# Reliable key combos — run this in EACH account (Adam's and Dad's), normal PowerShell.
# Replaces Windows' shortcut hotkeys (which keep "forgetting" the keys) with a tiny listener
# that starts at sign-in and runs the PC Helper scripts:
#   Ctrl+Alt+Shift+F6  Adam: switch to Dad      | Dad: start Mortal Shell
#   Ctrl+Alt+Shift+F7  sleep the PC (both)
#   Ctrl+Alt+Shift+F8  Adam: Chrome on 2nd monitor
#   Ctrl+Alt+Shift+F9  Adam: Get PC ready        | Dad: switch to Adam
#   Ctrl+Alt+Shift+F10 Adam: Call of Duty

$dir = Join-Path $env:LOCALAPPDATA 'PCHelper'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Write-Host ""
Write-Host "=== Reliable keys setup ($env:USERNAME) ===" -ForegroundColor Cyan

# 1. the listener
@'
$dir = Join-Path $env:LOCALAPPDATA 'PCHelper'
$log = Join-Path $dir 'key-listener.log'
function Log($t) { Add-Content -Path $log -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $t) }
Set-Content -Path $log -Value "listener started for $env:USERNAME"
trap { Log "ERROR: $($_.Exception.Message)"; continue }
Add-Type -Namespace PCH -Name Keys -MemberDefinition @"
[DllImport("user32.dll", SetLastError=true)] public static extern bool RegisterHotKey(System.IntPtr h, int id, uint mods, uint vk);
[DllImport("user32.dll")] public static extern bool PeekMessage(out MSG m, System.IntPtr h, uint min, uint max, uint remove);
public struct MSG { public System.IntPtr hwnd; public uint message; public System.IntPtr wParam; public System.IntPtr lParam; public uint time; public int x; public int y; }
"@
# key -> first script that exists in this account
$map = @{
  0x75 = @('launch-mortal-shell.ps1', 'switch-to-dad.ps1')   # F6
  0x76 = @('sleep-pc.ps1')                                    # F7
  0x77 = @('open-chrome.ps1')                                 # F8
  0x78 = @('get-ready.ps1', 'switch-to-adam.ps1')             # F9
  0x79 = @('launch-cod.ps1')                                  # F10
}
$mods = 0x1 -bor 0x2 -bor 0x4 -bor 0x4000                      # Alt + Ctrl + Shift, no auto-repeat
foreach ($vk in @($map.Keys)) {
  $ok = [PCH.Keys]::RegisterHotKey([IntPtr]::Zero, [int]$vk, [uint32]$mods, [uint32]$vk)
  Log ("register F{0}: {1} (error {2})" -f ($vk - 0x6F), $ok, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
}
# DOUBLE press (twice within 1.5 s) = "switch account only" (room page Adam / Dad modes):
#   F6 x2 -> switch to Dad (only from Adam's account)    F9 x2 -> switch to Adam (only from Dad's account)
$double = @{ 0x75 = @('switch-to-dad.ps1'); 0x78 = @('switch-to-adam.ps1') }
function RunFirst($names, $label) {
  foreach ($name in $names) {
    $f = Join-Path $dir $name
    if (Test-Path $f) {
      Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$f`""
      Log "$label -> $name"; return
    }
  }
  Log "$label -> nothing to do in this account"
}
$m = New-Object 'PCH.Keys+MSG'
$pendVk = 0; $pendAt = [DateTime]::MinValue
Log "waiting for keys"
while ($true) {
  while ([PCH.Keys]::PeekMessage([ref]$m, [IntPtr]::Zero, 0, 0, 1)) {   # PM_REMOVE
    if ($m.message -eq 0x0312) {                                          # WM_HOTKEY
      $vk = [int]$m.wParam; $now = Get-Date
      if ($pendVk -eq $vk -and ($now - $pendAt).TotalMilliseconds -lt 1500) {
        $pendVk = 0
        RunFirst $double[$vk] ("F{0} double" -f ($vk - 0x6F))
      } else {
        if ($pendVk) { RunFirst $map[$pendVk] ("F{0}" -f ($pendVk - 0x6F)) }   # a different key: flush the waiting one
        $pendVk = $vk; $pendAt = $now
      }
    }
  }
  # single press: run it once no second press came within 1.5 s
  if ($pendVk -and ((Get-Date) - $pendAt).TotalMilliseconds -ge 1500) {
    $v = $pendVk; $pendVk = 0
    RunFirst $map[$v] ("F{0}" -f ($v - 0x6F))
  }
  Start-Sleep -Milliseconds 50
}
'@ | Set-Content -Encoding UTF8 (Join-Path $dir 'key-listener.ps1')
Write-Host "[ok] Key listener written" -ForegroundColor Green

# 2. remove the old Windows shortcut hotkeys (they would block the listener)
$old = Join-Path ([Environment]::GetFolderPath('Programs')) 'PC Helper'
if (Test-Path $old) {
    Remove-Item -Recurse -Force $old
    # restart Explorer so it lets go of the old keys (the taskbar blinks for a second)
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Start-Sleep -Seconds 2
    Write-Host "[ok] Old shortcut keys removed" -ForegroundColor Green
}

# 3. start the listener at every sign-in (Startup folder, this account only)
$startup = [Environment]::GetFolderPath('Startup')
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startup 'PC Helper keys.lnk'))
$lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $dir 'key-listener.ps1')`""
$lnk.WindowStyle = 7
$lnk.Save()
Write-Host "[ok] Starts automatically when this account signs in" -ForegroundColor Green

# 4. (re)start it now
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*key-listener.ps1*' -and $_.ProcessId -ne $PID } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $dir 'key-listener.ps1')`""
Write-Host "[ok] Listener running" -ForegroundColor Green

Write-Host ""
Write-Host "Done! Test: Ctrl+Alt+Shift+F7 should put the PC to sleep." -ForegroundColor Cyan
Write-Host ""
