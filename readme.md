# Quake II Auto-Host

Quake II Remastered (Kex) unfortunately does not support dedicated servers. Hosting a listen server is possible, but in practice, it tends to be unstable and buggy.

This AutoHotkey v2 script automatically monitors and restarts a running Quake II listen server, sends optional in-game messages, and executes configuration files as needed. It is designed for **unattended servers** running 24/7 — as such, **the system must remain unlocked and have a visible desktop**. The in-game Quake II console must also be open for the auto-quit and message features to function.

---

## 🛠 Features

- Automatically launches and navigates the Quake II menu to host a multiplayer match
- Sends periodic in-game messages to players (e.g., download reminders)
- Quits and restarts the game at scheduled times
- Detects and closes known crash dialogs (e.g., `Z_Free: bad magic`, `ERROR_DEVICE_LOST`)
- Executes server config files automatically on launch
- Fully configurable via `config.ini`
- Includes log rotation with a max file size limit
- Automatically cycles through all available maps in the map list to initiate shuffling (for MuffMode servers only)

---

## 🚀 Setup

1. Install [AutoHotkey v2](https://www.autohotkey.com/)
2. Clone this repository or download the latest release `.zip`
3. Copy `config.ini.example` to `config.ini` and edit it to match your system paths and config preferences
4. Run the script: `Q2REAutoHost.ahk`

After a short delay, the game will launch, start a multiplayer server, and execute the specified configurations.

## ⚙️ Configuration Options (`config.ini`)

### [Settings]
| Key           | Description                                               |
|---------------|-----------------------------------------------------------|
| `GamePath`      | Full path to `quake2.exe`                                 |
| `WindowTitle`   | Title of the game window (e.g., "Quake II...")            |
| `ExeName`       | Process name of the game (e.g., `quake2ex_steam.exe`)     |
| `RestartTimes`  | Comma-separated list of `HH:mm` times to auto-restart     |
| `CrashMessages` | Comma-separated list of known crash message strings       |
| `ExecConfigs`   | Comma-separated config files to execute (e.g., `ffa.cfg`) |
| `ExecConfigDelay` | Delay (ms) between sending each `exec` command in-game   |
| `AutoStart`     | `true` / `false` — launch AutoHost automatically on start |
| `Debug`         | `true` / `false` — enable or disable log output           |

### [Messages]
| Key             | Description                                                       |
|-----------------|-------------------------------------------------------------------|
| `Message1..N`    | In-game messages to send (`say` is implied by the script logic)   |
| `Interval`       | Time in **minutes** between full message cycles                   |
| `BetweenDelay`   | Time in **milliseconds** between individual messages              |

---

## 🔐 Notes

- This script is designed for listen servers only — it does not support dedicated server setups.
- The system must remain **unlocked** with a visible desktop for input to be sent to the game window.
- The in-game **Quake II console must be open** for scheduled quits and chat messages to function correctly.
- Tested with the Steam release of Quake II Remastered (October 2023 build).

---

## 📄 License

[MIT License](LICENSE) — free to use, modify, and redistribute.
