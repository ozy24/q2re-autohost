ArrayToString(arr, delimiter := ", ") {
    if !arr || arr.Length = 0
        return ""
    result := arr[1]
    Loop arr.Length - 1 {
        result .= delimiter . arr[A_Index + 1]
    }
    return result
}

/* 
  Q2REAutohost.ahk - Quake II Remastered Listen Server Auto-Host
  Version: 2.1.1

  Automates launching, configuring, and managing a multiplayer listen server 
  in the Quake II Remastered Edition (Kex engine) for Steam or GOG.

  Features:
  - Full GUI management interface with system tray integration
  - Manual Start/Stop AutoHost controls (stopped by default)
  - Browse and configure game executable path from GUI
  - Auto-starts and configures the game menu to host a match
  - Gracefully quits and restarts the game at scheduled times
  - Detects and closes common crash dialogs
  - Sends scheduled reminder messages at configurable intervals
  - Validates configuration on startup
  - Retry logic for failed game launches
  - Prevents race conditions during concurrent restart attempts
  - Caches window handles for improved performance
  - Real-time log viewer and status monitoring

  The Kex remaster does not support dedicated servers. This script makes 
  listen servers more reliable by auto-recovering from common crashes and instabilities.

  Please refer to README.MD for setup details.
*/

/*
 Changelog:
 2.1.1
   - Expanded crash dialog detection to capture full window text
   - Added configurable handling for Visual C++ runtime error dialogs
   - Improved crash dialog dismissal button handling
 2.1.0
   - Added Config tab bindings for Reminder Messages with Add/Update/Remove buttons
   - Implemented reminder binding clipboard commands
   - Added unsaved changes tracking with UI indicator
   - Added clipboard generation and keybinding reminder sequence
   - Centered unsaved changes label and aligned save/reload controls
   - Fixed map property access in reminder timers
*/

#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode("Input")
TraySetIcon(A_ScriptDir "\icon.png")

; --- Global Variables ---
global ScriptVersion := "2.1.1"
global LastRunTime := ""
global DebugMode := true
global RestartTimes := []
global CrashMessages := []
global GamePath := ""
global WindowTitle := ""
global ExeName := ""
global ExecConfigs := []
global ReminderBindings := []
global MessageInterval := 300000
global MessageDelay := 500
global GameIsStarting := false
global CachedGameWindow := 0
global GameLaunchRetries := 0
global MaxRetries := 3
global StartupWaitTime := 15000
global ProcessCloseWaitTime := 10000
global MenuNavigationDelay := 500
global ExecConfigDelay := 500
global ScheduledQuitPending := false
global ScheduledQuitTime := ""
global AutoStartEnabled := false
global UnsavedChanges := false
global SuppressUnsavedTracking := false

; --- GUI Variables ---
global MainGui := ""
global StatusText := ""
global NextRestartText := ""
global MonitoringText := ""
global LogControl := ""
global MonitoringEnabled := true
global AutoHostRunning := false
global GamePathEdit := ""
global AutoHostStatusText := ""
global AutoStartCheckbox := ""
global UnsavedLabel := ""

; --- Config Tab GUI Controls ---
global ConfigGamePathEdit := ""
global ConfigGamePathBrowseBtn := ""
global ConfigWindowTitleEdit := ""
global ConfigExeNameEdit := ""
global ConfigRestartTimesEdit := ""
global ConfigStartupWaitEdit := ""
global ConfigProcessCloseWaitEdit := ""
global ConfigMenuDelayEdit := ""
global ConfigExecDelayEdit := ""
global ConfigExecConfigsEdit := ""
global ConfigCrashMessagesEdit := ""
global ConfigDebugCheckbox := ""

; --- Messages Tab GUI Controls ---
global MessagesIntervalEdit := ""
global MessagesDelayEdit := ""
global MessagesKeyEdit := ""
global MessagesTextEdit := ""
global MessagesListView := ""
global MessagesCommandsEdit := ""


