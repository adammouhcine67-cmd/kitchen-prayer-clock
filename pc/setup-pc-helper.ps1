# PC Helper setup — run this while signed in to YOUR account (not your dad's).
# It sets up two secret key combos that the ESP32 "presses":
#   Ctrl+Alt+Shift+F9  = Get PC ready  (Chrome on 2nd monitor + Call of Duty)
#   Ctrl+Alt+Shift+F10 = Launch Call of Duty only
# Nothing runs in the background. Safe to run again.

$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:LOCALAPPDATA 'PCHelper'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Write-Host ""
Write-Host "=== PC Helper setup ===" -ForegroundColor Cyan

# 1. Find the Call of Duty shortcut on the desktop
$desktops = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
              (Join-Path $env:USERPROFILE 'OneDrive\Desktop')) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
function Test-CodName($s) { $n = ($s -replace '[^A-Za-z0-9]', '').ToLower(); $n -like '*callofduty*' -or $n -like '*blackops*' }

# a) Xbox / Game Pass app in the Start menu (preferred)
$codCmd = $null
$app = Get-StartApps -ErrorAction SilentlyContinue | Where-Object { Test-CodName $_.Name } |
       Sort-Object { if ($_.AppID -match '!') { 0 } else { 1 } } | Select-Object -First 1
if ($app) {
    $codCmd = "Start-Process explorer.exe -ArgumentList 'shell:AppsFolder\$($app.AppID)'"
    Write-Host "[ok] Call of Duty app: $($app.Name)" -ForegroundColor Green
} else {
    # b) a shortcut on the desktop
    $items = foreach ($d in $desktops) { Get-ChildItem -LiteralPath $d -File -Force -ErrorAction SilentlyContinue }
    $cod = $items | Where-Object { Test-CodName $_.BaseName } | Select-Object -First 1
    if ($cod) {
        $codCmd = "Start-Process -FilePath '$($cod.FullName -replace "'", "''")'"
        Write-Host "[ok] Call of Duty shortcut: $($cod.Name)" -ForegroundColor Green
    }
}
if (-not $codCmd) {
    Write-Host "Couldn't find Call of Duty." -ForegroundColor Red
    Write-Host "Apps I can see with 'Call', 'Duty' or 'Xbox' in the name:" -ForegroundColor Yellow
    Get-StartApps | Where-Object { $_.Name -match 'Call|Duty|Xbox|Ops' } | ForEach-Object { Write-Host "   $($_.Name)" }
    return
}

# 2. Find Chrome
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($chrome) { Write-Host "[ok] Chrome found" -ForegroundColor Green }
else { Write-Host "[!] Chrome not found - 'Get PC ready' will only start Call of Duty" -ForegroundColor Yellow }

# 3. Write the two small action scripts
$codCmd | Set-Content -Encoding UTF8 (Join-Path $dir 'launch-cod.ps1')

@"
Add-Type -AssemblyName System.Windows.Forms
`$chrome = '$($chrome -replace "'", "''")'
if (`$chrome -and (Test-Path `$chrome)) {
    `$second = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not `$_.Primary } | Select-Object -First 1
    if (`$second) {
        `$b = `$second.WorkingArea
        Start-Process `$chrome -ArgumentList "--new-window", "--window-position=`$(`$b.X + 40),`$(`$b.Y + 40)", "--start-maximized"
    } else {
        Start-Process `$chrome -ArgumentList "--new-window", "--start-maximized"
    }
}
Start-Sleep -Seconds 2
$codCmd
"@ | Set-Content -Encoding UTF8 (Join-Path $dir 'get-ready.ps1')

# 4. Start Menu shortcuts with key combos (Windows runs them when the keys are pressed)
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'PC Helper'
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
$shell = New-Object -ComObject WScript.Shell
function New-HotkeyShortcut($name, $script, $hotkey) {
    $lnk = $shell.CreateShortcut((Join-Path $startMenu "$name.lnk"))
    $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $dir $script)`""
    $lnk.WindowStyle = 7   # minimized
    $lnk.Hotkey = $hotkey
    $lnk.Save()
    Write-Host "[ok] $name  ->  $hotkey" -ForegroundColor Green
}
New-HotkeyShortcut 'Get PC ready'        'get-ready.ps1'  'Ctrl+Alt+Shift+F9'
New-HotkeyShortcut 'Launch Call of Duty' 'launch-cod.ps1' 'Ctrl+Alt+Shift+F10'

# 5. Power button = Sleep, and stop Windows waking up by itself (needs admin; skipped if not)
& powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 1 2>$null | Out-Null; $ok1 = ($LASTEXITCODE -eq 0)
& powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 0 2>$null | Out-Null; $ok2 = ($LASTEXITCODE -eq 0)
& powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null
if ($ok1) { Write-Host "[ok] Power button now puts the PC to sleep" -ForegroundColor Green }
else { Write-Host "[!] Couldn't set power button to Sleep - do it in Control Panel > Power Options" -ForegroundColor Yellow }
if ($ok2) { Write-Host "[ok] Windows won't wake itself up on a timer" -ForegroundColor Green }

Write-Host ""
Write-Host "Done! Test it: press Ctrl+Alt+Shift+F10 on your keyboard - Call of Duty should start." -ForegroundColor Cyan
Write-Host ""
