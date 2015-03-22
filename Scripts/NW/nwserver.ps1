<#
.Synopsis
   Short description
.DESCRIPTION
   labbuildr is a Self Installing Windows/Networker/NMM Environemnt Supporting Exchange 2013 and NMM 3.0
.LINK
   https://community.emc.com/blogs/bottk/2014/06/16/announcement-labbuildr-released
#>
#requires -version 3
[CmdletBinding()]
param(
[ValidateSet('nw8211','nw821','nw8205','nw8204','nw8203','nw8202','nw82','nw8116','nw8115','nw8114', 'nw8113','nw8112', 'nw811',  'nw8105','nw8104','nw8102', 'nw81', 'nwunknown')]$NW_ver = "nw821"

)
$ScriptName = $MyInvocation.MyCommand.Name
$Host.UI.RawUI.WindowTitle = "$ScriptName"
$Builddir = $PSScriptRoot
$Logtime = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"
$Logfile = New-Item -ItemType file  "$Builddir\$ScriptName$Logtime.log"
############
Set-Content -Path $Logfile $MyInvocation.BoundParameters
Write-Verbose "Setting Up SNMP"
Add-WindowsFeature snmp-service  -IncludeAllSubFeature -IncludeManagementTools
Set-Service SNMPTRAP -StartupType Automatic
Start-Service SNMPTRAP




Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters -Name "EnableAuthenticationTraps" -Value 0
Remove-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers -Name "1" -Force
New-Item -Path HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\TrapConfiguration -Force
New-Item -Path HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\TrapConfiguration\networker -Force
New-Item -Path HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\RFC1156Agent -Force
New-ItemProperty  -Path  HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\RFC1156Agent -Name "sysServices" -PropertyType "dword" -Value 76 -Force
New-ItemProperty  -Path  HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\RFC1156Agent -Name "sysLocation" -PropertyType "string" -Value 'labbuildr' -Force
New-ItemProperty  -Path  HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\RFC1156Agent -Name "sysContact" -PropertyType "string" -Value '@Hyperv_guy' -Force
New-ItemProperty  -Path  HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities -Name "networker" -PropertyType "dword" -Value 8 -Force

.$Builddir\test-sharedfolders.ps1
$Setuppath = "\\vmware-host\Shared Folders\Sources\$NW_ver\win_x64\networkr\setup.exe"
.$Builddir\test-setup -setup NWServer -setuppath $Setuppath


Start-Process -Wait -FilePath "$Setuppath" -ArgumentList ' /S /v" /passive /l*v c:\scripts\nwserversetup2.log INSTALLLEVEL=300 CONFIGFIREWALL=1 setuptype=Install"'
Start-Process -Wait -FilePath "$Setuppath" -ArgumentList '/S /v" /passive /l*v c:\scripts\nwserversetup2.log INSTALLLEVEL=300 CONFIGFIREWALL=1 NW_FIREWALL_CONFIG=1 setuptype=Install"'

$Setuppath = "\\vmware-host\Shared Folders\Sources\$NW_ver\win_x64\networkr\nmc\setup.exe"
.$Builddir\test-setup -setup NWConsole -setuppath $Setuppath
Start-Process -Wait -FilePath "$Setuppath" -ArgumentList '/S /v" /passive /l*v c:\scripts\nmcsetup2.log CONFIGFIREWALL=1 NW_FIREWALL_CONFIG=1 setuptype=Install"'

Write-Verbose "Setting up NMC"
# Start-Process -Wait -FilePath "javaws.exe" -ArgumentList "-import -silent -system -shortcut -association http://localhost:9000/gconsole.jnlp"
# start-process http://localhost:9000/gconsole.jnlp