; --- Read config.ini ---
ReadConfig() {
    global RestartTimes, DebugMode, CrashMessages, GamePath, WindowTitle, ExeName, ExecConfigs, MessageInterval, MessageDelay
    global StartupWaitTime, ProcessCloseWaitTime, MenuNavigationDelay, ExecConfigDelay, AutoStartEnabled, ReminderBindings
    iniPath := A_ScriptDir "\config.ini"

    times := IniRead(iniPath, "Settings", "RestartTimes", "06:00,17:00")
    RestartTimes := StrSplit(times, ",")

    dbg := IniRead(iniPath, "Settings", "Debug", "true")
    DebugMode := (StrLower(dbg) = "true")

    crashList := IniRead(iniPath, "Settings", "CrashMessages", "Exception caught in main,ERROR_DEVICE_LOST,Z_Free: bad magic,Debug Error!,Run-Time Check Failure #3")
    CrashMessages := StrSplit(crashList, ",")

    GamePath := IniRead(iniPath, "Settings", "GamePath", "")
    WindowTitle := IniRead(iniPath, "Settings", "WindowTitle", "Quake II")
    ExeName := IniRead(iniPath, "Settings", "ExeName", "quake2ex_steam.exe")

    configList := IniRead(iniPath, "Settings", "ExecConfigs", "ffa.cfg")
    rawConfigs := StrSplit(configList, ",")
    ExecConfigs := []
    seenConfigs := Map()
    warnings := []
    SplitPath(GamePath, , &gameDir)
    baseq2Dir := gameDir ? gameDir "\rerelease\baseq2\" : ""

    for cfg in rawConfigs {
        cleanCfg := Trim(cfg)
        if (cleanCfg = "")
            continue

        cfgKey := StrLower(cleanCfg)
        if (seenConfigs.Has(cfgKey)) {
            warnings.Push("Duplicate ExecConfig entry ignored: " . cleanCfg)
            continue
        }
        seenConfigs[cfgKey] := true

        ; Warn if the referenced config is missing locally when using relative names
        if !(InStr(cleanCfg, "\") || InStr(cleanCfg, "/") || InStr(cleanCfg, ":")) {
            cfgPath := baseq2Dir ? baseq2Dir . cleanCfg : ""
            if (!cfgPath || !FileExist(cfgPath)) {
                warnings.Push("Config not found in baseq2 directory: " . cleanCfg)
            }
        } else if !FileExist(cleanCfg) {
            warnings.Push("Config path does not exist: " . cleanCfg)
        }

        ExecConfigs.Push(cleanCfg)
    }

    if (ExecConfigs.Length = 0)
        Log("No ExecConfigs defined; skipping auto-exec on launch")
    else
        Log("ExecConfigs loaded: " . ArrayToString(ExecConfigs, ", "))

    for warning in warnings {
        Log("WARNING: " . warning)
    }

    ; --- Load timing configuration ---
    StartupWaitTime := Number(IniRead(iniPath, "Settings", "StartupWaitTime", "15000"))
    ProcessCloseWaitTime := Number(IniRead(iniPath, "Settings", "ProcessCloseWaitTime", "10000"))
    MenuNavigationDelay := Number(IniRead(iniPath, "Settings", "MenuNavigationDelay", "500"))
    ExecConfigDelay := Number(IniRead(iniPath, "Settings", "ExecConfigDelay", "500"))
    autoStart := IniRead(iniPath, "Settings", "AutoStart", "false")
    AutoStartEnabled := (StrLower(autoStart) = "true")

    ; --- Load scheduled messages ---
    MessageInterval := Number(IniRead(iniPath, "Messages", "Interval", "5")) * 60000
    MessageDelay := Number(IniRead(iniPath, "Messages", "BetweenDelay", "500"))

    ReminderBindings := []
    i := 1
    while true {
        keyEntry := IniRead(iniPath, "Messages", "Message" . i . "Key", "__missing__")
        textEntry := IniRead(iniPath, "Messages", "Message" . i . "Text", "__missing__")
        legacyEntry := IniRead(iniPath, "Messages", "Message" . i, "__missing__")

        if (keyEntry = "__missing__" && textEntry = "__missing__" && legacyEntry = "__missing__")
            break

        keyValue := (keyEntry = "__missing__") ? "" : Trim(keyEntry)
        textValue := ""
        if (textEntry != "__missing__")
            textValue := Trim(textEntry)
        else if (legacyEntry != "__missing__")
            textValue := Trim(legacyEntry)

        if (keyValue != "" || textValue != "") {
            binding := Map()
            binding["Key"] := keyValue
            binding["Text"] := textValue
            ReminderBindings.Push(binding)
        }
        i++
    }

    if (AutoStartCheckbox)
        AutoStartCheckbox.Value := AutoStartEnabled

    PopulateConfigTab()
    PopulateMessagesTab()
    ClearUnsavedChanges()

    ; --- Validate configuration ---
    ValidateConfig()
}

; --- Validate configuration values ---
ValidateConfig() {
    global GamePath, ExeName, RestartTimes, MessageInterval, MessageDelay
    global StartupWaitTime, ProcessCloseWaitTime, MenuNavigationDelay, ExecConfigDelay
    
    errors := []
    
    ; Check GamePath exists
    if (GamePath = "" || !FileExist(GamePath)) {
        errors.Push("GamePath is invalid or file does not exist: " . GamePath)
    }
    
    ; Validate restart times format (HH:MM)
    for time in RestartTimes {
        cleanTime := Trim(time)
        if !RegExMatch(cleanTime, "^\d{2}:\d{2}$") {
            errors.Push("Invalid RestartTime format: " . cleanTime . " (expected HH:MM)")
        }
    }
    
    ; Validate positive timing values
    if (MessageInterval <= 0)
        errors.Push("MessageInterval must be positive")
    if (MessageDelay < 0)
        errors.Push("MessageDelay cannot be negative")
    if (StartupWaitTime <= 0)
        errors.Push("StartupWaitTime must be positive")
    if (ProcessCloseWaitTime <= 0)
        errors.Push("ProcessCloseWaitTime must be positive")
    if (MenuNavigationDelay < 0)
        errors.Push("MenuNavigationDelay cannot be negative")
    if (ExecConfigDelay < 0)
        errors.Push("ExecConfigDelay cannot be negative")
    
    ; Show errors and exit if validation fails
    if (errors.Length > 0) {
        errorMsg := "Configuration validation failed:`n`n"
        for err in errors {
            errorMsg .= "• " . err . "`n"
        }
        errorMsg .= "`nPlease check your config.ini file."
        MsgBox(errorMsg, "Configuration Error", 16)
        ExitApp()
    }
    
    Log("Configuration validated successfully")
}

PopulateConfigTab() {
    global ConfigGamePathEdit, ConfigWindowTitleEdit, ConfigExeNameEdit
    global ConfigRestartTimesEdit, ConfigStartupWaitEdit, ConfigProcessCloseWaitEdit
    global ConfigMenuDelayEdit, ConfigExecDelayEdit, ConfigExecConfigsEdit
    global ConfigCrashMessagesEdit, ConfigDebugCheckbox
    global GamePath, WindowTitle, ExeName, RestartTimes, StartupWaitTime, ProcessCloseWaitTime
    global MenuNavigationDelay, ExecConfigDelay, ExecConfigs, CrashMessages
    global DebugMode, SuppressUnsavedTracking

    SuppressUnsavedTracking := true
    if !ConfigGamePathEdit {
        SuppressUnsavedTracking := false
        return
    }

    ConfigGamePathEdit.Value := GamePath
    if ConfigWindowTitleEdit
        ConfigWindowTitleEdit.Value := WindowTitle
    if ConfigExeNameEdit
        ConfigExeNameEdit.Value := ExeName
    if ConfigRestartTimesEdit
        ConfigRestartTimesEdit.Value := ArrayToString(RestartTimes, ", ")
    if ConfigStartupWaitEdit
        ConfigStartupWaitEdit.Value := StartupWaitTime
    if ConfigProcessCloseWaitEdit
        ConfigProcessCloseWaitEdit.Value := ProcessCloseWaitTime
    if ConfigMenuDelayEdit
        ConfigMenuDelayEdit.Value := MenuNavigationDelay
    if ConfigExecDelayEdit
        ConfigExecDelayEdit.Value := ExecConfigDelay
    if ConfigExecConfigsEdit
        ConfigExecConfigsEdit.Value := ExecConfigs.Length ? ArrayToString(ExecConfigs, "`n") : ""
    if ConfigCrashMessagesEdit
        ConfigCrashMessagesEdit.Value := CrashMessages.Length ? ArrayToString(CrashMessages, "`n") : ""
    if ConfigDebugCheckbox
        ConfigDebugCheckbox.Value := DebugMode
    SuppressUnsavedTracking := false
}

PopulateMessagesTab() {
    global MessagesIntervalEdit, MessagesDelayEdit, MessagesListView
    global MessagesCommandsEdit, MessagesKeyEdit, MessagesTextEdit
    global MessageInterval, MessageDelay, ReminderBindings, SuppressUnsavedTracking

    SuppressUnsavedTracking := true
    if MessagesIntervalEdit
        MessagesIntervalEdit.Value := MessageInterval > 0 ? Round(MessageInterval / 60000, 2) : ""
    if MessagesDelayEdit
        MessagesDelayEdit.Value := MessageDelay
    if MessagesKeyEdit
        MessagesKeyEdit.Value := ""
    if MessagesTextEdit
        MessagesTextEdit.Value := ""

    if MessagesListView {
        MessagesListView.Delete()
        for binding in ReminderBindings {
            key := binding.Has("Key") ? binding["Key"] : ""
            text := binding.Has("Text") ? binding["Text"] : ""
            MessagesListView.Add("", key, text)
        }
    }

    UpdateMessagesCommandsPreview()
    SuppressUnsavedTracking := false
}

UpdateMessagesCommandsPreview() {
    global MessagesCommandsEdit, ReminderBindings

    if !MessagesCommandsEdit
        return

    lines := []
    dq := Chr(34)
    backslash := Chr(92)
    for binding in ReminderBindings {
        key := binding.Has("Key") ? Trim(binding["Key"]) : ""
        text := binding.Has("Text") ? binding["Text"] : ""
        if (key = "" && text = "")
            continue

        escapedText := StrReplace(text, dq, backslash . dq)
        if (key != "")
            lines.Push("bind " . key . " say " . dq . escapedText . dq)
        else
            lines.Push("say " . dq . escapedText . dq)
    }

    MessagesCommandsEdit.Value := lines.Length ? ArrayToString(lines, "`r`n") : ""
}

MarkUnsavedChanges(*) {
    global SuppressUnsavedTracking, UnsavedChanges, UnsavedLabel
    if SuppressUnsavedTracking
        return
    if !UnsavedChanges {
        UnsavedChanges := true
        if (UnsavedLabel)
            UnsavedLabel.Value := "Unsaved changes - click Save to persist."
    }
}

ClearUnsavedChanges() {
    global UnsavedChanges, UnsavedLabel
    UnsavedChanges := false
    if (UnsavedLabel)
        UnsavedLabel.Value := ""
}

MessagesListViewSelect(LV, RowNumber) {
    global MessagesKeyEdit, MessagesTextEdit, ReminderBindings

    if (RowNumber <= 0 || RowNumber > ReminderBindings.Length)
        return

    binding := ReminderBindings[RowNumber]
    if MessagesKeyEdit
        MessagesKeyEdit.Value := binding.Has("Key") ? binding["Key"] : ""
    if MessagesTextEdit
        MessagesTextEdit.Value := binding.Has("Text") ? binding["Text"] : ""
}

AddReminderBinding() {
    global MessagesKeyEdit, MessagesTextEdit, MessagesListView
    global ReminderBindings

    key := MessagesKeyEdit ? Trim(MessagesKeyEdit.Value) : ""
    message := MessagesTextEdit ? Trim(MessagesTextEdit.Value) : ""

    if (key = "") {
        MsgBox("Enter a key binding (single letter or key).", "Reminder Binding", 48)
        return
    }

    if (StrLen(key) > 1) {
        MsgBox("Key binding should be a single character.", "Reminder Binding", 48)
        return
    }

    if (message = "") {
        MsgBox("Enter a message for this binding.", "Reminder Binding", 48)
        return
    }

    key := StrLower(key)

    ; Prevent duplicate keys
    for entry in ReminderBindings {
        entryKey := entry.Has("Key") ? StrLower(entry["Key"]) : ""
        if (entryKey = key) {
            MsgBox("A binding for key '" . key . "' already exists. Use Update to modify it.", "Reminder Binding", 48)
            return
        }
    }

    binding := Map()
    binding["Key"] := key
    binding["Text"] := message
    ReminderBindings.Push(binding)
    MarkUnsavedChanges()

    PopulateMessagesTab()

    if MessagesListView {
        lastIndex := ReminderBindings.Length
        if (lastIndex > 0) {
            MessagesListView.Modify(lastIndex, "Select Focus")
            MessagesListViewSelect(MessagesListView, lastIndex)
        }
    }
}

UpdateReminderBinding() {
    global MessagesKeyEdit, MessagesTextEdit, MessagesListView
    global ReminderBindings

    key := MessagesKeyEdit ? Trim(MessagesKeyEdit.Value) : ""
    message := MessagesTextEdit ? Trim(MessagesTextEdit.Value) : ""

    if (key = "") {
        MsgBox("Enter a key binding (single letter or key).", "Reminder Binding", 48)
        return
    }

    if (StrLen(key) > 1) {
        MsgBox("Key binding should be a single character.", "Reminder Binding", 48)
        return
    }

    if (message = "") {
        MsgBox("Enter a message for this binding.", "Reminder Binding", 48)
        return
    }

    key := StrLower(key)

    if !MessagesListView {
        MsgBox("Select a binding to update from the list.", "Reminder Binding", 48)
        return
    }

    selectedIndex := MessagesListView.GetNext()
    if (!selectedIndex || selectedIndex > ReminderBindings.Length) {
        MsgBox("Select a binding to update from the list.", "Reminder Binding", 48)
        return
    }

    ; Check for duplicate key on a different row
    for idx, entry in ReminderBindings {
        if (idx = selectedIndex)
            continue
        entryKey := entry.Has("Key") ? StrLower(entry["Key"]) : ""
        if (entryKey = key) {
            MsgBox("A different binding already uses key '" . key . "'. Remove it first or choose another key.", "Reminder Binding", 48)
            return
        }
    }

    binding := Map()
    binding["Key"] := key
    binding["Text"] := message
    ReminderBindings[selectedIndex] := binding
    MarkUnsavedChanges()

    PopulateMessagesTab()

    if MessagesListView {
        MessagesListView.Modify(selectedIndex, "Select Focus")
        MessagesListViewSelect(MessagesListView, selectedIndex)
    }
}

RemoveReminderBinding() {
    global MessagesListView, ReminderBindings

    if !MessagesListView
        return

    row := MessagesListView.GetNext()
    if (!row)
        return

    ReminderBindings.RemoveAt(row)
    MarkUnsavedChanges()
    PopulateMessagesTab()
}

CopyReminderCommands() {
    global MessagesCommandsEdit

    if !MessagesCommandsEdit
        return

    text := MessagesCommandsEdit.Value
    if (Trim(text) = "") {
        MsgBox("There are no commands to copy. Add at least one reminder binding.", "Copy Commands", 48)
        return
    }

    A_Clipboard := text
    MsgBox("Commands copied to clipboard.", "Copy Commands", 64)
}
; --- Logging function ---
Log(msg) {
    global DebugMode, LogControl, MainGui
    if !DebugMode
        return

    static lock := false
    if lock {
        ; Optional: skip or retry
        return
    }

    lock := true
    try {
        logPath := A_ScriptDir "\debug_log.txt"
        maxSize := 1024 * 1024 ; 1 MB

        if FileExist(logPath) && FileGetSize(logPath) > maxSize {
            content := FileRead(logPath)
            content := SubStr(content, -51200) ; Keep last 50 KB
            FileDelete(logPath)
            FileAppend(content, logPath)
        }

        timestamp := "[" . FormatTime(, "HH:mm:ss") . "] "
        logLine := timestamp . msg . "`n"
        FileAppend(logLine, logPath)
        
        ; Update GUI log viewer
        if (LogControl && MainGui) {
            try {
                LogControl.Value .= logLine
                ; Auto-scroll to bottom
                SendMessage(0x115, 7, 0, LogControl.Hwnd)  ; WM_VSCROLL, SB_BOTTOM
            }
        }
    } catch as e {
        MsgBox("Log write failed: " . e.Message)
    }
    lock := false
}


; --- Launch and prepare Quake 2 ---
CheckAndStartGame(manualLaunch := false) {
    global GamePath, WindowTitle, ExeName, GameIsStarting, CachedGameWindow
    global GameLaunchRetries, MaxRetries, StartupWaitTime, ProcessCloseWaitTime, MenuNavigationDelay, MessageInterval, ExecConfigDelay
    global AutoHostRunning
    
    ; Only allow launches if AutoHost is running OR it's a manual launch from GUI
    if (!AutoHostRunning && !manualLaunch) {
        Log("Game launch blocked - AutoHost is not running (use manual controls to start game)")
        return false
    }
    
    ; Prevent concurrent launches
    if (GameIsStarting) {
        Log("Game launch already in progress - skipping")
        return false
    }
    
    GameIsStarting := true
    Log("Starting game..." . (manualLaunch ? " (manual launch)" : " (auto launch)"))

    ; Close existing process
    if (PID := ProcessExist(ExeName)) {
        ProcessClose(ExeName)
        Log("Closed existing process")
    }

    Sleep(ProcessCloseWaitTime)
    
    ; Attempt to launch game with retry logic
    try {
    Run(GamePath)
    } catch as e {
        Log("ERROR: Failed to launch game: " . e.Message)
        GameIsStarting := false
        
        if (GameLaunchRetries < MaxRetries) {
            GameLaunchRetries++
            Log("Retry attempt " . GameLaunchRetries . " of " . MaxRetries)
            
            ; Only retry if AutoHost is still running (or manual launch)
            if (AutoHostRunning || manualLaunch) {
                Sleep(5000)
                CheckAndStartGame(manualLaunch)
            } else {
                Log("Retry cancelled - AutoHost has been stopped")
                GameLaunchRetries := 0
            }
        } else {
            MsgBox("Failed to launch game after " . MaxRetries . " attempts.`n`nError: " . e.Message, "Launch Error", 16)
            GameLaunchRetries := 0
        }
        return false
    }
    
    Sleep(StartupWaitTime)

    ; Find and activate game window
    if WinExist(WindowTitle) {
        CachedGameWindow := WinExist(WindowTitle)
        WinActivate(CachedGameWindow)
        WinWaitActive(CachedGameWindow,, 10)
        Sleep(1000)
        Log("Game window found and activated (HWND: " . CachedGameWindow . ")")
        GameLaunchRetries := 0  ; Reset retry counter on success
    } else {
        Log("ERROR: Game window not found after launch")
        GameIsStarting := false
        
        if (GameLaunchRetries < MaxRetries) {
            GameLaunchRetries++
            Log("Retry attempt " . GameLaunchRetries . " of " . MaxRetries)
            
            ; Only retry if AutoHost is still running (or manual launch)
            if (AutoHostRunning || manualLaunch) {
                Sleep(5000)
                CheckAndStartGame(manualLaunch)
            } else {
                Log("Retry cancelled - AutoHost has been stopped")
                GameLaunchRetries := 0
            }
        } else {
            MsgBox("Game window not found after " . MaxRetries . " attempts.", "Launch Error", 16)
            GameLaunchRetries := 0
        }
        return false
    }

    ; Automate menu steps
    SendInput("{Esc}")
    Sleep(3000)
    SendInput("{Down down}")
    Sleep(100)
    SendInput("{Down up}")
    Sleep(MenuNavigationDelay)
    SendInput("{Enter down}")
    Sleep(100)
    SendInput("{Enter up}")
    Sleep(MenuNavigationDelay)
    SendInput("{Enter down}")
    Sleep(100)
    SendInput("{Enter up}")
    Sleep(MenuNavigationDelay)

    Loop 3 {
        SendInput("{Down down}")
        Sleep(100)
        SendInput("{Down up}")
        Sleep(MenuNavigationDelay)
    }

    SendInput("{Enter down}")
    Sleep(100)
    SendInput("{Enter up}")
    Sleep(MenuNavigationDelay)
    SendInput("{Enter down}")
    Sleep(100)
    SendInput("{Enter up}")
    Sleep(MenuNavigationDelay)

    Loop 4 {
        SendInput("{Down down}")
        Sleep(100)
        SendInput("{Down up}")
        Sleep(MenuNavigationDelay)
    }

    SendInput("{Enter down}")
    Sleep(100)
    SendInput("{Enter up}")
    Sleep(5000)

    ; Run config scripts
    WinActivate(CachedGameWindow)
    WinWaitActive(CachedGameWindow,, 3)
    Send("{SC029}")
    Sleep(MenuNavigationDelay)
    for cfg in ExecConfigs {
        Log("Executing config: " . cfg)
        Send("exec " . cfg)
        Sleep(ExecConfigDelay)
        Send("{enter}")
        Sleep(ExecConfigDelay)
        Log("Config command sent: " . cfg)
    }
    Sleep(500)
    Send("{SC029}")

    SetTimer(SendReminderMessage, MessageInterval)
    Log("Started reminder timer with interval: " . MessageInterval . "ms")
    
    global LastActionText
    if (LastActionText)
        LastActionText.Value := "Game started successfully at " . FormatTime(, "HH:mm:ss")
    
    GameIsStarting := false
    return true
}

MonitorGame() {
    global ExeName, GameIsStarting, MonitoringEnabled, AutoHostRunning
    
    ; Only monitor if AutoHost is running
    if (!AutoHostRunning) {
        return
    }
    
    ; Check if monitoring is enabled
    if (!MonitoringEnabled) {
        return
    }
    
    ; Don't interfere if game is already starting
    if (GameIsStarting) {
        return
    }
    
    if !ProcessExist(ExeName) {
        Log("Game not running - restarting")
        CheckAndStartGame()
    }
}

GetGameWindowHandle() {
    global CachedGameWindow, WindowTitle
    
    if (CachedGameWindow && WinExist("ahk_id " . CachedGameWindow)) {
        return CachedGameWindow
    }
    
    if WinExist(WindowTitle) {
        CachedGameWindow := WinExist(WindowTitle)
        return CachedGameWindow
    }
    
    winList := WinGetList()
    for hwnd in winList {
        title := WinGetTitle(hwnd)
        if InStr(title, "Quake II") {
            CachedGameWindow := hwnd
            return hwnd
        }
    }
    
    return 0
}

AnnounceScheduledRestart(hwnd) {
    if !hwnd
        return false
    
    WinActivate("ahk_id " . hwnd)
    if !WinWaitActive("ahk_id " . hwnd,, 5) {
        Log("Failed to focus game window for scheduled restart (HWND: " . hwnd . ")")
        return false
    }
    
    Send("say Server will be restarted in 1 minute.")
    Sleep(500)
    Send("{Enter}")
    Log(">>> Announced scheduled restart to players")
    return true
}

PerformScheduledQuit() {
    global ScheduledQuitPending, GameIsStarting, ExeName, ScheduledQuitTime
    
    scheduledTime := ScheduledQuitTime
    ScheduledQuitPending := false
    ScheduledQuitTime := ""
    
    if !ProcessExist(ExeName) {
        Log("Scheduled quit skipped – game process already stopped")
        GameIsStarting := false
        return
    }
    
    hwnd := GetGameWindowHandle()
    if !hwnd {
        Log("Scheduled quit aborted – unable to locate game window")
        GameIsStarting := false
        return
    }
    
    WinActivate("ahk_id " . hwnd)
    if !WinWaitActive("ahk_id " . hwnd,, 5) {
        Log("Scheduled quit aborted – could not activate game window")
        GameIsStarting := false
        return
    }
    
    Send("quit")
    Sleep(500)
    Send("{Enter}")
    Sleep(500)
    
    if (scheduledTime != "")
        Log(">>> Sent scheduled quit command (scheduled for " . scheduledTime . ")")
    else
        Log(">>> Sent scheduled quit command")
    
    GameIsStarting := false
}

CheckScheduledQuit() {
    global LastRunTime, RestartTimes, GameIsStarting, AutoHostRunning, ScheduledQuitPending
    
    ; Only check scheduled quits if AutoHost is running
    if (!AutoHostRunning) {
        return
    }
    
    nowTime := FormatTime(, "HH:mm")

    for time in RestartTimes {
        if (nowTime = Trim(time)) and (LastRunTime != nowTime) {
            LastRunTime := nowTime
            Log("Match found for scheduled quit: " . time)

            ; Prevent new launches during scheduled restart
            GameIsStarting := true

            if (ScheduledQuitPending) {
                Log("Scheduled quit already pending – skipping duplicate trigger")
                GameIsStarting := false
                return
            }

            hwnd := GetGameWindowHandle()
            if !hwnd {
                Log("No matching Quake II window found for scheduled quit")
                GameIsStarting := false
                return
            }

            if !AnnounceScheduledRestart(hwnd) {
                GameIsStarting := false
                return
            }

            ScheduledQuitPending := true
            ScheduledQuitTime := nowTime
            Log("Scheduled quit armed – executing in 60 seconds")
            SetTimer(PerformScheduledQuit, -60000)
            GameIsStarting := false
            return
        }
    }
}

SendReminderMessage() {
    global ReminderBindings, MessageDelay, AutoHostRunning
    
    ; Only send reminders if AutoHost is running
    if (!AutoHostRunning) {
        return
    }
    
    title := WinGetTitle("A")
    if !InStr(title, "Quake II") {
        Log("Skipped reminder — Quake II not focused (active window: " . title . ")")
        return
    }

    for binding in ReminderBindings {
        key := binding.Has("Key") ? Trim(binding["Key"]) : ""
        text := binding.Has("Text") ? binding["Text"] : ""

        if (key = "" && text = "")
            continue

        if (key != "") {
            Send("{" . key . " down}")
            Sleep(60)
            Send("{" . key . " up}")
            Log(">>> Fired reminder key '" . key . "'" . (text != "" ? " (" . text . ")" : ""))
        } else if (text != "") {
            Send(text)
            Sleep(120)
            Send("{Enter}")
            Log(">>> Sent reminder text: " . text)
        }

        Sleep(MessageDelay)
    }
}


GetCrashWindowText(hwnd) {
    if !hwnd
        return ""

    fullText := ""
    try {
        fullText := WinGetText("ahk_id " . hwnd)
    }

    staticControls := ["Static1", "Static2", "Static3", "Static4"]
    for ctrlName in staticControls {
        try {
            ctrlText := ControlGetText(ctrlName, hwnd)
            if (ctrlText != "" && !InStr(fullText, ctrlText)) {
                if (fullText != "" && SubStr(fullText, -1) != "`n")
                    fullText .= "`n"
                fullText .= ctrlText
            }
        }
    }

    return Trim(fullText)
}

DetectCrashSignature(text) {
    global CrashMessages

    if (text = "")
        return false

    for msg in CrashMessages {
        cleanMsg := Trim(msg)
        if (cleanMsg = "")
            continue
        if InStr(text, cleanMsg, false)
            return true
    }
    return false
}

DismissCrashWindow(hwnd, message) {
    if !hwnd
        return
    
    if !TryClickCrashButton(hwnd, "&Abort")
        if !TryClickCrashButton(hwnd, "&Retry")
            if !TryClickCrashButton(hwnd, "&Ignore")
                if !TryClickCrashButton(hwnd, "&OK")
                    WinClose("ahk_id " . hwnd)

    Sleep(200)
    Log(">>> Crash window detected and dismissed. Message: " . message)
}

TryClickCrashButton(hwnd, label) {
    try {
        ctrlHwnd := ControlGetHwnd(label, hwnd)
        if !ctrlHwnd
            return false
        ControlClick(label, "ahk_id " . hwnd)
        return true
    } catch {
        return false
    }
}

CheckCrashWindow() {
    global ExeName, CrashDetectionEnabled, AutoHostRunning
    
    ; Only check for crashes if AutoHost is running
    if (!AutoHostRunning) {
        return
    }
    
    ; Check if crash detection is enabled
    if (!CrashDetectionEnabled) {
        return
    }
    
    WinTitle := "ahk_class #32770 ahk_exe " . ExeName

    if !WinExist(WinTitle)
        return

    hwnd := WinExist(WinTitle)
    text := GetCrashWindowText(hwnd)

    if (text = "")
        return

    if DetectCrashSignature(text) {
        DismissCrashWindow(hwnd, text)
        return
    }

    ; Handle known Visual C++ runtime dialogs even if not configured explicitly
    if (InStr(text, "Debug Error!", false) || InStr(text, "Run-Time Check Failure", false)) {
        DismissCrashWindow(hwnd, text)
    }
}

; --- GUI Functions ---

CreateGUI() {
    global MainGui, StatusText, NextRestartText, MonitoringText, LogControl, ScriptVersion, GamePathEdit, AutoHostStatusText, GamePath, UnsavedLabel
    global ConfigGamePathEdit, ConfigGamePathBrowseBtn, ConfigWindowTitleEdit, ConfigExeNameEdit
    global ConfigRestartTimesEdit, ConfigStartupWaitEdit, ConfigProcessCloseWaitEdit
    global ConfigMenuDelayEdit, ConfigExecDelayEdit, ConfigExecConfigsEdit, ConfigCrashMessagesEdit
    global ConfigDebugCheckbox, AutoStartCheckbox
    global MessagesIntervalEdit, MessagesDelayEdit, MessagesKeyEdit, MessagesTextEdit, MessagesListView, MessagesCommandsEdit
    global AutoStartEnabled, DebugMode, RestartTimes, StartupWaitTime, ProcessCloseWaitTime
    global MenuNavigationDelay, ExecConfigDelay, ExecConfigs, CrashMessages, MessageInterval, MessageDelay, ReminderBindings
    
    MainGui := Gui("+Resize", "Q2RE AutoHost Manager v" . ScriptVersion)
    iconPath := A_ScriptDir "\icon.png"
    if FileExist(iconPath) {
        try MainGui.SetIcon(iconPath)
    }
    MainGui.OnEvent("Close", (*) => MainGui.Hide())  ; Hide instead of close
    MainGui.OnEvent("Size", GuiResize)
    
    ; Create Tab control
    Tab := MainGui.Add("Tab3", "x10 y10 w660 h640", ["Status", "Config", "Messages", "Controls", "Logs", "About"])
    
    ; === STATUS TAB ===
    Tab.UseTab("Status")
    
    ; AutoHost Status Section
    MainGui.Add("GroupBox", "x30 y50 w620 h140", "AutoHost Status")
    MainGui.Add("Text", "x50 y80 w120", "AutoHost State:")
    AutoHostStatusText := MainGui.Add("Text", "x180 y80 w200 cRed", "● STOPPED")
    
    global StartAutoHostBtn := MainGui.Add("Button", "x400 y75 w110 h30", "Start AutoHost")
    StartAutoHostBtn.OnEvent("Click", (*) => StartAutoHost())
    global StopAutoHostBtn := MainGui.Add("Button", "x520 y75 w110 h30 Disabled", "Stop AutoHost")
    StopAutoHostBtn.OnEvent("Click", (*) => StopAutoHost())
    
    MainGui.Add("Text", "x50 y120", "Game Path:")
    GamePathEdit := MainGui.Add("Edit", "x50 y140 w490 r1 ReadOnly", GamePath)
    MainGui.Add("Button", "x550 y140 w80 h25", "Browse...").OnEvent("Click", (*) => BrowseGamePath())
    
    ; Game Status Section
    MainGui.Add("GroupBox", "x30 y200 w620 h140", "Game Status")
    MainGui.Add("Text", "x50 y230 w120", "Game Status:")
    StatusText := MainGui.Add("Text", "x180 y230 w450", "Not running")
    
    MainGui.Add("Text", "x50 y260 w120", "Process:")
    global ProcessText := MainGui.Add("Text", "x180 y260 w450", "Not running")
    
    MainGui.Add("Text", "x50 y290 w120", "Last Action:")
    global LastActionText := MainGui.Add("Text", "x180 y290 w450", "AutoHost stopped - click Start AutoHost to begin")
    
    ; Schedule & Monitoring Section
    MainGui.Add("GroupBox", "x30 y350 w620 h130", "Schedule & Monitoring")
    MainGui.Add("Text", "x50 y380 w120", "Next Restart:")
    NextRestartText := MainGui.Add("Text", "x180 y380 w450", "Not scheduled (AutoHost stopped)")
    
    MainGui.Add("Text", "x50 y410 w120", "Monitoring:")
    MonitoringText := MainGui.Add("Text", "x180 y410 w450", "Inactive")
    
    MainGui.Add("Text", "x50 y440 w120", "Reminder Timer:")
    global ReminderTimerText := MainGui.Add("Text", "x180 y440 w450", "Inactive")
    
    ; === CONFIG TAB ===
    Tab.UseTab("Config")

    ; General Settings
    MainGui.Add("GroupBox", "x30 y50 w620 h180", "General Settings")
    MainGui.Add("Text", "x50 y80 w130", "Game Path:")
    ConfigGamePathEdit := MainGui.Add("Edit", "x190 y78 w360 r1", GamePath)
    ConfigGamePathBrowseBtn := MainGui.Add("Button", "x560 y78 w70 h24", "Browse...")
    ConfigGamePathBrowseBtn.OnEvent("Click", (*) => ConfigSelectGamePath())
    ConfigGamePathEdit.OnEvent("Change", MarkUnsavedChanges)

    MainGui.Add("Text", "x50 y115 w130", "Window Title:")
    ConfigWindowTitleEdit := MainGui.Add("Edit", "x190 y113 w440 r1", WindowTitle)
    ConfigWindowTitleEdit.OnEvent("Change", MarkUnsavedChanges)

    MainGui.Add("Text", "x50 y150 w130", "Executable Name:")
    ConfigExeNameEdit := MainGui.Add("Edit", "x190 y148 w220 r1", ExeName)
    ConfigExeNameEdit.OnEvent("Change", MarkUnsavedChanges)

    AutoStartCheckbox := MainGui.Add("Checkbox", "x430 y147", "Start AutoHost on script launch")
    AutoStartCheckbox.Value := AutoStartEnabled
    AutoStartCheckbox.OnEvent("Click", (*) => ToggleAutoStart())

    ConfigDebugCheckbox := MainGui.Add("Checkbox", "x190 y182", "Enable debug logging (writes debug_log.txt)")
    ConfigDebugCheckbox.Value := DebugMode
    ConfigDebugCheckbox.OnEvent("Click", (*) => ToggleDebugMode())

    ; Scheduling & Delays
    MainGui.Add("GroupBox", "x30 y240 w620 h110", "Scheduling & Delays")
    MainGui.Add("Text", "x50 y270 w130", "Restart Times (HH:MM):")
    ConfigRestartTimesEdit := MainGui.Add("Edit", "x190 y268 w440 r1", ArrayToString(RestartTimes, ", "))
    ConfigRestartTimesEdit.OnEvent("Change", MarkUnsavedChanges)

    MainGui.Add("Text", "x50 y300 w130", "Startup Wait (ms):")
    ConfigStartupWaitEdit := MainGui.Add("Edit", "x190 y298 w120 r1", StartupWaitTime)
    ConfigStartupWaitEdit.OnEvent("Change", MarkUnsavedChanges)

    MainGui.Add("Text", "x330 y300 w170", "Process Close Wait (ms):")
    ConfigProcessCloseWaitEdit := MainGui.Add("Edit", "x520 y298 w110 r1", ProcessCloseWaitTime)
    ConfigProcessCloseWaitEdit.OnEvent("Change", MarkUnsavedChanges)

    MainGui.Add("Text", "x50 y330 w130", "Menu Delay (ms):")
    ConfigMenuDelayEdit := MainGui.Add("Edit", "x190 y328 w120 r1", MenuNavigationDelay)
    ConfigMenuDelayEdit.OnEvent("Change", MarkUnsavedChanges)

    MainGui.Add("Text", "x330 y330 w170", "Exec Config Delay (ms):")
    ConfigExecDelayEdit := MainGui.Add("Edit", "x520 y328 w110 r1", ExecConfigDelay)
    ConfigExecDelayEdit.OnEvent("Change", MarkUnsavedChanges)

    ; Exec configs & crash signatures
    MainGui.Add("GroupBox", "x30 y360 w620 h150", "Exec Configs & Crash Signatures")
    MainGui.Add("Text", "x50 y390 w120", "Exec Configs:")
    ConfigExecConfigsEdit := MainGui.Add("Edit", "x50 y410 w260 h80 +VScroll", ExecConfigs.Length ? ArrayToString(ExecConfigs, "`n") : "")
    ConfigExecConfigsEdit.OnEvent("Change", MarkUnsavedChanges)
    MainGui.Add("Text", "x330 y390 w130", "Crash Messages:")
    ConfigCrashMessagesEdit := MainGui.Add("Edit", "x330 y410 w300 h80 +VScroll", CrashMessages.Length ? ArrayToString(CrashMessages, "`n") : "")
    ConfigCrashMessagesEdit.OnEvent("Change", MarkUnsavedChanges)
    MainGui.Add("Text", "x50 y495 w260", "One entry per line. Relative config paths resolve from baseq2.")

    MainGui.Add("Button", "x50 y560 w150 h28", "Save Configuration").OnEvent("Click", (*) => SaveConfigChanges())
    MainGui.Add("Button", "x210 y560 w150 h28", "Reload From File").OnEvent("Click", (*) => ReloadConfig())

    ; === MESSAGES TAB ===
    Tab.UseTab("Messages")
    MainGui.Add("GroupBox", "x30 y50 w620 h160", "Reminder Timing")
    MainGui.Add("Text", "x50 y85 w170", "Reminder Interval (minutes):")
    MessagesIntervalEdit := MainGui.Add("Edit", "x230 y83 w120 r1", MessageInterval > 0 ? Round(MessageInterval / 60000, 2) : "")
    MessagesIntervalEdit.OnEvent("Change", MarkUnsavedChanges)
    MainGui.Add("Text", "x50 y125 w170", "Delay between keys (ms):")
    MessagesDelayEdit := MainGui.Add("Edit", "x230 y123 w120 r1", MessageDelay)
    MessagesDelayEdit.OnEvent("Change", MarkUnsavedChanges)
    MainGui.Add("Text", "x380 y85 w230", "Set how often the script cycles through the bindings.")

    MainGui.Add("GroupBox", "x30 y230 w620 h190", "Reminder Bindings")
    MainGui.Add("Text", "x50 y265 w80", "Key:")
    MessagesKeyEdit := MainGui.Add("Edit", "x120 y263 w80 r1 Limit1", "")
    MainGui.Add("Text", "x210 y265 w80", "Message:")
    MessagesTextEdit := MainGui.Add("Edit", "x280 y263 w320 r1", "")
    MainGui.Add("Button", "x50 y295 w100 h26", "Add").OnEvent("Click", (*) => AddReminderBinding())
    MainGui.Add("Button", "x160 y295 w100 h26", "Update").OnEvent("Click", (*) => UpdateReminderBinding())
    MainGui.Add("Button", "x270 y295 w140 h26", "Remove Selected").OnEvent("Click", (*) => RemoveReminderBinding())
    MessagesListView := MainGui.Add("ListView", "x50 y330 w580 h70 +AltSubmit -Multi", ["Key", "Message"])
    MessagesListView.OnEvent("Click", MessagesListViewSelect)

    MainGui.Add("GroupBox", "x30 y430 w620 h150", "Copy Bind Commands")
    MainGui.Add("Text", "x50 y460 w540", "Copy these lines into your Quake II config to mirror the bindings above:")
    MessagesCommandsEdit := MainGui.Add("Edit", "x50 y485 w580 h70 ReadOnly -Wrap +VScroll", "")
    MainGui.Add("Button", "x50 y560 w150 h28", "Copy to Clipboard").OnEvent("Click", (*) => CopyReminderCommands())

    MainGui.Add("Button", "x220 y560 w150 h28", "Save Configuration").OnEvent("Click", (*) => SaveConfigChanges())
    MainGui.Add("Button", "x380 y560 w150 h28", "Reload From File").OnEvent("Click", (*) => ReloadConfig())

    ; === CONTROLS TAB ===
    Tab.UseTab("Controls")
    
    MainGui.Add("GroupBox", "x30 y50 w620 h120", "Manual Game Controls")
    MainGui.Add("Text", "x50 y75", "Use these controls to manually start/stop the game without affecting AutoHost:")
    MainGui.Add("Button", "x50 y100 w140 h35", "Start Game").OnEvent("Click", (*) => ManualStartGame())
    MainGui.Add("Button", "x200 y100 w140 h35", "Stop Game").OnEvent("Click", (*) => StopGame())
    MainGui.Add("Button", "x350 y100 w140 h35", "Restart Game").OnEvent("Click", (*) => RestartGame())
    MainGui.Add("Button", "x500 y100 w130 h35", "Force Quit").OnEvent("Click", (*) => ForceQuitGame())
    
    MainGui.Add("GroupBox", "x30 y180 w620 h120", "Script Controls")
    MainGui.Add("Button", "x50 y210 w180 h35", "Send Test Message").OnEvent("Click", (*) => SendTestMessage())
    MainGui.Add("Button", "x240 y210 w180 h35", "Reload Config").OnEvent("Click", (*) => ReloadConfig())
    MainGui.Add("Button", "x430 y210 w200 h35", "Open Config File").OnEvent("Click", (*) => OpenConfigFile())
    
    MainGui.Add("GroupBox", "x30 y310 w620 h190", "AutoHost Settings")
    MainGui.Add("Text", "x50 y340", "These settings only apply when AutoHost is running:")

    global MonitorCheckbox := MainGui.Add("Checkbox", "x50 y370 Checked", "Enable Auto-Monitoring (auto-restart if game crashes)")
    MonitorCheckbox.OnEvent("Click", (*) => ToggleMonitoring())
    
    global CrashCheckbox := MainGui.Add("Checkbox", "x50 y400 Checked", "Enable Crash Dialog Detection")
    CrashCheckbox.OnEvent("Click", (*) => ToggleCrashDetection())
    
    MainGui.Add("Text", "x50 y430", "Auto-start and other configuration options now live under the Config tab.")
    MainGui.Add("Text", "x50 y460", "Note: Scheduled restarts are always active when AutoHost is running.")
    
    ; === LOGS TAB ===
    Tab.UseTab("Logs")
    LogControl := MainGui.Add("Edit", "x30 y50 w620 h390 ReadOnly -Wrap +VScroll")
    MainGui.Add("Button", "x30 y450 w140 h35", "Clear Logs").OnEvent("Click", (*) => ClearLogsGUI())
    MainGui.Add("Button", "x180 y450 w140 h35", "Refresh Logs").OnEvent("Click", (*) => RefreshLogs())
    MainGui.Add("Button", "x330 y450 w160 h35", "Open Log File").OnEvent("Click", (*) => OpenLogFile())
    
    ; === ABOUT TAB ===
    Tab.UseTab("About")
    aboutTitle := MainGui.Add("Text", "x20 y60 w640 Center", "Q2RE AutoHost")
    aboutTitle.SetFont("s8 bold", "Segoe UI")
    MainGui.Add("Text", "x20 y100 w640 Center", "Version: " . ScriptVersion)
    MainGui.Add("Text", "x20 y130 w640 Center", 'by ozy')
    MainGui.Add("Text", "x40 y160 w600 Center", 'https://github.com/ozy24/q2re-autohost')

    
    Tab.UseTab()  ; End tab definition
    
    UnsavedLabel := MainGui.Add("Text", "x30 y600 w620 cRed Center", "")
    
    ; Create system tray menu
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Show Window", (*) => MainGui.Show())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Start AutoHost", (*) => StartAutoHost())
    A_TrayMenu.Add("Stop AutoHost", (*) => StopAutoHost())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Start Game", (*) => ManualStartGame())
    A_TrayMenu.Add("Stop Game", (*) => StopGame())
    A_TrayMenu.Add("Restart Game", (*) => RestartGame())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Show Window"
    
    ; Load existing logs
    RefreshLogs()
    
    MainGui.Show("w680 h680")
    PopulateMessagesTab()
    ClearUnsavedChanges()
    Log("GUI initialized - AutoHost stopped, waiting for user to start")
}

