# setup.ps1 — First-time setup for VSCode Ops Toolkit
# Run this once after cloning the repo

Write-Host ""
Write-Host "=== VSCode Ops Toolkit Setup ===" -ForegroundColor Cyan
Write-Host ""

# ── 1. Collect info ───────────────────────────────────────────────
$sshAlias = Read-Host "SSH host alias (e.g. my-server)"
if ($sshAlias -eq "") {
    Write-Host "SSH alias cannot be empty." -ForegroundColor Red
    exit 1
}

$sshIp = Read-Host "Server IP or hostname (e.g. 192.168.1.100)"
if ($sshIp -eq "") {
    Write-Host "Server IP cannot be empty." -ForegroundColor Red
    exit 1
}

$sshUser = Read-Host "SSH user (default: ubuntu)"
if ($sshUser -eq "") { $sshUser = "ubuntu" }

$keyName = Read-Host "SSH key filename in ~/.ssh/ (e.g. my-server.pem)"
if ($keyName -eq "") {
    Write-Host "Key filename cannot be empty." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Configuring with:" -ForegroundColor Cyan
Write-Host "  Host alias : $sshAlias" -ForegroundColor Gray
Write-Host "  Server IP  : $sshIp" -ForegroundColor Gray
Write-Host "  User       : $sshUser" -ForegroundColor Gray
Write-Host "  Key file   : ~/.ssh/$keyName" -ForegroundColor Gray
Write-Host ""

# ── 2. Replace YOUR_SERVER in project files ───────────────────────
$files = @(
    "$PSScriptRoot\.vscode\tasks.json",
    "$PSScriptRoot\docker\alert.ps1",
    "$PSScriptRoot\sync-services.ps1"
)

foreach ($file in $files) {
    if (-not (Test-Path $file)) {
        Write-Host "File not found: $file" -ForegroundColor Yellow
        continue
    }
    $content = Get-Content $file -Raw -Encoding UTF8
    $content = $content -replace "YOUR_SERVER", $sshAlias
    Set-Content $file -Value $content -Encoding UTF8
    Write-Host "Configured: $file" -ForegroundColor Green
}

# ── 3. Setup SSH config ───────────────────────────────────────────
$sshConfigPath = "$env:USERPROFILE\.ssh\config"
$sshKeyPath    = "~/.ssh/$keyName"

$sshEntry = @"

Host $sshAlias
    HostName $sshIp
    IdentityFile $sshKeyPath
    User $sshUser
"@

# Kiem tra da co entry nay chua
$existingConfig = ""
if (Test-Path $sshConfigPath) {
    $existingConfig = Get-Content $sshConfigPath -Raw -Encoding UTF8
}

if ($existingConfig -match "Host $sshAlias") {
    Write-Host "SSH config already has entry for '$sshAlias', skipping." -ForegroundColor Yellow
} else {
    Add-Content $sshConfigPath -Value $sshEntry -Encoding UTF8
    Write-Host "Added SSH config entry for '$sshAlias'" -ForegroundColor Green
}

# ── 4. Fix SSH key permission ─────────────────────────────────────
$keyFullPath = "$env:USERPROFILE\.ssh\$keyName"
if (Test-Path $keyFullPath) {
    Write-Host "Fixing SSH key permissions..." -ForegroundColor Cyan
    icacls $keyFullPath /inheritance:r /grant:r "$env:USERNAME:R" | Out-Null
    Write-Host "Key permissions fixed." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Key file not found at: $keyFullPath" -ForegroundColor Yellow
    Write-Host "Please copy your key file there before connecting." -ForegroundColor Yellow
}

# ── 5. Test SSH connection ────────────────────────────────────────
Write-Host ""
Write-Host "Testing SSH connection to '$sshAlias'..." -ForegroundColor Cyan
$testResult = ssh -o ConnectTimeout=5 -o BatchMode=yes $sshAlias "echo OK" 2>&1
if ($testResult -eq "OK") {
    Write-Host "SSH connection successful!" -ForegroundColor Green
} else {
    Write-Host "SSH connection failed. Check your key file and server IP." -ForegroundColor Red
    Write-Host "Error: $testResult" -ForegroundColor Gray
}

# ── Done ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Install Task Explorer extension in VS Code (spmeesseman)" -ForegroundColor Gray
Write-Host "  2. Reload VS Code window (Ctrl+Shift+P -> Reload Window)" -ForegroundColor Gray
Write-Host "  3. Run task: Setup: Upload all scripts to server" -ForegroundColor Gray
Write-Host "  4. Run task: Setup: Sync service list" -ForegroundColor Gray
Write-Host "  5. Run task: Linux: Who is logged in -- to verify everything works" -ForegroundColor Gray
Write-Host ""
