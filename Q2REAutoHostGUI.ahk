/*
  Q2REAutoHostGUI.ahk - GUI for Quake II Remastered Listen Server Auto-Host
  Version: 1.0.0

  A comprehensive GUI interface for managing the Q2REAutoHost.ahk script.
  Provides easy configuration management, server control, status monitoring,
  and message management capabilities.

  Features:
  - Visual configuration editor for all settings
  - Real-time server status monitoring
  - Start/stop/restart server controls
  - Message management and testing
  - Log viewer with auto-refresh
  - Config file browser and validator
*/

#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode("Input")

; --- Global Variables ---
global ScriptVersion := "1.0.0"
global MainGui := ""
global ConfigData := Map()
global ServerProcess := ""
global LogViewerTimer := ""
global StatusTimer := ""
global IsServerRunning := false

; --- GUI Creation ---
CreateMainGUI() {
    global MainGui, ConfigData

    MainGui := Gui("+Resize +MinSize640x480", "Q2RE Auto-Host Manager v" . ScriptVersion)
    MainGui.BackColor := "White"
    MainGui.SetFont("s9", "Segoe UI")

    ; Create Tab Control
    Tab := MainGui.AddTab3("x10 y10 w620 h460", ["Server Control", "Configuration", "Messages", "Logs"])

    ; === TAB 1: Server Control ===
    Tab.UseTab(1)
    
    ; Status Group
    StatusGroup := MainGui.AddGroupBox("x20 y50 w590 h120", "Server Status")
    MainGui.AddText("x30 y75", "Status:")
    global StatusText := MainGui.AddText("x80 y75 w200 +Border", "Not Running")
    StatusText.SetFont("s9 Bold")
    
    MainGui.AddText("x30 y100", "Process:")
    global ProcessText := MainGui.AddText("x80 y100 w200", "N/A")
    
    MainGui.AddText("x30 y125", "Uptime:")
    global UptimeText := MainGui.AddText("x80 y125 w200", "N/A")
    
    MainGui.AddText("x30 y150", "Last Action:")
    global LastActionText := MainGui.AddText("x100 y150 w400", "None")

    ; Control Buttons
    ControlGroup := MainGui.AddGroupBox("x20 y180 w590 h100", "Server Controls")
    global StartBtn := MainGui.AddButton("x40 y210 w100 h30", "Start Server")
    StartBtn.OnEvent("Click", StartServer)
    
    global StopBtn := MainGui.AddButton("x160 y210 w100 h30", "Stop Server")
    StopBtn.OnEvent("Click", StopServer)
    StopBtn.Enabled := false
    
    global RestartBtn := MainGui.AddButton("x280 y210 w100 h30", "Restart Server")
    RestartBtn.OnEvent("Click", RestartServer)
    RestartBtn.Enabled := false
    
    global ConfigBtn := MainGui.AddButton("x400 y210 w100 h30", "Reload Config")
    ConfigBtn.OnEvent("Click", ReloadConfig)

    ; Quick Actions
    QuickGroup := MainGui.AddGroupBox("x20 y290 w590 h100", "Quick Actions")
    global TestMsgBtn := MainGui.AddButton("x40 y320 w120 h30", "Test Messages")
    TestMsgBtn.OnEvent("Click", TestMessages)
    
    global OpenLogBtn := MainGui.AddButton("x180 y320 w120 h30", "Open Log File")
    OpenLogBtn.OnEvent("Click", OpenLogFile)
    
    global OpenConfigBtn := MainGui.AddButton("x320 y320 w120 h30", "Open Config")
    OpenConfigBtn.OnEvent("Click", OpenConfigFile)

    ; === TAB 2: Configuration ===
    Tab.UseTab(2)
    
    ; Game Settings
    GameGroup := MainGui.AddGroupBox("x20 y50 w590 h140", "Game Settings")
    MainGui.AddText("x30 y75", "Game Path:")
    global GamePathEdit := MainGui.AddEdit("x30 y95 w450 r1")
    global BrowseGameBtn := MainGui.AddButton("x490 y95 w80 h23", "Browse...")
    BrowseGameBtn.OnEvent("Click", BrowseGamePath)
    
    MainGui.AddText("x30 y125", "Window Title:")
    global WindowTitleEdit := MainGui.AddEdit("x30 y145 w250 r1")
    
    MainGui.AddText("x300 y125", "Executable Name:")
    global ExeNameEdit := MainGui.AddEdit("x300 y145 w250 r1")

    ; Server Settings
    ServerGroup := MainGui.AddGroupBox("x20 y200 w590 h140", "Server Settings")
    MainGui.AddText("x30 y225", "Restart Times (HH:MM,HH:MM):")
    global RestartTimesEdit := MainGui.AddEdit("x30 y245 w250 r1")
    
    MainGui.AddText("x300 y225", "Map Count:")
    global MapCountEdit := MainGui.AddEdit("x300 y245 w100 r1")
    
    MainGui.AddText("x30 y275", "Config Files (comma-separated):")
    global ExecConfigsEdit := MainGui.AddEdit("x30 y295 w450 r1")
    global BrowseConfigBtn := MainGui.AddButton("x490 y295 w80 h23", "Browse...")
    BrowseConfigBtn.OnEvent("Click", BrowseConfigFiles)

    ; Debug Settings
    DebugGroup := MainGui.AddGroupBox("x20 y350 w590 h80", "Debug Settings")
    global DebugCheck := MainGui.AddCheckbox("x30 y375", "Enable Debug Logging")
    
    MainGui.AddText("x200 y375", "Crash Messages (comma-separated):")
    global CrashMsgEdit := MainGui.AddEdit("x30 y395 w540 r1")

    ; Save/Load Buttons
    global SaveConfigBtn := MainGui.AddButton("x430 y440 w80 h25", "Save Config")
    SaveConfigBtn.OnEvent("Click", SaveConfiguration)
    
    global LoadConfigBtn := MainGui.AddButton("x520 y440 w80 h25", "Load Config")
    LoadConfigBtn.OnEvent("Click", LoadConfiguration)

    ; === TAB 3: Messages ===
    Tab.UseTab(3)
    
    ; Message Settings
    MsgGroup := MainGui.AddGroupBox("x20 y50 w590 h100", "Message Settings")
    MainGui.AddText("x30 y75", "Interval (minutes):")
    global IntervalEdit := MainGui.AddEdit("x140 y75 w80 r1")
    
    MainGui.AddText("x250 y75", "Between Delay (ms):")
    global DelayEdit := MainGui.AddEdit("x370 y75 w80 r1")

    ; Message List
    MainGui.AddText("x20 y160", "Server Messages:")
    global MessageList := MainGui.AddListView("x20 y180 w590 h200 +Grid", ["#", "Message"])
    MessageList.OnEvent("DoubleClick", EditMessage)
    
    ; Message Controls
    global AddMsgBtn := MainGui.AddButton("x20 y390 w80 h25", "Add Message")
    AddMsgBtn.OnEvent("Click", AddMessage)
    
    global EditMsgBtn := MainGui.AddButton("x110 y390 w80 h25", "Edit Message")
    EditMsgBtn.OnEvent("Click", EditMessage)
    
    global DeleteMsgBtn := MainGui.AddButton("x200 y390 w80 h25", "Delete Message")
    DeleteMsgBtn.OnEvent("Click", DeleteMessage)
    
    global TestAllMsgBtn := MainGui.AddButton("x300 y390 w100 h25", "Test All Messages")
    TestAllMsgBtn.OnEvent("Click", TestAllMessages)

    ; === TAB 4: Logs ===
    Tab.UseTab(4)
    
    MainGui.AddText("x20 y50", "Debug Log (Auto-refreshing):")
    global LogEdit := MainGui.AddEdit("x20 y70 w590 h320 +VScroll +ReadOnly +HScroll")
    LogEdit.SetFont("s8", "Consolas")
    
    global RefreshLogBtn := MainGui.AddButton("x20 y400 w100 h25", "Refresh Log")
    RefreshLogBtn.OnEvent("Click", RefreshLog)
    
    global ClearLogBtn := MainGui.AddButton("x130 y400 w100 h25", "Clear Log")
    ClearLogBtn.OnEvent("Click", ClearLog)
    
    global AutoRefreshCheck := MainGui.AddCheckbox("x250 y402", "Auto-refresh (5s)")
    AutoRefreshCheck.Value := 1
    AutoRefreshCheck.OnEvent("Click", ToggleAutoRefresh)

    ; Set up GUI events
    MainGui.OnEvent("Close", GuiClose)
    MainGui.OnEvent("Size", GuiResize)

    return MainGui
}