GuiResize(GuiObj, MinMax, Width, Height) {
    ; Handle window resize if needed
}

UpdateGUIStatus() {
    global StatusText, ProcessText, NextRestartText, LastActionText, MonitoringText, ReminderTimerText
    global ExeName, MainGui, MonitoringEnabled, AutoHostRunning, AutoHostStatusText
    
    if !MainGui
        return
    
    try {
        ; Update AutoHost status
        if (AutoHostRunning) {
            AutoHostStatusText.Value := "● RUNNING"
            AutoHostStatusText.Opt("cGreen")
        } else {
            AutoHostStatusText.Value := "● STOPPED"
            AutoHostStatusText.Opt("cRed")
        }
        
        ; Update game status
        if ProcessExist(ExeName) {
            pid := ProcessExist(ExeName)
            StatusText.Value := "Running ✓"
            ProcessText.Value := ExeName . " (PID: " . pid . ")"
        } else {
            StatusText.Value := "Not Running ✗"
            ProcessText.Value := "Not running"
        }
        
        ; Calculate next restart
        if (AutoHostRunning) {
            nextRestart := GetNextRestartTime()
            NextRestartText.Value := nextRestart
        } else {
            NextRestartText.Value := "Not scheduled (AutoHost stopped)"
        }
        
        ; Update monitoring status
        if (AutoHostRunning && MonitoringEnabled)
            MonitoringText.Value := "Active ✓"
        else if (AutoHostRunning && !MonitoringEnabled)
            MonitoringText.Value := "Disabled (but AutoHost running)"
        else
            MonitoringText.Value := "Inactive (AutoHost stopped)"
        
        ; Update reminder timer status
        global MessageInterval
        if (AutoHostRunning && MessageInterval > 0)
            ReminderTimerText.Value := "Active (every " . Round(MessageInterval / 60000) . " minutes)"
        else if (AutoHostRunning)
            ReminderTimerText.Value := "Disabled"
        else
            ReminderTimerText.Value := "Inactive (AutoHost stopped)"
    }
}

