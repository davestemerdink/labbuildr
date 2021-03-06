﻿<#
.Synopsis

.DESCRIPTION
   install-esxi is a standalone installer for esxi on vmware workstation
   the current devolpement requires a customized ESXi Image built for labbuildr
   currently, not all parameters will e supported / verified

   The script will generate a kickstart cd with all required parameters, clones a master vmx and injects disk drives and cd´d into is.

   The Required vmware Master can be downloaded fro https://community.emc.com/blogs/bottk/2015/03/30/labbuildrbeta#OtherTable,
   the customized esxi installimage can be found in https://community.emc.com/blogs/bottk/2015/03/30/labbuildrbeta#SoftwareTable

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
   https://community.emc.com/blogs/bottk/2015/03/30/labbuildrbeta
.EXAMPLE
    PS E:\LABBUILDR> .\install-esxi.ps1 -Nodes 2 -Startnode 2 -Disks 3 -Disksize 146GB -subnet 10.0.0.0 -BuildDomain labbuildr -esxiso C:\sources\ESX\ESXi-5.5.0-1331820-labbuildr-ks.iso -ESXIMasterPath '.\VMware ESXi 5' -Verbose
#>
[CmdletBinding()]
Param(
[Parameter(ParameterSetName = "defaults", Mandatory = $true)][switch]$Defaults,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][int32]$Nodes =1,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][int32]$Startnode = 1,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][int32]$Disks = 1,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][ValidateSet(36GB,72GB,146GB)][uint64]$Disksize = 146GB,
<# Specify your own Class-C Subnet in format xxx.xxx.xxx.xxx #>
[Parameter(ParameterSetName = "install",Mandatory=$true)][ValidateScript({$_ -match [IPAddress]$_ })][ipaddress]$subnet,
[Parameter(ParameterSetName = "install",Mandatory=$false)]
[ValidateLength(1,15)][ValidatePattern("^[a-zA-Z0-9][a-zA-Z0-9-]{1,15}[a-zA-Z0-9]+$")][string]$BuildDomain = "labbuildr",
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][ValidateScript({Test-Path -Path $_ -PathType Leaf -Include "VMware-VMvisor-Installer*labbuildr-ks*.iso"})]$esxiso,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(Mandatory=$false)][ValidateScript({ Test-Path -Path $_ -ErrorAction SilentlyContinue })]$ESXIMasterPath = ".\esximaster",
 <# NFS Parameter configures the NFS Default Datastore from DCNODE#>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][switch]$nfs,
<# future use, initializes nfs on DC#>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][switch]$initnfs,
<# should we use a differnt vmnet#>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][ValidateSet('vmnet1', 'vmnet2','vmnet3')]$vmnet = "vmnet2",
<# injects the kdriver for recoverpoint #>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][switch]$kdriver,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][switch]$esxui,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)][ValidateScript({ Test-Path -Path $_ })]$Defaultsfile=".\defaults.xml"

)

#requires -version 3.0
#requires -module vmxtoolkit 


If ($Defaults.IsPresent)
    {
     $labdefaults = Get-labDefaults
     if (!($labdefaults))
        {
        try
            {
            $labdefaults = Get-labDefaults -Defaultsfile ".\defaults.xml.example"
            }
        catch
            {
            Write-Warning "no  defaults or example defaults found, exiting now"
            exit
            }
        Write-Host -ForegroundColor Magenta "Using generic defaults from labbuildr"
        }
     $vmnet = $labdefaults.vmnet
     $subnet = $labdefaults.MySubnet
     $BuildDomain = $labdefaults.BuildDomain
     if (!$Sourcedir)
            {
            try
                {
                $Sourcedir = $labdefaults.Sourcedir
                }
            catch [System.Management.Automation.ParameterBindingException]
                {
                Write-Warning "No sources specified, trying default"
                $Sourcedir = "C:\Sources"
                }
            }

     #$Sourcedir = $labdefaults.Sourcedir
     $Gateway = $labdefaults.Gateway
     $DefaultGateway = $labdefaults.Defaultgateway
     $DNS1 = $labdefaults.DNS1
     $MasterPath = $labdefaults.MasterPath
     }



[System.Version]$subnet = $Subnet.ToString()
$Subnet = $Subnet.major.ToString() + "." + $Subnet.Minor + "." + $Subnet.Build
write-verbose "Subnet will be $subnet"
$Nodeprefix = "ESXiNode"
$MasterVMX = get-vmx -path $ESXIMasterPath
$Password = "Password123!"
$Builddir = $PSScriptRoot
Write-Verbose "Builddir is $Builddir"
if ($nfs.IsPresent -or $initnfs.IsPresent)
    {
    try {
    (Get-vmx -path $Builddir\dcnode).state -eq 'running'
    }
    catch
        {
        
        }
    }