; --- Configuration Management ---
LoadConfiguration() {
    global ConfigData, GamePathEdit, WindowTitleEdit, ExeNameEdit, RestartTimesEdit
    global MapCountEdit, ExecConfigsEdit, DebugCheck, CrashMsgEdit, IntervalEdit, DelayEdit
    global MessageList
    
    iniPath := A_ScriptDir "\config.ini"
    
    if !FileExist(iniPath) {
        MsgBox("Config file not found! Please create config.ini from config.ini.example")
        return
    }
    
    ; Load settings
    GamePathEdit.Text := IniRead(iniPath, "Settings", "GamePath", "")
    WindowTitleEdit.Text := IniRead(iniPath, "Settings", "WindowTitle", "Quake II")
    ExeNameEdit.Text := IniRead(iniPath, "Settings", "ExeName", "quake2ex_steam.exe")
    RestartTimesEdit.Text := IniRead(iniPath, "Settings", "RestartTimes", "06:00,17:00")
    MapCountEdit.Text := IniRead(iniPath, "Settings", "MapCount", "0")
    ExecConfigsEdit.Text := IniRead(iniPath, "Settings", "ExecConfigs", "ffa.cfg")
    CrashMsgEdit.Text := IniRead(iniPath, "Settings", "CrashMessages", "Exception caught in main,ERROR_DEVICE_LOST,Z_Free: bad magic")
    
    debugVal := IniRead(iniPath, "Settings", "Debug", "true")
    DebugCheck.Value := (StrLower(debugVal) = "true") ? 1 : 0
    
    ; Load message settings
    IntervalEdit.Text := IniRead(iniPath, "Messages", "Interval", "5")
    DelayEdit.Text := IniRead(iniPath, "Messages", "BetweenDelay", "500")
    
    ; Load messages
    MessageList.Delete()
    i := 1
    while true {
        key := "Message" . i
        msg := IniRead(iniPath, "Messages", key, "")
        if (msg = "")
            break
        MessageList.Add("", i, msg)
        i++
    }
    
    UpdateLastAction("Configuration loaded successfully")
}

