/*
  Q2REAutohost.ahk - Quake II Remastered Listen Server Auto-Host
  Version: 1.0.0

  Automates launching, configuring, and managing a multiplayer listen server 
  in the Quake II Remastered Edition (Kex engine) for Steam or GOG.

  Features:
  - Auto-starts and configures the game menu to host a match
  - Gracefully quits and restarts the game at scheduled times
  - Detects and closes common crash dialogs
  - Sends reminder messages every 5 minutes for slow file downloads

  The Kex remaster does not support dedicated servers. This script makes 
  listen servers more reliable by auto-recovering from common crashes and instabilities.

  Please refer to README.MD for setup details.
*/

#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode("Input")

; --- Global Variables ---
global ScriptVersion := "1.0.0"
global LastRunTime := ""
global DebugMode := true
global RestartTimes := []
global CrashMessages := []
global GamePath := ""
global WindowTitle := ""
global ExeName := ""
global MapCount := 0
global ExecConfigs := []
global MessageList := []
global MessageInterval := 300000
global MessageDelay := 500


; --- Read config.ini ---
ReadConfig() {
    global RestartTimes, DebugMode, CrashMessages, GamePath, WindowTitle, ExeName, MapCount, ExecConfigs, MessageList, MessageInterval, MessageDelay
    iniPath := A_ScriptDir "\config.ini"

    times := IniRead(iniPath, "Settings", "RestartTimes", "06:00,17:00")
    RestartTimes := StrSplit(times, ",")

    dbg := IniRead(iniPath, "Settings", "Debug", "true")
    DebugMode := (StrLower(dbg) = "true")

    crashList := IniRead(iniPath, "Settings", "CrashMessages", "Exception caught in main,ERROR_DEVICE_LOST,Z_Free: bad magic")
    CrashMessages := StrSplit(crashList, ",")

    GamePath := IniRead(iniPath, "Settings", "GamePath", "")
    WindowTitle := IniRead(iniPath, "Settings", "WindowTitle", "Quake II")
    ExeName := IniRead(iniPath, "Settings", "ExeName", "quake2ex_steam.exe")

    MapCount := IniRead(iniPath, "Settings", "MapCount", "0")

    configList := IniRead(iniPath, "Settings", "ExecConfigs", "ffa.cfg")
    ExecConfigs := StrSplit(configList, ",")

    ; --- Load scheduled messages ---
    MessageInterval := Number(IniRead(iniPath, "Messages", "Interval", "5")) * 60000
    MessageDelay := Number(IniRead(iniPath, "Messages", "BetweenDelay", "500"))

    i := 1
    while true {
        key := "Message" . i
        msg := IniRead(iniPath, "Messages", key, "")
        if (msg = "")
            break
        MessageList.Push(Trim(msg))
        i++
    }

}

; --- Logging function ---
Log(msg) {
    global DebugMode, LogLock
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

        FileAppend("[" . FormatTime(, "HH:mm:ss") . "] " . msg . "`n", logPath)
    } catch as e {
        MsgBox("Log write failed: " . e.Message)
    }
    lock := false
}


; --- Launch and prepare Quake 2 ---
CheckAndStartGame() {
    global GamePath, WindowTitle, ExeName
    Log("Starting game...")

    if (PID := ProcessExist(ExeName))
        ProcessClose(ExeName)

    Sleep(10000)
    Run(GamePath)
    Sleep(15000)

    if WinExist(WindowTitle) {
        WinActivate()
        WinWaitActive(WindowTitle,, 10)
        Sleep(1000)
        Log("Game window found and activated")
    } else {
        Log("Game window not found")
        return
    }

    ; Automate menu steps
    SendInput("{Esc}")
    Sleep(3000)
    SendInput("{Down down}")
    Sleep(100)
    SendInput("{Down up}")
    Sleep(500)
    SendInput("{Enter down}")
    Sleep(100)
    SendInput("{Enter up}")
    Sleep(500)
    SendInput("{Enter down}")
    Sleep(100)
    SendInput("{Enter up}")
    Sleep(500)

    Loop 3 {
        SendInput("{Down down}")
        Sleep(100)
        SendInput("{Down up}")
        Sleep(500)
    }

    SendInput("{Enter down}")
    Sleep(100)
    SendInput("{Enter up}")
    Sleep(500)
    SendInput("{Enter down}")
    Sleep(100)
    SendInput("{Enter up}")
    Sleep(500)

    Loop 4 {
        SendInput("{Down down}")
        Sleep(100)
        SendInput("{Down up}")
        Sleep(500)
    }

    SendInput("{Enter down}")
    Sleep(100)
    SendInput("{Enter up}")
    Sleep(5000)

    ; Run config scripts
    WinActivate()
    WinWaitActive(WindowTitle,, 3)
    Send("{SC029}")
    Sleep(500)
    for cfg in ExecConfigs {
        Send("exec " . Trim(cfg))
        Sleep(500)
        Send("{enter}")
        Sleep(500)
    }

    Loop MapCount {
        Sleep(700)
        Send("nextmap")
        Sleep(500)
        Send("{enter}")
    }

    SetTimer(SendReminderMessage, 300000)
    Log("Started reminder timer")
}

MonitorGame() {
    global ExeName
    if !ProcessExist(ExeName) {
        Log("Game not running - restarting")
        CheckAndStartGame()
    }
}

CheckScheduledQuit() {
    global LastRunTime, RestartTimes
    nowTime := FormatTime(, "HH:mm")
    Log("Checking quit time: " . nowTime . " | LastRunTime: " . LastRunTime)

    for time in RestartTimes {
        if (nowTime = Trim(time)) and (LastRunTime != nowTime) {
            LastRunTime := nowTime
            Log("Match found for scheduled quit: " . time)

            winList := WinGetList()
            for hwnd in winList {
                title := WinGetTitle(hwnd)
                if InStr(title, "Quake II") {
                    WinActivate(hwnd)
                    WinWaitActive(hwnd,, 5)
                    Send("say Server will be restarted in 1 minute.")
                    Sleep(500)
                    Send("{Enter}")
                    Sleep(60000)
                    Send("quit")
                    Sleep(500)
                    Send("{Enter}")
                    Sleep(500)
                    Log(">>> Sent quit at " . nowTime . " to window: '" . title . "'")
                    return
                }
            }
            Log("No matching Quake II window found for quit")
        }
    }
}

SendReminderMessage() {
    global MessageList, MessageDelay
    title := WinGetTitle("A")
    if !InStr(title, "Quake II") {
        Log("Skipped reminder — Quake II not focused (active window: " . title . ")")
        return
    }

    for msg in MessageList {
        Send(msg)
        Sleep(500)
        Send("{enter}")
        Sleep(MessageDelay)
        Log(">>> Sent reminder: " . msg)
    }
}


CheckCrashWindow() {
    global ExeName, CrashMessages
    WinTitle := "ahk_class #32770 ahk_exe " . ExeName

    if WinExist(WinTitle) {
        hwnd := WinExist(WinTitle)
        text := ControlGetText("Static2", hwnd)
        for msg in CrashMessages {
            if InStr(text, msg, false) {
                WinClose(hwnd)
                Log(">>> Crash window detected and closed. Message: " . text)
                return
            }
        }
    }
}

F2::CheckAndStartGame()
F3::ExitApp()

; --- Init ---
ReadConfig()
CheckAndStartGame()
SetTimer(MonitorGame, 5000)
SetTimer(CheckScheduledQuit, 60000)
SetTimer(CheckCrashWindow, 1000)