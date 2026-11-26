# VSCode Ops Toolkit

An IDE-native DevOps toolkit for monitoring and debugging Docker/Linux staging environments — directly from VS Code, no context switching.

## ✨ Features

- **Real-time log formatter** — Serilog (JSON), Nginx access/error, Docker stats, `ps aux` with color-coded levels and highlighted IDs (each unique ID gets its own color)
- **One-click SSH tasks** — Docker logs, service restart, shell access, Nginx config, Linux diagnostics via VS Code Task Explorer
- **Monitoring agent** — Single SSH connection per tick, monitors 20+ services: up/down, CPU/RAM, disk, Nginx 5xx, log errors — Windows toast + beep alerts
- **Auto-sync service list** — Pull live container list from server, filter blacklist, update task dropdown automatically

## 📋 Requirements

- VS Code
- SSH access to a Linux server
- Python 3 on the server
- Windows (alert.ps1 uses PowerShell + Windows toast notifications)
- VS Code extension: [Task Explorer](https://marketplace.visualstudio.com/items?itemName=spmeesseman.vscode-taskexplorer) by spmeesseman

---

## 🚀 Setup (First time)

### 1. Clone repo

```bash
git clone https://github.com/YOUR_USERNAME/vscode-ops-toolkit
cd vscode-ops-toolkit
```

### 2. Run setup script

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

The script will:

- Ask for your SSH host alias, server IP, user, and key filename
- Replace `YOUR_SERVER` placeholder in all config files automatically
- Add SSH config entry to `~/.ssh/config`
- Fix SSH key permissions (required on Windows)
- Test SSH connection

### 3. Install Task Explorer

`Ctrl+Shift+X` → search **Task Explorer** (spmeesseman) → Install

### 4. Reload VS Code

`Ctrl+Shift+P` → **Reload Window**

Sidebar will show Task Explorer panel with task tree.

### 5. Upload scripts to server

Task Explorer → **🔄 Setup: Upload all scripts to server**

Uploads `dlog.py`, `dinspect.py`, `logsearch.py` to `/tmp/` on the server.

Output should show:

```
dlog.py        100%  ...
dinspect.py    100%  ...
logsearch.py   100%  ...
```

### 6. Sync service list

Task Explorer → **🔄 Setup: Sync service list**

Pulls live container list from server, filters blacklist, updates dropdown in `tasks.json`.

Then `Ctrl+Shift+P` → **Reload Window** again.

### ✅ Verify setup

Run task **🐧 Linux: Who is logged in** — if it shows your SSH username, everything is working.

---

## 🗂️ Task Tree

```
🐳 Docker
   ├── Logs
   │    ├── View service          — Realtime colored log, pick from dropdown
   │    ├── View any (type name)  — Any container by name or ID
   │    ├── Last 2 hours
   │    ├── Errors only
   │    └── Search keyword
   ├── Service
   │    ├── Restart
   │    └── Shell into container
   ├── Server
   │    ├── CPU/RAM snapshot
   │    ├── CPU/RAM realtime
   │    └── Disk usage
   └── Debug
        ├── Check all container status
        ├── Inspect container
        └── Kill stuck container

🌐 Nginx
   ├── List all sites
   ├── View site config
   ├── Test config
   ├── Backup config
   ├── Reload
   ├── Error log realtime
   ├── Access log realtime
   └── Access log 4xx 5xx only

🌐 Network
   ├── Ping between services
   └── Check port open

🐧 Linux
   ├── System overview
   ├── Top processes (CPU)
   ├── Top processes (RAM)
   ├── Check open ports
   ├── Suspicious processes
   ├── System log
   ├── Auth log
   ├── Who is logged in
   └── Network connections

🚨 Alert
   └── Start monitoring

🔄 Setup
   ├── Sync service list
   └── Upload all scripts to server
```

---

## ➕ How to extend

### Add a new task

Open `.vscode/tasks.json`, add to the `tasks` array:

```json
{
  "label": "🐳 Docker: Logs: Last 24 hours",
  "type": "shell",
  "command": "ssh",
  "args": [
    "YOUR_SERVER",
    "docker logs ${input:service} --since 24h | python3 -u /tmp/dlog.py"
  ],
  "presentation": { "reveal": "always", "panel": "dedicated", "clear": true },
  "problemMatcher": []
}
```

Label format: `<emoji> <Group>: <Subgroup>: <Name>`

Task Explorer auto-creates folders from the `:` separator. No other config needed.

### Add a new task group

Just use a new prefix in the label:

```json
{ "label": "☁️ AWS: List S3 buckets", ... }
{ "label": "☁️ AWS: Check ECS services", ... }
```

This auto-creates an `AWS` folder in Task Explorer.

### Add a service to blacklist

Edit `services.json`:

```json
{
  "blacklist": ["kibana", "your-infra-service"]
}
```

Then run **🔄 Setup: Sync service list**.

### Customize alert thresholds

```powershell
powershell -File docker/alert.ps1 -cpuThreshold 70 -memThreshold 75 -diskThreshold 80 -interval 60
```

Default: CPU > 80%, RAM > 80%, Disk > 85%, every 30s.

---

## 🔄 Updating scripts on server

After editing `dlog.py`, `dinspect.py`, or `logsearch.py`:

Task Explorer → **🔄 Setup: Upload all scripts to server**

Or manually:

```bash
scp docker/dlog.py docker/dinspect.py docker/logsearch.py YOUR_SERVER:/tmp/
```

After pulling new version from git, run upload again to keep server in sync.

---

## 🔧 Troubleshooting

| Problem                                     | Fix                                                                                                                               |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `Permission denied` on SSH                  | Run `setup.ps1` again, or manually run `icacls` on your key file                                                                  |
| Task Explorer shows flat list               | Check `.vscode/settings.json` has `groupWithSeparator: true` and `groupSeparator: ":"`, click refresh (🔄) in Task Explorer panel |
| Log has no color                            | Run **Setup: Upload all scripts to server**                                                                                       |
| `Could not resolve hostname`                | SSH alias in `~/.ssh/config` doesn't match what's in `tasks.json`. Run `setup.ps1` again                                          |
| Alert not detecting log errors              | Service must use Serilog JSON format with `"@l":"Error"` field                                                                    |
| Sync service list includes infra containers | Add them to `blacklist` in `services.json`                                                                                        |

---

## 📁 Structure

```
vscode-ops-toolkit/
├── docker/
│   ├── dlog.py           # Log formatter: Serilog, Nginx, Docker stats, ps aux
│   ├── dinspect.py       # docker inspect formatter
│   ├── logsearch.py      # Keyword search in container logs
│   └── alert.ps1         # Monitoring agent (Windows PowerShell)
├── .vscode/
│   ├── tasks.json        # All task definitions
│   └── settings.json     # Task Explorer grouping config
├── setup.ps1             # First-time setup script
├── sync-services.ps1     # Auto-sync service list from server
├── services.json         # Blacklist config
└── README.md
```

---

## 📝 License

MIT
