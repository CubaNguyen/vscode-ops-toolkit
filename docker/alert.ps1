param(
    [string]$server         = "YOUR_SERVER",
    [int]$interval          = 30,
    [int]$cpuThreshold      = 80,
    [int]$memThreshold      = 80,
    [int]$diskThreshold     = 85
)

# Load service list tu services.json
$CONFIG_FILE = Join-Path (Split-Path $PSScriptRoot -Parent) "services.json"
$config      = Get-Content $CONFIG_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
$blacklist   = $config.blacklist

$rawServices = ssh $server "docker ps --format '{{.Names}}'" 2>$null
$services = $rawServices -split "`n" |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" -and $blacklist -notcontains $_ }

# State tracking
$prevDown     = @{}
$prevHighCpu  = @{}
$prevHighMem  = @{}
$diskAlerted  = $false
$lastErrorLog = @{}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-Notification {
    param([string]$title, [string]$message, [string]$level = "Warning")
    $notify         = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon    = [System.Drawing.SystemIcons]::Warning
    $notify.Visible = $true
    $icon = if ($level -eq "Error") { [System.Windows.Forms.ToolTipIcon]::Error }
            else                    { [System.Windows.Forms.ToolTipIcon]::Warning }
    $notify.ShowBalloonTip(8000, $title, $message, $icon)
    Start-Sleep -Milliseconds 500
    $notify.Dispose()
}

function Beep-Alert {
    param([string]$type = "warn")
    if ($type -eq "critical") {
        [Console]::Beep(800, 300); Start-Sleep -Milliseconds 100
        [Console]::Beep(600, 300); Start-Sleep -Milliseconds 100
        [Console]::Beep(400, 600)
    } else {
        [Console]::Beep(600, 200); Start-Sleep -Milliseconds 100
        [Console]::Beep(500, 400)
    }
}