GetNextRestartTime() {
    global RestartTimes
    now := FormatTime(, "HH:mm")
    nowMinutes := SubStr(now, 1, 2) * 60 + SubStr(now, 4, 2)
    
    for time in RestartTimes {
        cleanTime := Trim(time)
        timeMinutes := SubStr(cleanTime, 1, 2) * 60 + SubStr(cleanTime, 4, 2)
        
        if (timeMinutes > nowMinutes) {
            diff := timeMinutes - nowMinutes
            hours := Floor(diff / 60)
            mins := Mod(diff, 60)
            return cleanTime . " (in " . hours . "h " . mins . "m)"
        }
    }
    
    ; Next restart is tomorrow
    if (RestartTimes.Length > 0) {
        firstTime := Trim(RestartTimes[1])
        return firstTime . " (tomorrow)"
    }
    
    return "No restarts scheduled"
}

StartAutoHost() {
    global AutoHostRunning, StartAutoHostBtn, StopAutoHostBtn, LastActionText
    
    if (AutoHostRunning) {
        MsgBox("AutoHost is already running.", "Q2RE AutoHost", 48)
        return
    }
    
    Log("=== AutoHost STARTED ===")
    AutoHostRunning := true
    
    ; Enable/disable buttons
    StartAutoHostBtn.Enabled := false
    StopAutoHostBtn.Enabled := true
    
    if (LastActionText)
        LastActionText.Value := "AutoHost started at " . FormatTime(, "HH:mm:ss")
    
    ; Start all monitoring timers (UpdateGUIStatus already running from init)
    SetTimer(MonitorGame, 5000)
    SetTimer(CheckScheduledQuit, 60000)
    SetTimer(CheckCrashWindow, 1000)
    
    Log("All monitoring timers activated")
    
    ; Start the game AFTER timers are set up
    CheckAndStartGame()
}

