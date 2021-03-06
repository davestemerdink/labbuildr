﻿<#
.Synopsis

.DESCRIPTION
   import-viprva

   Copyright 2014 Karsten Bott

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

.LINK
   https://community.emc.com/blogs/bottk/2015/05/04/labbuildrannouncement-unattended-vipr-controller-deployment-for-vmware-workstation
.EXAMPLE
 Download and Install ViPR 2.3:
 .\install-vipr.ps1 -Defaults -viprmaster vipr-2.3.0.0.828
#>
[CmdletBinding()]
Param(

[Parameter(ParameterSetName = "defaults", Mandatory = $false)][switch]$Defaults = $true,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)][ValidateSet('vipr-2.3.0.0.828','vipr-2.2.1.0.1106','vipr-2.4.0.0.519','vipr-2.4.1.0.220','vipr-3.0.0.0.814')]$viprmaster = "vipr-3.0.0.0.814",
[Parameter(ParameterSetName = "defaults", Mandatory = $false)][ValidateScript({ Test-Path -Path $_ })]$Defaultsfile=".\defaults.xml"

)

$targetname = "vipr1"
$ViprZip = "ViPR_Controller_Download.zip"
$Viprver = $viprmaster.Replace("vipr-","")
Write-Verbose $Viprver
$ViprMajor = $Viprver.Substring(0,5)
Measure-Command {
If ($Defaults.IsPresent)
    {
     $labdefaults = Get-labDefaults
     $vmnet = $labdefaults.vmnet
     $subnet = $labdefaults.MySubnet
     $BuildDomain = $labdefaults.BuildDomain
     $Sourcedir = $labdefaults.Sourcedir
     $Defaultgateway = $labdefaults.DefaultGateway
     }
else
    {
    $subnet = "192.168.2.0"
    }
if ($LabDefaults.custom_domainsuffix)
	{
	$custom_domainsuffix = $LabDefaults.custom_domainsuffix
	}
else
	{
	$custom_domainsuffix = "local"
	}

if (!(test-path $Sourcedir))
    {
    Write-Warning " $Sourcedir not found. we need a Valid Directory for sources specified with set-labsources"
    exit
    }



[System.Version]$subnet = $Subnet.ToString()
$Subnet = $Subnet.major.ToString() + "." + $Subnet.Minor + "." + $Subnet.Build
if (!$Defaultgateway)
    {
    $Defaultgateway = "$subnet.9"
    }
if (get-vmx $targetname)
    {
    Write-Warning " the Virtual Machine already exists"
    Break
    }

$Disks = ('disk1','disk2','disk5')
$masterpath = "$PSScriptRoot\$viprmaster"
$Missing = @()
foreach ($Disk in $Disks)
    {
    if (!(Test-Path -Path "$masterpath\*$Disk.vmdk"))
        {
        if (!(test-path "$Sourcedir\Vipr*\$viprmaster-controller-1+0.ova"))
            {
            Write-Warning "Vipr OVA for $Viprver not Found, we try for Zip Package in Sources"
            if (!(Test-Path "$Sourcedir\$ViprZip"))
                {
                Write-Warning "Vipr Controller Download Package not found
                               we will try download"
                

                    #}
                Switch ($Viprver)
                {
            "2.2.1.0.1106"
                {
                $ViprURL = "ftp://ftp.emc.com/ViPR/ViPR_Controller_Download.zip"
                $Zippackage = Split-Path -Leaf $ViprURL
                Get-LABFTPFile -Source $ViprURL -Defaultcredentials -Target "$Sourcedir\$viprmaster.zip" -Verbose

                }
            default
                {
                $ViprURL = "https://downloads.emc.com/emc-com/usa/ViPR/ViPR_Controller_Download.zip"
                $ViprZip = Split-Path -Leaf $ViprURL
                try
                    {
                    # $Request = Invoke-WebRequest $ViprURL -UseBasicParsing -Method Head
                    Start-BitsTransfer -DisplayName ViPR -Description "ViPR Controller" -Destination $Sourcedir -Source  $ViprURL
                    }
                catch [Exception] 
                    {
                    Write-Warning "Could not downlod $ViprURL. please download manually"
                    Write-Warning $_.Exception
                    exit
                    }
                }
            }

             }
            $Zipfiles = Get-ChildItem "$Sourcedir\$ViprZip"
            $Zipfiles = $Zipfiles| Sort-Object -Property Name -Descending
		    $LatestZip = $Zipfiles[0].FullName
	        write-verbose "We are going to extract $LatestZip now"    	
            Expand-LABZip -zipfilename $LatestZip -destination $Sourcedir
            }
            $Viprova = Get-Item "$Sourcedir\Vipr*\$viprmaster-controller-1+0.ova" -filter "*.ova" -ErrorAction SilentlyContinue
            $Viprova = $Viprova| Sort-Object -Property Name -Descending | Select-Object -Last 1
		    $LatestViprOVA = $Viprova.FullName
            $LatestVipr = $Viprova.Name.Replace("-controller-1+0.ova","")
            $LatestViprLic = Get-ChildItem -Path "$Sourcedir\ViPRC*$ViprMajor*\*" -Filter *.lic
            Write-Warning "We found $LatestVipr"
            $masterpath = "$Sourcedir\$LatestVipr"
            if (!$LatestViprOVA)
                { 
                Write-Warning "Could not find any ViprOVA in $Sourcedir to use"
                exit
                }
            if (!(Test-Path "$global:vmwarepath\7za.exe"))
                    {
                    Write-Warning " 7zip not found
                    7za is part of VMware Workstation 11 or the 7zip Distribution
                    please get and copy 7za to & $global:vmwarepath\7za.exe"
                    exit
                    }
            Write-warning "$Disk not found, deflating ViprDisk from OVA"
            & $global:vmwarepath\7za.exe x "-o$masterpath" -y $LatestViprOVA "*$Disk.vmdk" 
            if (!(Test-Path "$Sourcedir\$LatestVipr\$($LatestViprLic.Name)"))
                {
                Copy-Item $LatestViprLic.FullName -Destination "$masterpath\$($LatestViprLic.Name)" -Force
                }
        }

    }


Write-Warning "importing the disks "

if(!(Test-Path $PSScriptRoot\$targetname))
    {
    New-Item -ItemType Directory $PSScriptRoot\$targetname | Out-Null
    }
foreach ($Disk in $Disks)
    {
    
    $SOURCEDISK = Get-ChildItem -Path "$masterpath\vipr-*$disk.vmdk"
    $TargetDisk = "$PSScriptRoot\$targetname\$Disk.vmdk"
    if (Test-Path $TargetDisk)
        { 
        write-warning "Master $TargetDisk already present, no conversion needed"
        }
    else
        {
        write-warning "converting $TargetDisk"
        & $VMwarepath\vmware-vdiskmanager.exe -r $SOURCEDISK.FullName -t 0 $TargetDisk  2>&1 | Out-Null
        If ($Disk -match "Disk5")
            {
            # will need this for the storageos installer once figure out ovf-env disk :-)
            # & $VMwarepath\vmware-vdiskmanager.exe $PSScriptRoot\$targetname\disk3.vmdk -x 122GB
            }
        }
    }


# & $global:vmwarepath\OVFTool\ovftool.exe --lax --skipManifestCheck  --name=$targetname $masterpath\viprmaster.ovf $PSScriptRoot 
Write-Verbose " Copy base vm config to new master"

Copy-Item $PSScriptRoot\scripts\viprmaster\viprmaster.vmx $targetname\$targetname.vmx
$vmx = get-vmx $targetname
$vmx | Set-VMXTemplate -unprotect
$vmx | Set-VMXNetworkAdapter -Adapter 0 -AdapterType vmxnet3 -ConnectionType custom
$vmx | Set-VMXVnet -Adapter 0 -vnet $vmnet
$vmx | Set-VMXDisplayName -DisplayName $targetname
Write-Verbose "Generating CDROM"

Write-Verbose "Creating OVFenvironment"
$ovfenv = '<?xml version="1.0" encoding="UTF-8"?>
<Environment
     xmlns="http://schemas.dmtf.org/ovf/environment/1"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xmlns:oe="http://schemas.dmtf.org/ovf/environment/1"
     xmlns:ve="http://www.vmware.com/schema/ovfenv"
     oe:id="vipr1"
     ve:vCenterId="vm-21012">
   <PlatformSection>
      <Kind>VMware ESXi</Kind>
      <Version>5.5.0</Version>
      <Vendor>VMware, Inc.</Vendor>
      <Locale>de_DE</Locale>
   </PlatformSection>
   <PropertySection>
         <Property oe:key="network_1_ipaddr" oe:value="'+$subnet+'.9"/>
         <Property oe:key="network_1_ipaddr6" oe:value="::0"/>
         <Property oe:key="network_gateway" oe:value="'+$defaultgateway+'"/>
         <Property oe:key="network_gateway6" oe:value="::0"/>
         <Property oe:key="network_netmask" oe:value="255.255.255.0"/>
         <Property oe:key="network_vip" oe:value="'+$subnet+'.9"/>
         <Property oe:key="network_vip6get" oe:value="::0"/>
         <Property oe:key="node_count" oe:value="1"/>
   </PropertySection>
</Environment>
'

if ($PSCmdlet.MyInvocation.BoundParameters["verbose"].IsPresent)
    {
    Write-Host -ForegroundColor Yellow $ovfenv
    }

$ViprcdDir = join-path $PSScriptRoot "scripts\viprmaster\cd\"
if (!(Test-Path $ViprcdDir))
    {
    New-Item -ItemType Directory -Path $ViprcdDir
    }
$ovffile = (Join-Path $ViprcdDir ovf-env.xml)
$ovfenv  | Set-Content -Path $ovffile -Force
convert-VMXdos2unix -Sourcefile $ovffile -Verbose
& $Global:vmwarepath\mkisofs.exe -J -R -o "$PSScriptRoot\$Targetname\vipr.iso" $PSScriptRoot\scripts\viprmaster\cd 2>&1 | Out-Null
$config = $vmx | get-vmxconfig
    write-verbose "injecting CDROM"
    $config = $config | where {$_ -NotMatch "ide0:0"}
    $config += 'ide0:0.present = "TRUE"'
    $config += 'ide0:0.fileName = "vipr.iso"'
    $config += 'ide0:0.deviceType = "cdrom-image"'
$Config | set-Content -Path $vmx.config
$Annotation = $VMX | Set-VMXAnnotation -Line1 "https://$subnet.9" -Line2 "user:root" -Line3 "password:ChangeMe" -Line4 "add license from $masterpath" -Line5 "labbuildr by @sddc_guy" -builddate
$vmx | Start-VMX
Write-Host -ForegroundColor Magenta "
Successfully Deployed $viprmaster
wait a view minutes for storageos to be up and running
point your browser to https://$subnet.9 
Login with root:ChangeMe and follow the wizard steps
The License File can be found in $masterpath
"
}