SaveConfiguration() {
    global GamePathEdit, WindowTitleEdit, ExeNameEdit, RestartTimesEdit
    global MapCountEdit, ExecConfigsEdit, DebugCheck, CrashMsgEdit, IntervalEdit, DelayEdit
    global MessageList
    
    iniPath := A_ScriptDir "\config.ini"
    
    ; Save settings
    IniWrite(GamePathEdit.Text, iniPath, "Settings", "GamePath")
    IniWrite(WindowTitleEdit.Text, iniPath, "Settings", "WindowTitle")
    IniWrite(ExeNameEdit.Text, iniPath, "Settings", "ExeName")
    IniWrite(RestartTimesEdit.Text, iniPath, "Settings", "RestartTimes")
    IniWrite(MapCountEdit.Text, iniPath, "Settings", "MapCount")
    IniWrite(ExecConfigsEdit.Text, iniPath, "Settings", "ExecConfigs")
    IniWrite(CrashMsgEdit.Text, iniPath, "Settings", "CrashMessages")
    IniWrite(DebugCheck.Value ? "true" : "false", iniPath, "Settings", "Debug")
    
    ; Save message settings
    IniWrite(IntervalEdit.Text, iniPath, "Messages", "Interval")
    IniWrite(DelayEdit.Text, iniPath, "Messages", "BetweenDelay")
    
    ; Clear existing messages
    i := 1
    while true {
        key := "Message" . i
        if IniRead(iniPath, "Messages", key, "") = ""
            break
        IniDelete(iniPath, "Messages", key)
        i++
    }
    
    ; Save messages
    Loop MessageList.GetCount() {
        key := "Message" . A_Index
        msg := MessageList.GetText(A_Index, 2)
        IniWrite(msg, iniPath, "Messages", key)
    }
    
    UpdateLastAction("Configuration saved successfully")
    MsgBox("Configuration saved to config.ini")
}

