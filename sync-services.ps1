# sync-services.ps1
# Lấy danh sách container từ server, lọc blacklist, cập nhật tasks.json

$SSH_HOST    = "YOUR_SERVER"
$TASKS_FILE  = "$PSScriptRoot\.vscode\tasks.json"
$CONFIG_FILE = "$PSScriptRoot\services.json"

Write-Host "Đang lấy danh sách service từ $SSH_HOST..." -ForegroundColor Cyan

# Đọc blacklist từ services.json
$config    = Get-Content $CONFIG_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
$blacklist = $config.blacklist

# Lấy danh sách container đang chạy
$raw = ssh $SSH_HOST "docker ps --format '{{.Names}}' | sort" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Lỗi kết nối SSH tới $SSH_HOST" -ForegroundColor Red
    Write-Host $raw
    exit 1
}

# Lọc blacklist
$serviceList = $raw -split "`n" `
    | ForEach-Object { $_.Trim() } `
    | Where-Object { $_ -ne "" -and $blacklist -notcontains $_ }

if ($serviceList.Count -eq 0) {
    Write-Host "Không tìm thấy service nào sau khi lọc" -ForegroundColor Yellow
    exit 1
}

Write-Host "Tìm thấy $($serviceList.Count) services:" -ForegroundColor Green
$serviceList | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }

# Cập nhật tasks.json
$json  = Get-Content $TASKS_FILE -Raw -Encoding UTF8
$tasks = $json | ConvertFrom-Json

$serviceInput = $tasks.inputs | Where-Object { $_.id -eq "service" }
if ($null -eq $serviceInput) {
    Write-Host "Không tìm thấy input 'service' trong tasks.json" -ForegroundColor Red
    exit 1
}
$serviceInput.options = $serviceList

$newJson = $tasks | ConvertTo-Json -Depth 10
$newJson = $newJson -replace "\\u0026", "&" -replace "\\u003e", ">" -replace "\\u003c", "<"
Set-Content $TASKS_FILE -Value $newJson -Encoding UTF8

Write-Host ""
Write-Host "Đã cập nhật tasks.json với $($serviceList.Count) services." -ForegroundColor Green
Write-Host "Reload VS Code window để thấy danh sách mới (Ctrl+Shift+P → Reload Window)." -ForegroundColor Yellow
