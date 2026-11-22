# Dad's PC Helper setup — run this while signed in to DAD's account.
# Makes the key combo Ctrl+Alt+Shift+F6 start Mortal Shell (the ESP32 presses it).
# Nothing runs in the background. Safe to run again.

$dir = Join-Path $env:LOCALAPPDATA 'PCHelper'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Write-Host ""
Write-Host "=== Dad's PC Helper setup ===" -ForegroundColor Cyan

function Test-GameName($s) { (($s -replace '[^A-Za-z0-9]', '').ToLower()) -like '*mortalshell*' }

# 1. Find Mortal Shell: desktop shortcut first, then the Start menu apps
$desktops = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
              (Join-Path $env:USERPROFILE 'OneDrive\Desktop')) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
$items = foreach ($d in $desktops) { Get-ChildItem -LiteralPath $d -File -Force -ErrorAction SilentlyContinue }
$game = $items | Where-Object { Test-GameName $_.BaseName } |
        Sort-Object { $_.Name -match '2' } -Descending | Select-Object -First 1
$cmd = $null
if ($game) {
    $cmd = "Start-Process -FilePath '$($game.FullName -replace "'", "''")'"
    Write-Host "[ok] Mortal Shell shortcut: $($game.Name)" -ForegroundColor Green
    # Stop the "Do you want to allow this app to make changes?" popup for the game
    # (runs it with Dad's normal rights; only affects Dad's account)
    $exe = $null
    if ($game.Extension -eq '.lnk') { $exe = (New-Object -ComObject WScript.Shell).CreateShortcut($game.FullName).TargetPath }
    elseif ($game.Extension -eq '.exe') { $exe = $game.FullName }
    if ($exe -and $exe -like '*.exe' -and (Test-Path $exe)) {
        $layers = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
        New-Item -Path $layers -Force | Out-Null
        Set-ItemProperty -Path $layers -Name $exe -Value '~ RUNASINVOKER'
        Write-Host "[ok] No more 'allow changes?' popup for $(Split-Path $exe -Leaf)" -ForegroundColor Green
    }
} else {
    $app = Get-StartApps -ErrorAction SilentlyContinue | Where-Object { Test-GameName $_.Name } | Select-Object -First 1
    if ($app) {
        $cmd = "Start-Process explorer.exe -ArgumentList 'shell:AppsFolder\$($app.AppID)'"
        Write-Host "[ok] Mortal Shell app: $($app.Name)" -ForegroundColor Green
    }
}
if (-not $cmd) {
    Write-Host "Couldn't find Mortal Shell." -ForegroundColor Red
    Write-Host "Files on this desktop:" -ForegroundColor Yellow
    $items | ForEach-Object { Write-Host "   $($_.Name)" }
    return
}
# only start it if it isn't already running (the ESP32 presses the key a few times while Dad signs in)
@"
if (Get-Process -ErrorAction SilentlyContinue | Where-Object { `$_.ProcessName -match 'mortal' }) { exit }
$cmd
"@ | Set-Content -Encoding UTF8 (Join-Path $dir 'launch-mortal-shell.ps1')

# 2. Start Menu shortcut with the key combo
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'PC Helper'
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut((Join-Path $startMenu 'Launch Mortal Shell.lnk'))
$lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $dir 'launch-mortal-shell.ps1')`""
$lnk.WindowStyle = 7
$lnk.Hotkey = 'Ctrl+Alt+Shift+F6'
$lnk.Save()
Write-Host "[ok] Launch Mortal Shell  ->  Ctrl+Alt+Shift+F6" -ForegroundColor Green

# 3. Ctrl+Alt+Shift+F9 in Dad's account = switch back to Adam (so Adam's "Get PC ready" always lands in Adam's account)
"Start-Process schtasks.exe -ArgumentList '/run','/tn','PCHelper-SwitchToAdam' -WindowStyle Hidden" |
    Set-Content -Encoding UTF8 (Join-Path $dir 'switch-to-adam.ps1')
$lnk2 = $shell.CreateShortcut((Join-Path $startMenu 'Switch to Adam.lnk'))
$lnk2.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk2.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $dir 'switch-to-adam.ps1')`""
$lnk2.WindowStyle = 7
$lnk2.Hotkey = 'Ctrl+Alt+Shift+F9'
$lnk2.Save()
Write-Host "[ok] Switch to Adam  ->  Ctrl+Alt+Shift+F9 (in Dad's account)" -ForegroundColor Green

# 4. Ctrl+Alt+Shift+F7 in Dad's account = put the PC to sleep (same as in Adam's account)
@"
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::SetSuspendState('Suspend', `$false, `$false) | Out-Null
"@ | Set-Content -Encoding UTF8 (Join-Path $dir 'sleep-pc.ps1')
$lnk3 = $shell.CreateShortcut((Join-Path $startMenu 'Sleep PC.lnk'))
$lnk3.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk3.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $dir 'sleep-pc.ps1')`""
$lnk3.WindowStyle = 7
$lnk3.Hotkey = 'Ctrl+Alt+Shift+F7'
$lnk3.Save()
Write-Host "[ok] Sleep PC  ->  Ctrl+Alt+Shift+F7 (in Dad's account)" -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT: sign out of this account and back in once, so Windows picks up the new keys." -ForegroundColor Yellow

Write-Host ""
Write-Host "Done! Test it: press Ctrl+Alt+Shift+F6 - Mortal Shell should start." -ForegroundColor Cyan
Write-Host ""
