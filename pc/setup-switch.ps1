# Account-switch setup — run this from ADAM's account (Windows asks for permission once).
# Creates two Windows tasks that send the PC to the sign-in screen with the right person
# already selected, so the ESP32 only has to press Enter:
#   PCHelper-SwitchToDad   (Adam's account:  Ctrl+Alt+Shift+F6)
#   PCHelper-SwitchToAdam  (Dad's account:   Ctrl+Alt+Shift+F9 — added by setup-dad.ps1)
# Nothing in your account is deleted or changed; switching is the same as Windows "Switch user".
param([switch]$AdminPart, [string]$AdamUser, [string]$DadUser)

$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:ProgramData 'PCHelper'

function New-SwitchTask($taskName, $userName) {
    $u = Get-LocalUser -Name $userName
    $sid = $u.SID.Value
    $full = if ($u.FullName) { $u.FullName } else { $u.Name }
    $sam = "$env:COMPUTERNAME\$($u.Name)"
    $file = Join-Path $dir "$taskName.ps1"
    @"
`$k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI'
Set-ItemProperty `$k -Name LastLoggedOnUser        -Value '$sam'
Set-ItemProperty `$k -Name LastLoggedOnSAMUser     -Value '$sam'
Set-ItemProperty `$k -Name LastLoggedOnUserSID     -Value '$sid'
Set-ItemProperty `$k -Name LastLoggedOnDisplayName -Value '$($full -replace "'", "''")'
Set-ItemProperty `$k -Name SelectedUserSID         -Value '$sid'
Add-Type -Namespace PCH -Name W -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern uint WTSGetActiveConsoleSessionId();
[DllImport("wtsapi32.dll")] public static extern bool WTSDisconnectSession(System.IntPtr h, uint id, bool wait);
'@
`$id = [PCH.W]::WTSGetActiveConsoleSessionId()
[PCH.W]::WTSDisconnectSession([System.IntPtr]::Zero, `$id, `$false) | Out-Null
"@ | Set-Content -Encoding UTF8 $file
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$file`""
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
    $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
    $svc.GetFolder('\').GetTask($taskName).SetSecurityDescriptor('D:(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;AU)', 0)  # normal users may start it
    Write-Host "[ok] $taskName -> $($u.Name)" -ForegroundColor Green
}

if ($AdminPart) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    New-SwitchTask 'PCHelper-SwitchToDad'  $DadUser
    New-SwitchTask 'PCHelper-SwitchToAdam' $AdamUser
    Write-Host "You can close this window." -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    return
}

# ---------- runs as Adam (normal) ----------
Write-Host ""
Write-Host "=== Account switch setup ===" -ForegroundColor Cyan
$me = $env:USERNAME
$skip = 'Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount', $me
$others = @(Get-LocalUser | Where-Object { $_.Enabled -and ($skip -notcontains $_.Name) })
if ($others.Count -ne 1) {
    Write-Host "Other accounts on this PC — type Dad's exactly:" -ForegroundColor Yellow
    $others | ForEach-Object { Write-Host "   $($_.Name)  $($_.FullName)" }
    $dad = Read-Host "Dad's account name"
} else { $dad = $others[0].Name }
Write-Host "[ok] Your account: $me    Dad's account: $dad" -ForegroundColor Green

# key combo in Adam's account: switch to Dad
$udir = Join-Path $env:LOCALAPPDATA 'PCHelper'
New-Item -ItemType Directory -Force -Path $udir | Out-Null
"Start-Process schtasks.exe -ArgumentList '/run','/tn','PCHelper-SwitchToDad' -WindowStyle Hidden" |
    Set-Content -Encoding UTF8 (Join-Path $udir 'switch-to-dad.ps1')
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'PC Helper'
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startMenu 'Switch to Dad.lnk'))
$lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $udir 'switch-to-dad.ps1')`""
$lnk.WindowStyle = 7
$lnk.Hotkey = 'Ctrl+Alt+Shift+F6'
$lnk.Save()
Write-Host "[ok] Switch to Dad  ->  Ctrl+Alt+Shift+F6 (in your account)" -ForegroundColor Green

# admin part (Windows asks "allow changes?" once)
$self = Join-Path $udir 'setup-switch.ps1'
Invoke-WebRequest 'https://adammouhcine67-cmd.github.io/kitchen-prayer-clock/pc/setup-switch.ps1' -OutFile $self -UseBasicParsing
Write-Host "Windows will ask for permission — click Yes." -ForegroundColor Yellow
Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$self`" -AdminPart -AdamUser `"$me`" -DadUser `"$dad`""
Write-Host ""
Write-Host "Done! Now sign in to Dad's account and run his setup line." -ForegroundColor Cyan
Write-Host ""