function Run-Tick {
    param([bool]$fullCheck = $false)

    # Build 1 lenh lon chay het tren server, 1 SSH duy nhat
    $sinceArg = $interval.ToString() + "s"

    # Phan log errors: chay song song cho tat ca service
    $logCmds = $services | ForEach-Object {
        "echo '=SVC=" + $_ + "=' && docker logs " + $_ + " --since " + $sinceArg + ' 2>&1 | grep -a "\"@l\":\"Error\"\|\"@l\":\"Fatal\"\|Unhandled exception" | tail -1'
    }

    $fullCmd = "echo '=RUNNING=' && docker ps --format '{{.Names}}'"
    $fullCmd += " && echo '=STATS=' && timeout 8 docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}'"
    $fullCmd += " && echo '=LOGS=' && " + ($logCmds -join " && ")

    if ($fullCheck) {
        $fullCmd += " && echo '=DISK=' && df / --output=pcent | tail -1"
        $fullCmd += " && echo '=NGINX=' && tail -1000 /var/log/nginx/access.log 2>/dev/null | grep -c ' 5[0-9][0-9] '; true"
    }

    $output = ssh $server $fullCmd 2>$null
    if (-not $output) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') Cannot reach $server" -ForegroundColor Yellow
        return
    }

    # Parse output theo section
    $section     = ""
    $runningList = @()
    $statsList   = @()
    $currentSvc  = ""
    $diskPct     = 0
    $nginxCount  = 0

    foreach ($line in ($output -split "`n")) {
        $line = $line.Trim()
        if ($line -eq "=RUNNING=") { $section = "running"; continue }
        if ($line -eq "=STATS=")   { $section = "stats";   continue }
        if ($line -eq "=LOGS=")    { $section = "logs";    continue }
        if ($line -eq "=DISK=")    { $section = "disk";    continue }
        if ($line -eq "=NGINX=")   { $section = "nginx";   continue }
        if ($line -eq "")          { continue }

        switch ($section) {
            "running" { $runningList += $line }
            "stats"   { $statsList   += $line }
            "disk"    {
                try { $diskPct = [int]($line -replace '%', '') } catch {}
            }
            "nginx"   {
                try { $nginxCount = [int]$line } catch {}
            }
            "logs" {
                if ($line -match "^=SVC=(.+)=$") {
                    $currentSvc = $Matches[1]; continue
                }
                if ($currentSvc -eq "") { continue }

                if (-not $lastErrorLog.ContainsKey($currentSvc) -or $lastErrorLog[$currentSvc] -ne $line) {
                    $displayMsg = $line
                    try {
                        $parsed = $line | ConvertFrom-Json
                        if ($parsed.'@m') { $displayMsg = $parsed.'@m' }
                    } catch {}
                    if ($displayMsg.Length -gt 150) { $displayMsg = $displayMsg.Substring(0, 150) + "..." }

                    Write-Host "$(Get-Date -Format 'HH:mm:ss') ERROR [$currentSvc]: $displayMsg" -ForegroundColor Red
                    Write-Host ("    >>> ssh YOUR_SERVER `"docker logs " + $currentSvc + " -f --tail 200 | python3 -u /tmp/dlog.py`"") -ForegroundColor DarkYellow
                    Show-Notification "Error: $currentSvc" $displayMsg "Error"
                    Beep-Alert "warn"
                    $lastErrorLog[$currentSvc] = $line
                }
            }
        }
    }

    # Check services up/down
    foreach ($svc in $services) {
        $isDown = $runningList -notcontains $svc
        if ($isDown -and (-not $prevDown.ContainsKey($svc) -or -not $prevDown[$svc])) {
            $msg = "$svc is DOWN!"
            Write-Host "$(Get-Date -Format 'HH:mm:ss') DOWN: $msg" -ForegroundColor Red
            Show-Notification "Service Down!" $msg "Error"
            Beep-Alert "critical"
            $prevDown[$svc] = $true
        }
        elseif (-not $isDown -and $prevDown.ContainsKey($svc) -and $prevDown[$svc]) {
            $msg = "$svc is back UP"
            Write-Host "$(Get-Date -Format 'HH:mm:ss') UP: $msg" -ForegroundColor Green
            Show-Notification "Service Recovered" $msg
            $prevDown[$svc] = $false
        }
    }

    # Check CPU/RAM
    foreach ($line in $statsList) {
        $parts = $line -split '\|'
        if ($parts.Count -lt 3) { continue }
        $name   = $parts[0].Trim()
        $cpuStr = $parts[1].Trim() -replace '%', ''
        $memStr = $parts[2].Trim() -replace '%', ''
        try { $cpu = [float]$cpuStr } catch { continue }
        try { $mem = [float]$memStr } catch { continue }

        if ($cpu -gt $cpuThreshold) {
            if (-not $prevHighCpu.ContainsKey($name) -or -not $prevHighCpu[$name]) {
                $msg = "$name CPU at ${cpu}%"
                Write-Host "$(Get-Date -Format 'HH:mm:ss') HIGH CPU: $msg" -ForegroundColor Red
                Show-Notification "High CPU!" $msg "Warning"
                Beep-Alert "warn"
                $prevHighCpu[$name] = $true
            }
        } else { $prevHighCpu[$name] = $false }

        if ($mem -gt $memThreshold) {
            if (-not $prevHighMem.ContainsKey($name) -or -not $prevHighMem[$name]) {
                $msg = "$name RAM at ${mem}%"
                Write-Host "$(Get-Date -Format 'HH:mm:ss') HIGH RAM: $msg" -ForegroundColor Magenta
                Show-Notification "High RAM!" $msg "Warning"
                Beep-Alert "warn"
                $prevHighMem[$name] = $true
            }
        } else { $prevHighMem[$name] = $false }
    }

    # Check disk (chi full check)
    if ($fullCheck -and $diskPct -gt 0) {
        if ($diskPct -ge $diskThreshold -and -not $diskAlerted) {
            $msg = "Server disk at " + $diskPct + "% - running out of space!"
            Write-Host "$(Get-Date -Format 'HH:mm:ss') DISK: $msg" -ForegroundColor Yellow
            Show-Notification "Disk Almost Full!" $msg "Error"
            Beep-Alert "critical"
            $script:diskAlerted = $true
        }
        elseif ($diskPct -lt ($diskThreshold - 5)) {
            $script:diskAlerted = $false
        }
    }

    # Check nginx 5xx (chi full check)
    if ($fullCheck -and $nginxCount -gt 10) {
        $msg = $nginxCount.ToString() + " server errors in last 1000 nginx requests"
        Write-Host "$(Get-Date -Format 'HH:mm:ss') NGINX 5xx: $msg" -ForegroundColor Yellow
        Show-Notification "Nginx 5xx Spike!" $msg "Warning"
        Beep-Alert "warn"
    }

    Write-Host "$(Get-Date -Format 'HH:mm:ss') All OK" -ForegroundColor DarkGray
}

# Main loop
Write-Host ""
Write-Host ("Monitoring [" + $server + "] every " + $interval + "s - " + $services.Count + " services") -ForegroundColor Cyan
Write-Host ("  CPU alert  : > " + $cpuThreshold + "%") -ForegroundColor Gray
Write-Host ("  RAM alert  : > " + $memThreshold + "%") -ForegroundColor Gray
Write-Host ("  Disk alert : > " + $diskThreshold + "%") -ForegroundColor Gray
Write-Host "  Log errors : @l Error / Fatal / Unhandled exception" -ForegroundColor Gray
Write-Host "  Press Ctrl+C to stop." -ForegroundColor Gray
Write-Host ""

$tick = 0
while ($true) {
    $fullCheck = ($tick % 5 -eq 0)
    Run-Tick -fullCheck $fullCheck
    $tick++
    Start-Sleep -Seconds $interval
}