StopAutoHost() {
    global AutoHostRunning, StartAutoHostBtn, StopAutoHostBtn, LastActionText, ExeName
    global ScheduledQuitPending, ScheduledQuitTime
    
    if (!AutoHostRunning) {
        MsgBox("AutoHost is not running.", "Q2RE AutoHost", 48)
        return
    }
    
    result := MsgBox("Stop AutoHost?`n`nThis will stop all automatic monitoring and scheduled restarts.`nThe game will continue running unless you manually stop it.`n`nContinue?", "Stop AutoHost", 4 + 32)
    
    if (result = "Yes") {
        Log("=== AutoHost STOPPED ===")
        AutoHostRunning := false
        
        ; Enable/disable buttons
        StartAutoHostBtn.Enabled := true
        StopAutoHostBtn.Enabled := false
        
        if (LastActionText)
            LastActionText.Value := "AutoHost stopped at " . FormatTime(, "HH:mm:ss")
        
        ; Stop all timers except GUI update
        SetTimer(MonitorGame, 0)
        SetTimer(CheckScheduledQuit, 0)
        SetTimer(CheckCrashWindow, 0)
        SetTimer(SendReminderMessage, 0)
        if (ScheduledQuitPending) {
            SetTimer(PerformScheduledQuit, 0)
            ScheduledQuitPending := false
            ScheduledQuitTime := ""
            Log("Scheduled quit cancelled because AutoHost was stopped")
        }
        
        Log("All monitoring timers deactivated")
        MsgBox("AutoHost stopped.`n`nNote: The game is still running. Use 'Stop Game' if you want to close it.", "Q2RE AutoHost", 64)
    }
}

