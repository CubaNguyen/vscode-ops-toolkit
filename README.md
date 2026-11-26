# VSCode Ops Toolkit

An IDE-native DevOps toolkit for monitoring and debugging Docker/Linux staging environments — directly from VS Code, no context switching.

## ✨ Features

- **Real-time log formatter** — Serilog (JSON), Nginx access/error, Docker stats, `ps aux` with color-coded levels and highlighted IDs
- **One-click SSH tasks** — Docker logs, service restart, shell access, Nginx config, Linux diagnostics via VS Code Task Explorer
- **Monitoring agent** — Single SSH connection per tick, monitors 20+ services: up/down, CPU/RAM, disk, Nginx 5xx, log errors — Windows toast + beep alerts
- **Auto-sync service list** — Pull live container list from server, filter blacklist, update task dropdown automatically

## 📋 Requirements

- VS Code
- SSH access to your Linux server
- Python 3 on the server (`/usr/bin/python3`)
- Extension: [Task Explorer](https://marketplace.visualstudio.com/items?itemName=spmeesseman.vscode-taskexplorer) (spmeesseman)
- Windows (for `alert.ps1` toast notifications)

---

## 🚀 Setup

### 1. Clone repo

```bash
git clone https://github.com/YOUR_USERNAME/vscode-ops-toolkit
cd vscode-ops-toolkit
```

### 2. Configure your server

Edit the following files and replace `YOUR_SERVER` with your SSH host alias:

**`.vscode/tasks.json`** — search and replace `YOUR_SERVER`

**`docker/alert.ps1`** — line 2:
```powershell
[string]$server = "YOUR_SERVER",
```

**`sync-services.ps1`** — line 4:
```powershell
$SSH_HOST = "YOUR_SERVER"
```

### 3. Configure SSH

Add to `~/.ssh/config`:
```
Host YOUR_SERVER
    HostName YOUR_SERVER_IP
    IdentityFile ~/.ssh/your-key.pem
    User ubuntu
```

Fix key permission on Windows (required):
```powershell
icacls "$env:USERPROFILE\.ssh\your-key.pem" /inheritance:r /grant:r "$env:USERNAME:R"
```

Test:
```bash
ssh YOUR_SERVER
```

### 4. Install Task Explorer

`Ctrl+Shift+X` → search **Task Explorer** (spmeesseman) → Install

### 5. Upload scripts to server

Open Task Explorer sidebar → **🔄 Setup: Upload all scripts to server**

This uploads `dlog.py`, `dinspect.py`, `logsearch.py` to `/tmp/` on the server.

### 6. Sync service list

Run **🔄 Setup: Sync service list** → pulls live container list from server → updates dropdown in `tasks.json`

Then `Ctrl+Shift+P` → **Reload Window**

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

## ➕ Adding a new task

Open `.vscode/tasks.json`, add to the `tasks` array:

```json
{
  "label": "🐳 Docker: Logs: Last 24 hours",
  "type": "shell",
  "command": "ssh",
  "args": ["YOUR_SERVER", "docker logs ${input:service} --since 24h | python3 -u /tmp/dlog.py"],
  "presentation": { "reveal": "always", "panel": "dedicated", "clear": true },
  "problemMatcher": []
}
```

Label format: `<emoji> <Group>: <Subgroup>: <Name>` — Task Explorer auto-creates folders from the `:` separator.

---

## ➕ Adding a new service to blacklist

Edit `services.json`:

```json
{
  "blacklist": [
    "kibana",
    "your-new-service-to-exclude"
  ]
}
```

Then run **🔄 Setup: Sync service list** to update the dropdown.

---

## 🔧 Customizing alert thresholds

Run **🚨 Alert: Start monitoring** with custom params:

```powershell
# In terminal
powershell -File docker/alert.ps1 -cpuThreshold 70 -memThreshold 75 -diskThreshold 80 -interval 60
```

Default thresholds: CPU > 80%, RAM > 80%, Disk > 85%, check every 30s.

---

## 🔧 Troubleshooting

| Problem | Fix |
|---|---|
| `Permission denied` SSH | Run `icacls` command in step 3 |
| Task Explorer shows flat list | Check `.vscode/settings.json` has `groupWithSeparator: true` and `groupSeparator: ":"`, then click refresh |
| Log has no color | Run **Setup: Upload all scripts** |
| `Could not resolve hostname` | Check `~/.ssh/config` host alias matches `YOUR_SERVER` in tasks |
| Alert not detecting errors | Logs must be Serilog JSON format with `"@l":"Error"` field |

---

## 📁 Structure

```
vscode-ops-toolkit/
├── docker/
│   ├── dlog.py         # Log formatter: Serilog, Nginx, Docker stats, ps aux
│   ├── dinspect.py     # docker inspect formatter
│   ├── logsearch.py    # Keyword search in container logs
│   └── alert.ps1       # Monitoring agent (Windows, PowerShell)
├── .vscode/
│   ├── tasks.json      # All task definitions
│   └── settings.json   # Task Explorer grouping config
├── sync-services.ps1   # Auto-sync service list from server
├── services.json       # Blacklist config
└── README.md
```

---

## 🔄 Updating

When scripts are updated, re-upload to server:

**Task Explorer → 🔄 Setup: Upload all scripts to server**

Or manually:
```bash
scp docker/dlog.py docker/dinspect.py docker/logsearch.py YOUR_SERVER:/tmp/
```

---

## 📝 License

MIT
