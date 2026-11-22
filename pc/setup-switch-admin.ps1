# Run in an ADMINISTRATOR PowerShell window:
#   irm https://adammouhcine67-cmd.github.io/kitchen-prayer-clock/pc/setup-switch-admin.ps1 | iex
# Creates the two switch tasks (PCHelper-SwitchToDad / PCHelper-SwitchToAdam) and shows any error.
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


try {
    $ErrorActionPreference = 'Stop'
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw "This window is not 'Run as administrator'. Close it and open PowerShell with right-click > Run as administrator." }
    Write-Host ""
    Write-Host "Accounts on this PC:" -ForegroundColor Yellow
    Get-LocalUser | Where-Object { $_.Enabled -and ('Administrator','Guest','DefaultAccount','WDAGUtilityAccount' -notcontains $_.Name) } |
        ForEach-Object { Write-Host "   $($_.Name)    $($_.FullName)" }
    $AdamUser = Read-Host "Type YOUR account name (from the list)"
    $DadUser  = Read-Host "Type DAD's account name (from the list)"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    New-SwitchTask 'PCHelper-SwitchToDad'  $DadUser
    New-SwitchTask 'PCHelper-SwitchToAdam' $AdamUser
    Write-Host ""
    Write-Host "Done! Both switches are ready." -ForegroundColor Cyan
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Send a photo of this window." -ForegroundColor Red
}