BrowseGamePath() {
    global GamePath, GamePathEdit, ConfigGamePathEdit
    
    selectedFile := FileSelect(3, GamePath, "Select Quake II Executable", "Executable Files (*.exe)")
    
    if (selectedFile != "") {
        GamePath := selectedFile
        if (GamePathEdit)
            GamePathEdit.Value := selectedFile
        if (ConfigGamePathEdit)
            ConfigGamePathEdit.Value := selectedFile
        
        ; Update config file
        IniWrite(selectedFile, A_ScriptDir "\config.ini", "Settings", "GamePath")
        
        Log("Game path updated to: " . selectedFile)
        MsgBox("Game path updated successfully!`n`nNew path: " . selectedFile . "`n`nThe configuration has been saved.", "Q2RE AutoHost", 64)
    }
}

ConfigSelectGamePath() {
    global ConfigGamePathEdit, GamePath

    startPath := GamePath
    if (ConfigGamePathEdit && Trim(ConfigGamePathEdit.Value) != "")
        startPath := ConfigGamePathEdit.Value

    selectedFile := FileSelect(3, startPath, "Select Quake II Executable", "Executable Files (*.exe)")

    if (selectedFile != "" && ConfigGamePathEdit)
        ConfigGamePathEdit.Value := selectedFile
}