if (!$MasterVMX.Template) 
    {
    write-verbose "Templating Master VMX"
    $template = $MasterVMX | Set-VMXTemplate
    }
$Basesnap = $MasterVMX | Get-VMXSnapshot | where Snapshot -Match "Base"

if (!$Basesnap) 
    {
    Write-verbose "Base snap does not exist, creating now"
    $Basesnap = $MasterVMX | New-VMXSnapshot -SnapshotName BASE
    }

####Build Machines#

foreach ($Node in $Startnode..(($Startnode-1)+$Nodes))
    {
    Write-Verbose "Checking VM $Nodeprefix$node already Exists"
    If (!(get-vmx $Nodeprefix$node))
    {
    Write-Host -ForegroundColor Magenta "Creating VM $Nodeprefix$Node"
    Write-Verbose "Clearing out old content"
    if (Test-Path .\iso\ks) { Remove-Item -Path .\iso\ks -Recurse }
    $KSDirectory = New-Item -ItemType Directory .\iso\KS
    
    $Content = Get-Content .\Scripts\ESX\KS.CFG
    ####modify $content
    #$Content = $Content | where {$_ -NotMatch "network"}
    $Content += "network --bootproto=static --device=vmnic0 --ip=$subnet.8$Node --netmask=255.255.255.0 --gateway=$DefaultGateway --nameserver=$DNS1 --hostname=$Nodeprefix$node.$Builddomain.local"
    $Content += "keyboard German"
    
        foreach ( $Disk in 1..$Disks)
        {
        Write-Host -ForegroundColor Magenta " ==>Customizing Datastore$Disk"
        $Content += "partition Datastore$Disk@$Nodeprefix$node --ondisk=mpx.vmhba1:C0:T$Disk"+":L0"
        }
    $Content += Get-Content .\Scripts\ESX\KS_PRE.cfg
    $Content += "echo 'network --bootproto=static --device=vmnic0 --ip=$subnet.8$Node --netmask=255.255.255.0 --gateway=$DefaultGateway --nameserver=$DNS1 --hostname=$Nodeprefix$node.$Builddomain.local' /tmp/networkconfig" 

    if ($esxui.IsPresent)
        {
        $Content += Get-Content .\Scripts\ESX\KS_POST.cfg
        $Post_section = $true
        ### everything here goes to post
        Write-Host -ForegroundColor Magenta " ==>injecting ESX-UI"
        try 
            {
            $Drivervib = Get-ChildItem "$Sourcedir\ESX\esxui*.vib" -ErrorAction Stop
            }
 
        catch [Exception] 
            {
            Write-Warning "could not copy ESXUI, please make sure to have Package in $Sourcedir"
            write-host $_.Exception.Message
            break
            }
        $Drivervib| Sort-Object -Descending | Select-Object -First 1 | Copy-Item -Destination .\iso\KS\ESXUI.VIB
        $Content += "cp -a /vmfs/volumes/mpx.vmhba32:C0:T0:L0/KS/ESXUI.VIB /vmfs/volumes/Datastore1@$Nodeprefix$node"
        }
        if ($kdriver.IsPresent)
        {
        if (!$Post_section)
            {
            $Content += Get-Content .\Scripts\ESX\KS_POST.cfg
            }
        Write-Host -ForegroundColor Magenta " ==>injecting K-Driver"
        try 
            {
            $Drivervib = Get-ChildItem "$Sourcedir\ESX\kdriver_RPESX-00.4.2*.vib" -ErrorAction Stop
            }
 
        catch [Exception] 
            {
            Write-Warning "could not copy K-Driver VIB, please make sure to have Kdriver/RP vor VM´s Package in $Sourcedir or specify right -driveletter"
            write-host $_.Exception.Message
            break
            }
        $Drivervib| Sort-Object -Descending | Select-Object -First 1 | Copy-Item -Destination .\iso\KS\KDRIVER.VIB
        $Content += "cp -a /vmfs/volumes/mpx.vmhba32:C0:T0:L0/KS/KDRIVER.VIB /vmfs/volumes/Datastore1@$Nodeprefix$node"
        }

    $Content += Get-Content .\Scripts\ESX\KS_FIRSTBOOT.cfg
    if ($kdriver.IsPresent)
        {
        $Content += "esxcli software acceptance set --level=CommunitySupported"
        $Content += "esxcli software vib install -v /vmfs/volumes/Datastore1@$Nodeprefix$node/KDRIVER.VIB"
        }
    if ($esxui.IsPresent)
        {
        $Content += "esxcli software acceptance set --level=CommunitySupported"
        $Content += "esxcli software vib install -v /vmfs/volumes/Datastore1@$Nodeprefix$node/ESXUI.VIB"
        }

    #$Content += "esxcli software acceptance set --level=CommunitySupported"
    $Content += "cp /var/log/hostd.log /vmfs/volumes/Datastore1@$Nodeprefix$node/firstboot-hostd.log"
    $Content += "cp /var/log/esxi_install.log /vmfs/volumes/Datastore1@$Nodeprefix$node/firstboot-esxi_install.log" 
    $Content += Get-Content .\Scripts\ESX\KS_REBOOT.cfg
    ######

    $Content += Get-Content .\Scripts\ESX\KS_SECONDBOOT.cfg
    #### finished
if ($nfs.IsPresent)
    {
    $Content += "esxcli storage nfs add --host $Subnet.10 --share /$BuildDomain"+"nfs --volume-name=SWDEPOT --readonly"
    $Content += "tar xzfv  /vmfs/volumes/SWDEPOT/ovf.tar.gz  -C /vmfs/volumes/Datastore1@$Nodeprefix$Node/"
    $Content += '/vmfs/volumes/Datastore1@ESXiNode1/ovf/tools/ovftool --diskMode=thin --datastore=Datastore1@'+$Nodeprefix+$Node+' --noSSLVerify --X:injectOvfEnv --powerOn "--net:Network 1=VM Network" --acceptAllEulas --prop:vami.ip0.VMware_vCenter_Server_Appliance='+$Subnet+'.89 --prop:vami.netmask0.VMware_vCenter_Server_Appliance=255.255.255.0 --prop:vami.gateway.VMware_vCenter_Server_Appliance='+$Subnet+'.103 --prop:vami.DNS.VMware_vCenter_Server_Appliance='+$Subnet+'.10 --prop:vami.hostname=vcenter1.labbuildr.local /vmfs/volumes/SWDEPOT/VMware-vCenter-Server-Appliance-5.5.0.20200-2183109_OVF10.ova "vi://root:'+$Password+'@127.0.0.1"'
    }
    $Content | Set-Content $KSDirectory\KS.CFG 

    if ($PSCmdlet.MyInvocation.BoundParameters["verbose"].IsPresent)
    {
    Write-Host -ForegroundColor Yellow "Kickstart Config:"
    $Content | Write-Host -ForegroundColor DarkGray
    pause
    }
    
    ####create iso, ned to figure out license of tools
    # Uppercasing files for joliet
    Get-ChildItem $KSDirectory -Recurse | Rename-Item -newname { $_.name.ToUpper() } -ErrorAction SilentlyContinue


    ####have to work on abs pathnames here

    write-verbose "Cloning $Nodeprefix$node"
    $NodeClone = $MasterVMX | Get-VMXSnapshot | where Snapshot -Match "Base" | New-VMXClone -CloneName $Nodeprefix$node 
    write-verbose "Config : $($Nodeclone.config)"
    
    $Config = Get-VMXConfig -config $NodeClone.config
    IF (!(Test-Path $VMWAREpath\mkisofs.exe))
        {
        Write-Warning "VMware ISO Tools not found, exiting"
        }

    Write-Verbose "Node Clonepath =  $($NodeClone.Path)"
    Write-Host -ForegroundColor Magenta " ==>Creating Kickstart CD"

    .$VMWAREpath\mkisofs.exe -o "$($NodeClone.path)\ks.iso"  "$Builddir\iso"   | Out-Null
    switch ($LASTEXITCODE)
        {
            2
                {
                Write-Warning "could not create CD"
                Break
                }
        }
    $config = $config | where {$_ -NotMatch "ide1:0"}
    Write-Host -ForegroundColor Magenta " ==>injecting kickstart CDROM"
    $config += 'ide1:0.present = "TRUE"'
    $config += 'ide1:0.fileName = "ks.iso"'
    $config += 'ide1:0.deviceType = "cdrom-image"'
    Write-Host -ForegroundColor Magenta " ==>injecting $esxiso CDROM"
    $config = $config | where {$_ -NotMatch "ide0:0"}
    $config += 'ide0:0.present = "TRUE"'
    $config += 'ide0:0.fileName = "'+$esxiso+'"'
    $config += 'ide0:0.deviceType = "cdrom-image"'
    Write-Host -ForegroundColor Magenta " ==>Creating Disks"
    foreach ($Disk in 1..$Disks)
        {
     if ($Disk -le 6)
        {
        $SCSI = 0
        $Lun = $Disk
        }
     if (($Disk -gt 6) -and ($Disk -le 14))
        {
        $SCSI = 0
        $Lun = $Disk+1
        }
     if (($Disk -gt 14) -and ($Disk -le 21))
        {
        $SCSI = 1
        $Lun = $Disk-15
        }
     if (($Disk -gt 21) -and ($Disk -le 29))
        {
        $SCSI = 1
        $Lun = $Disk-14
        }
     if (($Disk -gt 29) -and ($Disk -le 36))
        {
        $SCSI = 2
        $Lun = $Disk-30
        }
     if (($Disk -gt 36) -and ($Disk -le 44))
        {
        $SCSI = 2
        $Lun = $Disk-29
        }
     if (($Disk -gt 44) -and ($Disk -le 51))
        {
        $SCSI = 3
        $Lun = $Disk-45
        }
     if (($Disk -gt 51) -and ($Disk -le 59))
        {
        $SCSI = 3
        $Lun = $Disk-44
        }

        Write-Verbose "SCSI$($Scsi):$lun"
        $Diskname = "SCSI$SCSI"+"_LUN$LUN.vmdk"
        $Diskpath = "$($NodeClone.Path)\$Diskname"
        Write-Host -ForegroundColor Magenta " ==>Creating Disk #$Disk with $Diskname and a size of $($Disksize/1GB) GB"
        & $VMWAREpath\vmware-vdiskmanager.exe -c -s "$($Disksize/1GB)GB" -a lsilogic -t 0 $Diskpath 2>> error.txt | Out-Null
        $AddDrives  = @('scsi'+$scsi+':'+$LUN+'.present = "TRUE"')
        $AddDrives += @('scsi'+$scsi+':'+$LUN+'.deviceType = "disk"')
        $AddDrives += @('scsi'+$scsi+':'+$LUN+'.fileName = "'+$Diskname+'"')
        $AddDrives += @('scsi'+$scsi+':'+$LUN+'.mode = "persistent"')
        $AddDrives += @('scsi'+$scsi+':'+$LUN+'.writeThrough = "false"')
        $Config += $AddDrives
        }
    
    $Config | set-Content -Path $NodeClone.Config 
    Write-Host -ForegroundColor Magenta " ==>Setting NICs"
    #Set-VMXNetworkAdapter -Adapter 0 -ConnectionType hostonly -AdapterType vmxnet3 -config $NodeClone.Config
    if ($vmnet)
         {
          Write-Verbose "Configuring NIC 2 and 3 for $vmnet"
    #      Set-VMXNetworkAdapter -Adapter 1 -ConnectionType custom -AdapterType vmxnet3 -config $NodeClone.Config 
         write-verbose "Setting NIC0"
         Set-VMXNetworkAdapter -Adapter 0 -ConnectionType custom -AdapterType e1000 -config $NodeClone.Config | Out-Null
    #     get-vmxconfig -config $NodeClone.Config
         Set-VMXVnet -Adapter 0 -vnet $vmnet -config $NodeClone.Config  | Out-Null

    #     Set-VMXVnet -Adapter 2 -vnet $vmnet -config $NodeClone.Config
    #      get-vmxconfig -config $NodeClone.Config
        }
    $Scenario = Set-VMXscenario -config $NodeClone.Config -Scenarioname ESXi -Scenario 6
    $ActivationPrefrence = Set-VMXActivationPreference -config $NodeClone.Config -activationpreference $Node 
    Write-Verbose "Starting $Nodeprefix$node"
    # Set-VMXVnet -Adapter 0 -vnet vmnet2
    Set-VMXDisplayName -config $NodeClone.Config -Value "$($NodeClone.CloneName)@$Builddomain" | Out-Null
    Write-Host -ForegroundColor Magenta " ==>Starting $($NodeClone.CloneName)"
    start-vmx -Path $NodeClone.Path -VMXName $NodeClone.CloneName | Out-Null
    Write-Host -ForegroundColor Magenta "The ESX Build may take 2 Minutes ... "
    if ($esxui)
        {
        Write-Host -ForegroundColor Magenta "Connect to ESX UI Using https://$subnet.8$Node/ui"
        }
    } # end check vm
    else
    {
    Write-Warning "VM $Nodeprefix$node already exists"
    }
    }






