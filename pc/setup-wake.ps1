# Sets up this Windows PC so an iPad can turn it on (Wake-on-LAN).
# Run in PowerShell as Administrator. Safe to run more than once.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "Please run this as Administrator:" -ForegroundColor Yellow
    Write-Host "  Start menu -> type PowerShell -> right-click 'Windows PowerShell' -> Run as administrator" -ForegroundColor Yellow
    Write-Host ""
    return
}

Write-Host ""
Write-Host "=== Wake-on-LAN setup ===" -ForegroundColor Cyan

# 1. Find the wired network adapter(s)
$wired = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
    Where-Object { $_.MediaType -eq '802.3' -and $_.InterfaceDescription -notmatch 'Wireless|Wi-?Fi|Bluetooth|Virtual' }

if (-not $wired) {
    Write-Host ""
    Write-Host "No wired (Ethernet) network adapter found." -ForegroundColor Red
    Write-Host "Wake-on-LAN needs the PC plugged into the router with a network cable." -ForegroundColor Red
    return
}

foreach ($a in $wired) {
    Write-Host ""
    Write-Host ("Adapter: {0}  ({1})  status: {2}" -f $a.Name, $a.InterfaceDescription, $a.Status)

    # 2. Driver settings: wake on magic packet, and keep the link alive when shut down
    $props = Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue
    foreach ($p in $props) {
        $want = $null
        if ($p.RegistryKeyword -eq '*WakeOnMagicPacket') { $want = '1' }
        elseif ($p.DisplayName -match 'Shutdown Wake|Wake.*Shutdown|Wake on LAN|WOL') {
            $enabled = $p.ValidDisplayValues | Where-Object { $_ -match '^(Enabled|On)$' } | Select-Object -First 1
            if ($enabled) { $want = $enabled }
        }
        elseif ($p.DisplayName -match 'Energy.*Ethernet|Green Ethernet|Power Saving Mode|Ultra Low Power') {
            $off = $p.ValidDisplayValues | Where-Object { $_ -match '^(Disabled|Off)$' } | Select-Object -First 1
            if ($off) { $want = $off }
        }
        if ($want) {
            try {
                if ($p.RegistryKeyword -eq '*WakeOnMagicPacket') {
                    Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword $p.RegistryKeyword -RegistryValue $want -NoRestart -ErrorAction Stop
                } else {
                    Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $p.DisplayName -DisplayValue $want -NoRestart -ErrorAction Stop
                }
                Write-Host ("  [ok] {0} -> {1}" -f $p.DisplayName, $want) -ForegroundColor Green
            } catch {
                Write-Host ("  [skip] {0}: {1}" -f $p.DisplayName, $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    }

    # 3. Windows power management: allow this adapter to wake the PC, only on a magic packet
    try {
        Set-NetAdapterPowerManagement -Name $a.Name -WakeOnMagicPacket Enabled -ErrorAction Stop
        Write-Host "  [ok] Allow magic packet to wake the computer" -ForegroundColor Green
    } catch { Write-Host "  [skip] Power management: $($_.Exception.Message)" -ForegroundColor DarkYellow }
    & powercfg /deviceenablewake "$($a.InterfaceDescription)" 2>$null | Out-Null
    Write-Host "  [ok] Device allowed to wake the computer" -ForegroundColor Green

    # Restart the adapter so driver settings apply (brief network blip)
    Restart-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue
}

# 4. Turn off Fast Startup (it stops Wake-on-LAN working after a shutdown)
try {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord -ErrorAction Stop
    Write-Host ""
    Write-Host "[ok] Fast Startup turned off" -ForegroundColor Green
} catch { Write-Host "[skip] Fast Startup: $($_.Exception.Message)" -ForegroundColor DarkYellow }

# 5. Show what the iPad app needs
Start-Sleep -Seconds 4
Write-Host ""
Write-Host "=== Put these into the 'Wake Me Up' app on the iPad ===" -ForegroundColor Cyan
foreach ($a in (Get-NetAdapter -Physical | Where-Object { $_.Name -in $wired.Name })) {
    $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    Write-Host ("  MAC address : {0}" -f ($a.MacAddress -replace '-', ':')) -ForegroundColor White
    if ($ip) {
        $parts = $ip.Split('.'); $bcast = "$($parts[0]).$($parts[1]).$($parts[2]).255"
        Write-Host ("  PC IP       : {0}" -f $ip) -ForegroundColor White
        Write-Host ("  Broadcast   : {0}   (use this if the app asks for an address)" -f $bcast) -ForegroundColor White
    }
    Write-Host "  Port        : 9" -ForegroundColor White
}

Write-Host ""
Write-Host "Last step (one time): restart the PC, open the BIOS/UEFI setup" -ForegroundColor Yellow
Write-Host "(press Del or F2 while it starts) and turn ON 'Wake on LAN' /" -ForegroundColor Yellow
Write-Host "'Power On By PCI-E' / 'Resume by LAN'. Turn OFF 'ErP' / 'Deep Sleep' if you see it." -ForegroundColor Yellow
Write-Host ""