ToggleDebugMode() {
    global DebugMode, ConfigDebugCheckbox
    DebugMode := ConfigDebugCheckbox.Value
    IniWrite(DebugMode ? "true" : "false", A_ScriptDir "\config.ini", "Settings", "Debug")
    Log("Debug logging " . (DebugMode ? "enabled" : "disabled"))
}

SaveConfigChanges() {
    global ConfigGamePathEdit, ConfigWindowTitleEdit, ConfigExeNameEdit
    global ConfigRestartTimesEdit, ConfigStartupWaitEdit, ConfigProcessCloseWaitEdit
    global ConfigMenuDelayEdit, ConfigExecDelayEdit, ConfigExecConfigsEdit
    global ConfigCrashMessagesEdit, AutoStartCheckbox, ConfigDebugCheckbox
    global MessagesIntervalEdit, MessagesDelayEdit, ReminderBindings
    global GamePath, WindowTitle, ExeName, RestartTimes, StartupWaitTime, ProcessCloseWaitTime
    global MenuNavigationDelay, ExecConfigDelay, ExecConfigs, CrashMessages, MessageInterval
    global MessageDelay, AutoStartEnabled, DebugMode, AutoHostRunning

    configPath := A_ScriptDir "\config.ini"
    errors := []

    newGamePath := Trim(ConfigGamePathEdit.Value)
    if (newGamePath = "")
        errors.Push("Game path cannot be blank.")
    else if !FileExist(newGamePath)
        errors.Push("Game path does not exist: " . newGamePath)

    newWindowTitle := Trim(ConfigWindowTitleEdit.Value)
    if (newWindowTitle = "")
        errors.Push("Window title cannot be blank.")

    newExeName := Trim(ConfigExeNameEdit.Value)
    if (newExeName = "")
        errors.Push("Executable name cannot be blank.")

    restartInput := StrReplace(Trim(ConfigRestartTimesEdit.Value), "`r")
    newRestartTimes := []
    if (restartInput != "") {
        restartTokens := StrSplit(StrReplace(restartInput, "`n", ","), ",")
        for token in restartTokens {
            timeValue := Trim(token)
            if (timeValue = "")
                continue
            if !RegExMatch(timeValue, "^\d{2}:\d{2}$") {
                errors.Push("Invalid restart time format: " . timeValue)
                continue
            }
            newRestartTimes.Push(timeValue)
        }
    }
    if (newRestartTimes.Length = 0)
        errors.Push("At least one restart time is required (HH:MM).")

    startupWaitText := Trim(ConfigStartupWaitEdit.Value)
    if !RegExMatch(startupWaitText, "^\d+$")
        errors.Push("Startup wait must be a positive number (ms).")
    startupWaitValue := Number(startupWaitText)
    if (startupWaitValue <= 0)
        errors.Push("Startup wait must be greater than zero.")

    processWaitText := Trim(ConfigProcessCloseWaitEdit.Value)
    if !RegExMatch(processWaitText, "^\d+$")
        errors.Push("Process close wait must be a positive number (ms).")
    processWaitValue := Number(processWaitText)
    if (processWaitValue <= 0)
        errors.Push("Process close wait must be greater than zero.")

    menuDelayText := Trim(ConfigMenuDelayEdit.Value)
    if !RegExMatch(menuDelayText, "^\d+$")
        errors.Push("Menu delay must be zero or a positive number (ms).")
    menuDelayValue := Number(menuDelayText)
    if (menuDelayValue < 0)
        errors.Push("Menu delay cannot be negative.")

    execDelayText := Trim(ConfigExecDelayEdit.Value)
    if !RegExMatch(execDelayText, "^\d+$")
        errors.Push("Exec config delay must be zero or a positive number (ms).")
    execDelayValue := Number(execDelayText)
    if (execDelayValue < 0)
        errors.Push("Exec config delay cannot be negative.")

    execConfigsRaw := StrReplace(ConfigExecConfigsEdit.Value, "`r")
    newExecConfigs := []
    execSeen := Map()
    if (Trim(execConfigsRaw) != "") {
        for line in StrSplit(execConfigsRaw, "`n") {
            cfg := Trim(line)
            if (cfg = "")
                continue
            key := StrLower(cfg)
            if execSeen.Has(key)
                continue
            execSeen[key] := true
            newExecConfigs.Push(cfg)
        }
    }

    crashRaw := StrReplace(ConfigCrashMessagesEdit.Value, "`r")
    newCrashMessages := []
    if (Trim(crashRaw) != "") {
        for line in StrSplit(crashRaw, "`n") {
            crash := Trim(line)
            if (crash = "")
                continue
            newCrashMessages.Push(crash)
        }
    }

    messageIntervalText := Trim(MessagesIntervalEdit.Value)
    if !RegExMatch(messageIntervalText, "^\d+(\.\d+)?$")
        errors.Push("Message interval must be a positive number of minutes.")
    messageIntervalMinutes := Number(messageIntervalText)
    if (messageIntervalMinutes <= 0)
        errors.Push("Message interval must be greater than zero.")
    messageIntervalMs := Round(messageIntervalMinutes * 60000)

    messageDelayText := Trim(MessagesDelayEdit.Value)
    if !RegExMatch(messageDelayText, "^\d+$")
        errors.Push("Delay between keys must be zero or a positive number (ms).")
    messageDelayValue := Number(messageDelayText)
    if (messageDelayValue < 0)
        errors.Push("Delay between keys cannot be negative.")

    normalizedBindings := []
    idx := 1
    for binding in ReminderBindings {
        key := binding.Has("Key") ? Trim(binding["Key"]) : ""
        text := binding.Has("Text") ? Trim(binding["Text"]) : ""

        if (key = "" && text = "")
            continue

        entryError := false

        if (key = "") {
            errors.Push("Reminder entry #" . idx . " is missing a key binding.")
            entryError := true
        } else if (StrLen(key) != 1) {
            errors.Push("Reminder entry #" . idx . " key must be a single character.")
            entryError := true
        }

        if (text = "") {
            errors.Push("Reminder entry #" . idx . " is missing a message.")
            entryError := true
        }

        if (!entryError) {
            normalized := Map()
            normalized["Key"] := StrLower(key)
            normalized["Text"] := text
            normalizedBindings.Push(normalized)
        }

        idx++
    }

    if (normalizedBindings.Length = 0)
        errors.Push("Add at least one reminder binding before saving.")

    if (errors.Length > 0) {
        errorText := "Cannot save configuration:`n`n"
        for err in errors
            errorText .= "• " . err . "`n"
        MsgBox(errorText, "Validation Errors", 16)
        return
    }

    ; Persist Settings
    IniWrite(newGamePath, configPath, "Settings", "GamePath")
    IniWrite(newWindowTitle, configPath, "Settings", "WindowTitle")
    IniWrite(newExeName, configPath, "Settings", "ExeName")
    IniWrite(ArrayToString(newRestartTimes, ", "), configPath, "Settings", "RestartTimes")
    IniWrite(newExecConfigs.Length ? ArrayToString(newExecConfigs, ", ") : "", configPath, "Settings", "ExecConfigs")
    IniWrite(execDelayText, configPath, "Settings", "ExecConfigDelay")
    IniWrite(AutoStartCheckbox.Value ? "true" : "false", configPath, "Settings", "AutoStart")
    IniWrite(ConfigDebugCheckbox.Value ? "true" : "false", configPath, "Settings", "Debug")
    IniWrite(startupWaitText, configPath, "Settings", "StartupWaitTime")
    IniWrite(processWaitText, configPath, "Settings", "ProcessCloseWaitTime")
    IniWrite(menuDelayText, configPath, "Settings", "MenuNavigationDelay")

    IniWrite(messageIntervalText, configPath, "Messages", "Interval")
    IniWrite(messageDelayText, configPath, "Messages", "BetweenDelay")

    ; Clear existing message entries (legacy and new format)
    idx := 1
    Loop {
        existingKey := IniRead(configPath, "Messages", "Message" . idx . "Key", "__missing__")
        existingText := IniRead(configPath, "Messages", "Message" . idx . "Text", "__missing__")
        legacy := IniRead(configPath, "Messages", "Message" . idx, "__missing__")
        if (existingKey = "__missing__" && existingText = "__missing__" && legacy = "__missing__")
            break
        IniDelete(configPath, "Messages", "Message" . idx . "Key")
        IniDelete(configPath, "Messages", "Message" . idx . "Text")
        IniDelete(configPath, "Messages", "Message" . idx)
        idx++
    }

    ; Write new bindings
    idx := 1
    for binding in normalizedBindings {
        IniWrite(binding["Key"], configPath, "Messages", "Message" . idx . "Key")
        IniWrite(binding["Text"], configPath, "Messages", "Message" . idx . "Text")
        idx++
    }

    ; Update in-memory values
    GamePath := newGamePath
    WindowTitle := newWindowTitle
    ExeName := newExeName
    RestartTimes := newRestartTimes
    StartupWaitTime := startupWaitValue
    ProcessCloseWaitTime := processWaitValue
    MenuNavigationDelay := menuDelayValue
    ExecConfigDelay := execDelayValue
    ExecConfigs := newExecConfigs
    CrashMessages := newCrashMessages
    MessageInterval := messageIntervalMs
    MessageDelay := messageDelayValue
    ReminderBindings := normalizedBindings
    AutoStartEnabled := AutoStartCheckbox.Value
    DebugMode := ConfigDebugCheckbox.Value

    if (AutoHostRunning) {
        SetTimer(SendReminderMessage, 0)
        if (MessageInterval > 0)
            SetTimer(SendReminderMessage, MessageInterval)
    }

    PopulateConfigTab()
    PopulateMessagesTab()
    if (GamePathEdit)
        GamePathEdit.Value := newGamePath

    Log("Configuration saved from Config tab")
    UpdateGUIStatus()
    ClearUnsavedChanges()
    MsgBox("Configuration saved successfully.", "Q2RE AutoHost", 64)
}
ManualStartGame() {
    global LastActionText
    Log("Manual start requested from GUI")
    if (LastActionText)
        LastActionText.Value := "Manual start requested at " . FormatTime(, "HH:mm:ss")
    CheckAndStartGame(true)  ; Pass true to indicate manual launch
}

