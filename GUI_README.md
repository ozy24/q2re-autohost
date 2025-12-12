# Q2RE Auto-Host Manager GUI

A comprehensive graphical user interface for managing the Quake II Remastered Auto-Host script. This GUI provides an intuitive way to configure, monitor, and control your Quake II listen server without having to manually edit configuration files or use hotkeys.

## 🚀 Quick Start

1. **Install AutoHotkey v2** from [https://www.autohotkey.com/](https://www.autohotkey.com/)
2. **Double-click** `Launch_GUI.bat` or run `Q2REAutoHostGUI.ahk` directly
3. **Load your configuration** by clicking "Load Config" in the Configuration tab
4. **Start your server** from the Server Control tab

## 📋 Features

### 🎮 Server Control Tab
- **Real-time Status Monitoring**: See if your server is running, crashed, or stopped
- **One-click Controls**: Start, stop, and restart your server with simple buttons
- **Process Monitoring**: View current game process and uptime information
- **Quick Actions**: Test messages, open log files, and access configuration
- **Activity Log**: Track all server actions with timestamps

### ⚙️ Configuration Tab
- **Visual Config Editor**: No more manual INI file editing
- **File Browser Integration**: Browse for game executable and config files
- **Input Validation**: Ensures your settings are properly formatted
- **Save/Load Functions**: Easily backup and restore configurations
- **Real-time Preview**: See exactly what settings will be applied

### 💬 Messages Tab
- **Message Management**: Add, edit, and delete server messages visually
- **Timing Controls**: Set message intervals and delays with sliders
- **Message Testing**: Preview how messages will appear in-game
- **Drag & Drop Reordering**: Organize messages in the order you want
- **Bulk Operations**: Test all messages at once

### 📊 Logs Tab
- **Real-time Log Viewer**: See debug output as it happens
- **Auto-refresh**: Logs update automatically every 5 seconds
- **Log Management**: Clear logs or open them in external editor
- **Filtered Display**: Shows only the most recent 100 lines for performance
- **Search Functionality**: Find specific events in your logs

## 🛠️ Usage Instructions

### Initial Setup
1. **First Launch**: The GUI will attempt to load `config.ini` automatically
2. **If no config exists**: You'll be prompted to create one from `config.ini.example`
3. **Configure Game Path**: Browse to your Quake II executable location
4. **Set Server Options**: Configure restart times, map rotation, and crash detection

### Managing Server Messages
1. **Go to Messages Tab**: Click the "Messages" tab at the top
2. **Add Messages**: Click "Add Message" and enter your text
3. **Edit Messages**: Double-click any message or select and click "Edit"
4. **Test Messages**: Use "Test All Messages" to preview the sequence
5. **Set Timing**: Adjust interval (minutes) and delay (milliseconds)

### Server Operations
1. **Start Server**: Click "Start Server" - the GUI will launch the AutoHost script
2. **Monitor Status**: Watch the status indicators for real-time updates
3. **View Logs**: Check the Logs tab for detailed operation information
4. **Stop/Restart**: Use the control buttons as needed

### Configuration Management
1. **Edit Settings**: Use the Configuration tab to modify all server settings
2. **Browse Files**: Use "Browse" buttons to select game and config files
3. **Save Changes**: Click "Save Config" to write changes to `config.ini`
4. **Backup Configs**: Save different configurations for different server types

## 🎯 Advanced Features

### Server Monitoring
- **Process Detection**: Automatically detects if the game is running
- **Crash Recovery**: Shows when the server has crashed and needs restart
- **Uptime Tracking**: Monitors how long the server has been running
- **Activity Logging**: Records all server events with timestamps

### Configuration Validation
- **Path Checking**: Verifies that game paths exist and are accessible
- **Format Validation**: Ensures restart times are in correct HH:MM format
- **Config File Detection**: Validates that specified config files exist
- **Error Reporting**: Clear error messages for configuration issues

### Message System
- **Rich Text Support**: Messages support all Quake II console commands
- **Timing Control**: Precise control over message intervals and delays
- **Preview Mode**: Test messages without starting the server
- **Bulk Management**: Add multiple messages quickly

## 🔧 Troubleshooting

### Common Issues

**"Config file not found" Error**
- Copy `config.ini.example` to `config.ini`
- Use the Configuration tab to set up your settings
- Click "Save Config" to create the file

**"Server won't start" Error**
- Check that the game path is correct
- Verify AutoHotkey v2 is installed
- Ensure `Q2REAutoHost.ahk` is in the same folder

**"GUI won't launch" Error**
- Install AutoHotkey v2 (not v1.1)
- Run as Administrator if needed
- Check that all script files are present

**Messages not working**
- Ensure the Quake II console is open (~ key)
- Check message timing settings
- Verify server is actually running

### Log Analysis
The Logs tab provides detailed information about server operations:
- **[HH:mm:ss] Starting game...**: Server startup initiated
- **[HH:mm:ss] Game window found**: Game launched successfully  
- **[HH:mm:ss] >>> Sent reminder**: Message sent to players
- **[HH:mm:ss] >>> Crash window detected**: Crash dialog handled

## 📁 File Structure

```
Q2RE-AutoHost/
├── Q2REAutoHost.ahk          # Main server script
├── Q2REAutoHostGUI.ahk       # GUI application
├── Launch_GUI.bat            # Easy launcher
├── config.ini.example        # Configuration template
├── config.ini               # Your configuration (created by GUI)
├── debug_log.txt            # Server logs (created automatically)
├── ServerConfigs/           # Server configuration files
│   ├── ffa.cfg
│   ├── ffa-q2eaks.cfg
│   ├── ffa-mm.cfg
│   └── customs.cfg
└── GUI_README.md            # This file
```

## 🎮 Server Configuration Examples

### Basic FFA Server
- **Game Path**: `C:\Program Files (x86)\Steam\steamapps\common\Quake 2\quake2.exe`
- **Window Title**: `Quake II- Version Date: Oct 31 2023 (Vulkan)`
- **Executable**: `quake2ex_steam.exe`
- **Config Files**: `ffa.cfg`
- **Restart Times**: `02:00,14:00`

### MuffMode Server with Custom Maps
- **Config Files**: `ffa-mm.cfg,customs.cfg`
- **Map Count**: `11` (cycles through all maps)
- **Messages**: Download reminders for custom content

### Q2Eaks Enhanced Server
- **Config Files**: `ffa-q2eaks.cfg`
- **Debug**: Enabled (for mod compatibility checking)
- **Crash Messages**: Include Q2Eaks-specific error strings

## 🆘 Support

If you encounter issues:
1. **Check the Logs tab** for detailed error information
2. **Verify your configuration** using the Configuration tab
3. **Test individual components** using the various test buttons
4. **Refer to the main README.md** for AutoHotkey script details

## 📄 License

This GUI application is released under the same MIT License as the main Q2RE AutoHost script.