; --- Server Control Functions ---
StartServer() {
    global ServerProcess, IsServerRunning, StartBtn, StopBtn, RestartBtn
    global ExeNameEdit
    
    if IsServerRunning {
        MsgBox("Server is already running!")
        return
    }
    
    ; Check if config is loaded
    if !ExeNameEdit.Text {
        MsgBox("Please load configuration first!")
        return
    }
    
    ; Start the main script
    try {
        Run(A_ScriptDir "\Q2REAutoHost.ahk")
        IsServerRunning := true
        StartBtn.Enabled := false
        StopBtn.Enabled := true
        RestartBtn.Enabled := true
        UpdateStatus("Starting...", "Starting server process")
        UpdateLastAction("Server start initiated")
    } catch as e {
        MsgBox("Failed to start server: " . e.Message)
    }
}

StopServer() {
    global ServerProcess, IsServerRunning, StartBtn, StopBtn, RestartBtn
    global ExeNameEdit
    
    if !IsServerRunning {
        MsgBox("Server is not running!")
        return
    }
    
    ; Stop the AutoHost script
    try {
        WinClose("Q2REAutohost.ahk ahk_class AutoHotkey")
        ; Also stop the game process
        if ProcessExist(ExeNameEdit.Text)
            ProcessClose(ExeNameEdit.Text)
        
        IsServerRunning := false
        StartBtn.Enabled := true
        StopBtn.Enabled := false
        RestartBtn.Enabled := false
        UpdateStatus("Stopped", "Server stopped")
        UpdateLastAction("Server stopped")
    } catch as e {
        MsgBox("Failed to stop server: " . e.Message)
    }
}

RestartServer() {
    UpdateLastAction("Restarting server...")
    StopServer()
    Sleep(2000)
    StartServer()
}

ReloadConfig() {
    LoadConfiguration()
    UpdateLastAction("Configuration reloaded")
}

; --- Message Management ---
AddMessage() {
    global MessageList
    
    result := InputBox("Enter new message:", "Add Message", "w300 h100")
    if result.Result = "OK" && result.Text != "" {
        row := MessageList.Add("", MessageList.GetCount() + 1, result.Text)
        MessageList.Modify(row, "Select")
        UpdateLastAction("Message added: " . result.Text)
    }
}

EditMessage() {
    global MessageList
    
    selected := MessageList.GetNext()
    if !selected {
        MsgBox("Please select a message to edit.")
        return
    }
    
    currentMsg := MessageList.GetText(selected, 2)
    result := InputBox("Edit message:", "Edit Message", "w300 h100", currentMsg)
    
    if result.Result = "OK" && result.Text != "" {
        MessageList.Modify(selected, Col2, result.Text)
        UpdateLastAction("Message edited")
    }
}

DeleteMessage() {
    global MessageList
    
    selected := MessageList.GetNext()
    if !selected {
        MsgBox("Please select a message to delete.")
        return
    }
    
    if MsgBox("Delete selected message?", "Confirm Delete", "YesNo") = "Yes" {
        MessageList.Delete(selected)
        ; Renumber remaining messages
        Loop MessageList.GetCount() {
            MessageList.Modify(A_Index, Col1, A_Index)
        }
        UpdateLastAction("Message deleted")
    }
}

TestMessages() {
    global MessageList, DelayEdit
    
    if MessageList.GetCount() = 0 {
        MsgBox("No messages to test!")
        return
    }
    
    delay := DelayEdit.Text ? Integer(DelayEdit.Text) : 500
    
    ; Test by showing messages in a temporary window
    testGui := Gui(, "Message Test")
    testGui.AddText("x10 y10 w300", "Testing messages (as they would appear in-game):")
    testEdit := testGui.AddEdit("x10 y40 w300 h200 +ReadOnly +VScroll")
    testGui.AddButton("x10 y250 w100 h30", "Close").OnEvent("Click", (*) => testGui.Close())
    
    testContent := ""
    Loop MessageList.GetCount() {
        msg := MessageList.GetText(A_Index, 2)
        testContent .= "[" . A_Index . "] " . msg . "`n"
        Sleep(delay)
    }
    
    testEdit.Text := testContent
    testGui.Show("w320 h290")
    UpdateLastAction("Messages tested")
}

TestAllMessages() {
    TestMessages()
}

; --- File Browser Functions ---
BrowseGamePath() {
    global GamePathEdit
    
    result := FileSelect(1, , "Select Quake II Executable", "Executable (*.exe)")
    if result != ""
        GamePathEdit.Text := result
}