StopGame() {
    global ExeName, LastActionText
    if ProcessExist(ExeName) {
        ProcessClose(ExeName)
        Log("Manual game stop requested")
        if (LastActionText)
            LastActionText.Value := "Game stopped at " . FormatTime(, "HH:mm:ss")
        MsgBox("Game stopped successfully.", "Q2RE AutoHost", 64)
    } else {
        MsgBox("Game is not running.", "Q2RE AutoHost", 48)
    }
}

ForceQuitGame() {
    global ExeName, LastActionText
    if ProcessExist(ExeName) {
        result := MsgBox("Force quit will immediately terminate the game process without saving.`n`nContinue?", "Force Quit", 4 + 48)
        if (result = "Yes") {
            ProcessClose(ExeName)
            Log("Force quit executed")
            if (LastActionText)
                LastActionText.Value := "Force quit at " . FormatTime(, "HH:mm:ss")
        }
    } else {
        MsgBox("Game is not running.", "Q2RE AutoHost", 48)
    }
}

RestartGame() {
    global LastActionText
    Log("Manual restart requested")
    if (LastActionText)
        LastActionText.Value := "Manual restart at " . FormatTime(, "HH:mm:ss")
    StopGame()
    Sleep(3000)
    CheckAndStartGame(true)  ; Pass true to indicate manual launch
}

SendTestMessage() {
    global WindowTitle, ExeName
    
    if (!ProcessExist(ExeName)) {
        MsgBox("Game is not running. Start the game first.", "Q2RE AutoHost", 48)
        return
    }
    
    hwnd := GetGameWindowHandle()
    if !hwnd {
        MsgBox("Could not find game window.", "Q2RE AutoHost", 48)
        return
    }
    
    WinActivate("ahk_id " . hwnd)
    if !WinWaitActive("ahk_id " . hwnd,, 5) {
        MsgBox("Could not focus the game window.", "Q2RE AutoHost", 48)
        return
    }
    
    Sleep(500)
    Send("say Test message from AutoHost Manager")
    Sleep(300)
    Send("{Enter}")
    Log("Test message sent")
    MsgBox("Test message sent to game.", "Q2RE AutoHost", 64)
}

ReloadConfig() {
    result := MsgBox("Reload configuration from config.ini?`n`nNote: This will restart the timers.", "Reload Config", 4 + 32)
    if (result = "Yes") {
        ReadConfig()
        Log("Configuration reloaded")
        ClearUnsavedChanges()
        MsgBox("Configuration reloaded successfully.", "Q2RE AutoHost", 64)
    }
}

OpenConfigFile() {
    configPath := A_ScriptDir "\config.ini"
    if FileExist(configPath) {
        Run(configPath)
        Log("Opened config.ini")
    } else {
        MsgBox("config.ini not found!", "Error", 16)
    }
}

OpenLogFile() {
    logPath := A_ScriptDir "\debug_log.txt"
    if FileExist(logPath) {
        Run(logPath)
        Log("Opened debug_log.txt")
    } else {
        MsgBox("debug_log.txt not found!", "Error", 16)
    }
}

ToggleMonitoring() {
    global MonitoringEnabled, MonitorCheckbox
    MonitoringEnabled := MonitorCheckbox.Value
    Log("Monitoring " . (MonitoringEnabled ? "enabled" : "disabled"))
    UpdateGUIStatus()
}

global CrashDetectionEnabled := true
ToggleCrashDetection() {
    global CrashDetectionEnabled, CrashCheckbox
    CrashDetectionEnabled := CrashCheckbox.Value
    Log("Crash detection " . (CrashDetectionEnabled ? "enabled" : "disabled"))
}

ToggleAutoStart() {
    global AutoStartEnabled, AutoStartCheckbox
    AutoStartEnabled := AutoStartCheckbox.Value
    IniWrite(AutoStartEnabled ? "true" : "false", A_ScriptDir "\config.ini", "Settings", "AutoStart")
    Log("AutoStart on launch " . (AutoStartEnabled ? "enabled" : "disabled"))
}

ClearLogsGUI() {
    global LogControl
    result := MsgBox("Clear the log viewer?`n`nNote: This only clears the display, not the log file.", "Clear Logs", 4 + 32)
    if (result = "Yes") {
        LogControl.Value := ""
        Log("Log viewer cleared")
    }
}

RefreshLogs() {
    global LogControl
    logPath := A_ScriptDir "\debug_log.txt"
    
    if FileExist(logPath) {
        try {
            content := FileRead(logPath)
            ; Show last 50KB of logs
            if (StrLen(content) > 50000)
                content := SubStr(content, -50000)
            LogControl.Value := content
            ; Auto-scroll to bottom
            SendMessage(0x115, 7, 0, LogControl.Hwnd)
        } catch as e {
            LogControl.Value := "Error reading log file: " . e.Message
        }
    } else {
        LogControl.Value := "Log file not found. Logs will appear here once generated."
    }
}

F2::StartAutoHost()
F3::ExitApp()

; --- Init ---
ReadConfig()

; Explicitly disable all timers first
SetTimer(MonitorGame, 0)
SetTimer(CheckScheduledQuit, 0)
SetTimer(CheckCrashWindow, 0)
SetTimer(SendReminderMessage, 0)

CreateGUI()

; Start GUI update timer (always running)
SetTimer(UpdateGUIStatus, 1000)

if (AutoStartEnabled) {
    Log("Script initialized. AutoStart is enabled; starting AutoHost automatically.")
    SetTimer(StartAutoHost, -100)
} else {
    ; Don't start other timers or game - wait for user to click Start AutoHost
    Log("Script initialized. AutoHost is STOPPED. Press 'Start AutoHost' to begin automatic hosting.")
}