BrowseConfigFiles() {
    global ExecConfigsEdit
    
    result := FileSelect("M", A_ScriptDir "\ServerConfigs", "Select Config Files", "Config Files (*.cfg)")
    if result.Length > 0 {
        configList := ""
        for file in result
            configList .= (configList ? "," : "") . file
        ExecConfigsEdit.Text := configList
    }
}

; --- Utility Functions ---
UpdateStatus(status, process := "", uptime := "") {
    global StatusText, ProcessText, UptimeText
    
    StatusText.Text := status
    if status = "Running"
        StatusText.SetFont("c0x008000") ; Green
    else if status = "Stopped"
        StatusText.SetFont("c0x800000") ; Red
    else
        StatusText.SetFont("c0x808000") ; Yellow
    
    if process != ""
        ProcessText.Text := process
    if uptime != ""
        UptimeText.Text := uptime
}

UpdateLastAction(action) {
    global LastActionText
    LastActionText.Text := FormatTime(, "HH:mm:ss") . " - " . action
}

; --- Log Management ---
RefreshLog() {
    global LogEdit
    
    logPath := A_ScriptDir "\debug_log.txt"
    if FileExist(logPath) {
        try {
            content := FileRead(logPath)
            ; Show last 100 lines
            lines := StrSplit(content, "`n")
            if lines.Length > 100 {
                content := ""
                Loop 100 {
                    content .= lines[lines.Length - 100 + A_Index] . "`n"
                }
            }
            LogEdit.Text := content
        } catch {
            LogEdit.Text := "Error reading log file"
        }
    } else {
        LogEdit.Text := "Log file not found"
    }
}

ClearLog() {
    global LogEdit
    
    if MsgBox("Clear the debug log file?", "Confirm Clear", "YesNo") = "Yes" {
        logPath := A_ScriptDir "\debug_log.txt"
        try {
            FileDelete(logPath)
            LogEdit.Text := "Log cleared"
            UpdateLastAction("Log file cleared")
        } catch {
            MsgBox("Failed to clear log file")
        }
    }
}

ToggleAutoRefresh() {
    global AutoRefreshCheck, LogViewerTimer
    
    if AutoRefreshCheck.Value {
        LogViewerTimer := SetTimer(RefreshLog, 5000)
    } else {
        if LogViewerTimer
            SetTimer(LogViewerTimer, 0)
    }
}

OpenLogFile() {
    logPath := A_ScriptDir "\debug_log.txt"
    if FileExist(logPath)
        Run("notepad.exe " . logPath)
    else
        MsgBox("Log file not found")
}

OpenConfigFile() {
    configPath := A_ScriptDir "\config.ini"
    if FileExist(configPath)
        Run("notepad.exe " . configPath)
    else
        MsgBox("Config file not found")
}

; --- Status Monitoring ---
MonitorServerStatus() {
    global IsServerRunning, ExeNameEdit
    
    if !ExeNameEdit.Text
        return
    
    gameRunning := ProcessExist(ExeNameEdit.Text)
    scriptRunning := WinExist("Q2REAutohost.ahk ahk_class AutoHotkey")
    
    if IsServerRunning && (!gameRunning && !scriptRunning) {
        ; Server crashed or stopped unexpectedly
        IsServerRunning := false
        UpdateStatus("Crashed", "Process stopped unexpectedly")
        UpdateLastAction("Server process stopped unexpectedly")
        
        global StartBtn, StopBtn, RestartBtn
        StartBtn.Enabled := true
        StopBtn.Enabled := false
        RestartBtn.Enabled := false
    } else if IsServerRunning && (gameRunning || scriptRunning) {
        UpdateStatus("Running", ExeNameEdit.Text, "Active")
    }
}

; --- GUI Event Handlers ---
GuiClose(*) {
    if MsgBox("Exit Q2RE Auto-Host Manager?", "Confirm Exit", "YesNo") = "Yes"
        ExitApp()
}

GuiResize(thisGui, MinMax, Width, Height) {
    ; Handle window resizing if needed
}

; --- Initialization ---
; Create and show the GUI
MainGui := CreateMainGUI()
LoadConfiguration()
MainGui.Show("w650 h500")

; Start monitoring
SetTimer(MonitorServerStatus, 2000)
SetTimer(RefreshLog, 5000)

; Show welcome message
UpdateLastAction("Q2RE Auto-Host Manager started")