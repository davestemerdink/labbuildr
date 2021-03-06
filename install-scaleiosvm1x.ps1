﻿<#
.Synopsis
   .\install-scaleiosvm.ps1 
.DESCRIPTION
  install-scaleiosvm is  the a vmxtoolkit solutionpack for configuring and deploying scaleio svm´s
      
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
   https://github.com/bottkars/labbuildr/wiki/SolutionPacks#install-scaleiosvm  
.EXAMPLE
.\install-scaleiosvm.ps1 -Sourcedir d:\sources
.EXAMPLE
.\install-scaleiosvm.ps1 -configure -Defaults
This will Install and Configure a 3-Node ScaleIO with default Configuration
.EXAMPLE
.\install-scaleiosvm.ps1 -SCALEIOMaster ".\ScaleIOVM_1.32.402.1" -configure -singlemdm
This will Configure a SIO Cluster with 3 Nodes and Single MDM
.EXAMPLE
.\install-scaleiosvm.ps1 -SCALEIOMaster ".\ScaleIOVM_1.32.402.1" -Disks 3  -sds
This will install a Single Node SDS
#>
[CmdletBinding(DefaultParametersetName = "import")]
Param(
### import parameters
<# for the Import, we specify the Path to the Sources. 
Sources are the Root of the Extracted ScaleIO_VMware_SW_Download.zip
If not available, it will be downloaded from http://www.emc.com/scaleio
The extracte OVA will be dehydrated to a VMware Workstation Master #>
[Parameter(ParameterSetName = "import",Mandatory=$true)][switch]$import,

[Parameter(ParameterSetName = "import",Mandatory=$false)]$OVAPath,
[Parameter(ParameterSetName = "import",Mandatory=$false)][String]
[ValidateScript({ Test-Path -Path $_ -ErrorAction SilentlyContinue })]$Sourcedir,

#### install parameters#
<# The ScaleIO Master created from -sourcedir  #>
[Parameter(ParameterSetName = "defaults",Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)]
[Parameter(ParameterSetName = "sdsonly",Mandatory=$false)]
[String]$SCALEIOMaster = ".\ScaleIOVM*",
<# Number of Nodes, default to 3 #>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)]
[Parameter(ParameterSetName = "sdsonly",Mandatory=$false)][int32]$Nodes=3,
<# Starting Node #>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)]
[Parameter(ParameterSetName = "sdsonly",Mandatory=$false)][int32]$Startnode = 1,
<# Number of disks to add, default is 3#>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "sdsonly",Mandatory=$false)]
[Parameter(ParameterSetName = "install",Mandatory=$False)][ValidateRange(1,3)][int32]$Disks = 3,
<# Specify your own Class-C Subnet in format xxx.xxx.xxx.xxx #>
[Parameter(ParameterSetName = "install",Mandatory=$false)]
[Parameter(ParameterSetName = "sdsonly",Mandatory=$false)][ValidateScript({$_ -match [IPAddress]$_ })][ipaddress]$subnet = "192.168.2.0",
<# Name of the domain, .local added#>
[Parameter(ParameterSetName = "sdsonly",Mandatory=$false)]
[Parameter(ParameterSetName = "install",Mandatory=$False)]
[ValidateLength(1,15)][ValidatePattern("^[a-zA-Z0-9][a-zA-Z0-9-]{1,15}[a-zA-Z0-9]+$")][string]$BuildDomain = "labbuildr",

<# VMnet to use#>
[Parameter(ParameterSetName = "sdsonly",Mandatory=$false)]
[Parameter(ParameterSetName = "install",Mandatory = $false)][ValidateSet('vmnet2','vmnet3','vmnet4','vmnet5','vmnet6','vmnet7','vmnet9','vmnet10','vmnet11','vmnet12','vmnet13','vmnet14','vmnet15','vmnet16','vmnet17','vmnet18','vmnet19')]$vmnet = "vmnet2",
<# SDS only#>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "sdsonly",Mandatory=$true)][switch]$sds,
<# SDC only3#>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "sdsonly",Mandatory=$false)][switch]$sdc,
<# Configure automatically configures the ScaleIO Cluster and will always install 3 Nodes !  #>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)][switch]$configure,
<# we use SingleMDM parameter with Configure for test and dev to Showcase ScaleIO und LowMem Machines #>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$False)][switch]$singlemdm,
<# Use labbuildr Defaults.xml #>
[Parameter(ParameterSetName = "import", Mandatory = $false)]

[Parameter(ParameterSetName = "defaults", Mandatory = $true)][switch]$Defaults,
<# Path to a Defaults.xml #>
[Parameter(ParameterSetName = "defaults", Mandatory = $false)][ValidateScript({ Test-Path -Path $_ })]$Defaultsfile=".\defaults.xml"
)
#requires -version 3.0
#requires -module vmxtoolkit
#requires -module labtools
If ($singlemdm.IsPresent)
    {
    [switch]$configure = $true
    }
if ($configure.IsPresent)
    {
    [switch]$sds = $true
    [switch]$sdc = $true
    }
If ($Defaults.IsPresent)
    {
     $labdefaults = Get-labDefaults
     $vmnet = $labdefaults.vmnet
     $subnet = $labdefaults.MySubnet
     $BuildDomain = $labdefaults.BuildDomain
     $Sourcedir = $labdefaults.Sourcedir
     $DefaultGateway = $labdefaults.DefaultGateway
     $Sourcedir = $labdefaults.Sourcedir
     }
[System.Version]$subnet = $Subnet.ToString()
$Subnet = $Subnet.major.ToString() + "." + $Subnet.Minor + "." + $Subnet.Build
$rootuser = "root"
$rootpassword = "admin"
$MDMPassword = "Password123!"
[uint64]$Disksize = 100GB
$scsi = 0
$ScaleIO_OS = "VMware"
$ScaleIO_Path = "ScaleIO_$($ScaleIO_OS)_SW_Download"
$Devicename = "$Location"+"_Disk_$Driveletter"
$VolumeName = "Volume_$Location"
$ProtectionDomainName = "PD_$BuildDomain"
$StoragePoolName = "SP_$BuildDomain"
$SystemName = "ScaleIO@$BuildDomain"
$FaultSetName = "Rack_"
$mdm_ipa  = "$subnet.191"
$mdm_ipb  = "$subnet.192"
$tb_ip = "$subnet.193"


switch ($PsCmdlet.ParameterSetName)
{
    "import"
        {
        if (!($OVAPath))
            {
        Try 
            {
            test-Path $Sourcedir
            } 
        Catch 
            { 
            Write-Verbose $_ 
            Write-Warning "We need a Valid Sourcedir, trying Defaults"
            if (!($Sourcedir = (Get-labDefaults).Sourcedir))
                {
                exit
                }
            }

        


        if (!($OVAPath = Get-ChildItem -Path "$Sourcedir\ScaleIO\$ScaleIO_Path" -recurse -Filter "SCALEIOVM_1*.ova" -ErrorAction SilentlyContinue))
        { 
                    write-warning "No ScaleIO OVA Version 1.x found, Please download Manually and extrax to $Sourcedir\ScaleIO\$ScaleIO_Path"
                    <#
                    $Uri = "http://www.emc.com/products-solutions/trial-software-download/scaleio.htm"
                    $request = Invoke-WebRequest -Uri $Uri -UseBasicParsing
                    $DownloadLinks = $request.Links | where href -match "VMWARE"
                    foreach ($Link in $DownloadLinks)
                        {
                        $Url = $link.href
                        # $URL = "ftp://ftp.emc.com/Downloads/ScaleIO/ScaleIO_VMware_SW_Download.zip"
                        $FileName = Split-Path -Leaf -Path $Url
                        if (!(test-path  $Sourcedir\$FileName) -or $forcedownload.IsPresent)
                        {
                                    
                        $ok = Get-labyesnoabort -title "Could not find $Filename, we need to dowload from www.emc.com" -message "Should we Download $FileName from ww.emc.com ?" 
                        switch ($ok)
                            {

                            "0"
                                {
                                Write-Verbose "$FileName not found, trying Download"
                                Get-LABHttpFile -SourceURL $URL -TarGetFile $Sourcedir\$FileName -verbose
                                $Downloadok = $true
                                }
                             "1"
                                {
                                break
                                }   
                             "2"
                                {
                                Write-Verbose "User requested Abort"
                                exit
                                }
                            }
                        
                        }

                        if ((Test-Path "$Sourcedir\$FileName") -and (!($noextract.ispresent)))
                            {
                            Expand-LABZip -zipfilename "$Sourcedir\$FileName" -destination "$Sourcedir\ScaleIO\$ScaleIO_Path"
                            }
                        else
                            {
                            if (!$noextract.IsPresent)
                                {
                                exit
                                }
                            }
                        }
            #>


        }
        else
        {
        $OVAPath = $OVAPath.FullName
        }
        else

        } ###
  
        $OVAPath = Get-ChildItem -Path $OVAPath -Recurse -Filter "SCALEIOVM_1*.ova"  | Sort-Object -Descending
        $OVAPath
        $OVAPath = $OVApath[0]

        Write-Warning "Creating ScaleIO Master for $($ovaPath.Basename), may take a while"
        & $global:vmwarepath\OVFTool\ovftool.exe --lax --skipManifestCheck --name=$($ovaPath.Basename) $ovaPath.FullName $PSScriptRoot  #
        $MasterVMX = get-vmx -path ".\$($ovaPath.Basename)"
        if (!$MasterVMX.Template) 
            {
            write-verbose "Templating Master VMX"
            $MasterVMX | Set-VMXTemplate
            }
        }

     default
        {
        if (!(Test-Path $SCALEIOMaster))
            {
            Write-Warning "!!!!! No ScaleIO Master found
            please run .\install-scaleiosvm.ps1 -import to download / create Master
            "
            exit
            }
        $Mastervmxlist = get-vmx $SCALEIOMaster | Sort-Object -Descending
        $MasterVMX = $Mastervmxlist[0]   
        $Nodeprefix = "ScaleIONode"
        If ($configure.IsPresent -and $Nodes -lt 3)
            {
            Write-Warning "Configure Present, setting nodes to 3"
            $Nodes = 3
            }
        If ($singlemdm.IsPresent)
            {
            Write-Warning "Single MDM installations with MemoryTweaking  are only for Test Deployments and Memory Contraints/Manager Laptops :-)"
            $mdm_ip="$mdm_ipa"
            }
        else
            {
            $mdm_ip="$mdm_ipa,$mdm_ipb"
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
    Write-Host -ForegroundColor Magenta "Starting Avalanche install For Scaleio Nodes..."
    Measure-Command -Expression {
    foreach ($Node in $Startnode..(($Startnode-1)+$Nodes))
        {
        write-host -ForegroundColor Magenta " ==>Checking presence of $Nodeprefix$node"

        if (!(get-vmx $Nodeprefix$node))
            {   
            write-verbose "Creating $Nodeprefix$node"

            $NodeClone = $MasterVMX | Get-VMXSnapshot | where Snapshot -Match "Base" | New-VMXLinkedClone -CloneName $Nodeprefix$Node 
            If ($Node -eq 1){$Primary = $NodeClone}
            $Config = Get-VMXConfig -config $NodeClone.config
            Write-Verbose "Tweaking Config"
            $Config = $config | ForEach-Object { $_ -replace "lsilogic" , "pvscsi" }
            $Config | set-Content -Path $NodeClone.Config
            Write-Verbose "Creating Disks"
            foreach ($LUN in (1..$Disks))
                {
                $Diskname =  "SCSI$SCSI"+"_LUN$LUN.vmdk"
                Write-Verbose "Building new Disk $Diskname"
                $Newdisk = New-VMXScsiDisk -NewDiskSize $Disksize -NewDiskname $Diskname -VMXName $NodeClone.VMXname -Path $NodeClone.Path 
                Write-Verbose "adding Disk $Diskname to $($NodeClone.VMXname)"
                $AddDisk = $NodeClone | Add-VMXScsiDisk -Diskname $Newdisk.Diskname -LUN $LUN -Controller $SCSI 
                }
            write-verbose "Setting NIC0 to HostOnly"
            Set-VMXNetworkAdapter -Adapter 0 -ConnectionType hostonly -AdapterType vmxnet3 -config $NodeClone.Config | out-null
            if ($vmnet)
                {
                Write-Verbose "Configuring NIC 0 for $vmnet"
                Set-VMXNetworkAdapter -Adapter 0 -ConnectionType custom -AdapterType vmxnet3 -config $NodeClone.Config | out-null
                Set-VMXVnet -Adapter 0 -vnet $vmnet -config $NodeClone.Config | out-null
                Write-Verbose "Disconnecting Nic1 and Nic2"
                Disconnect-VMXNetworkAdapter -Adapter 1 -config $NodeClone.Config | out-null
                Disconnect-VMXNetworkAdapter -Adapter 2 -config $NodeClone.Config | out-null
                }
            $Displayname = $NodeClone | Set-VMXDisplayName -DisplayName "$($NodeClone.CloneName)@$BuildDomain"
                $MainMem = $NodeClone | Set-VMXMainMemory -usefile:$false

            $Annotation = $NodeClone | Set-VMXAnnotation -Line1 "rootuser:$rootuser" -Line2 "rootpasswd:$rootpassword" -Line3 "mdmuser:admin" -Line4 "mdmpassword:$MDMPassword" -Line5 "labbuildr by @sddc_guy" -builddate
 
            $Scenario = $NodeClone |Set-VMXscenario -config $NodeClone.Config -Scenarioname Scaleio -Scenario 6
            $ActivationPrefrence = $NodeClone |Set-VMXActivationPreference -config $NodeClone.Config -activationpreference $Node
            if ($singlemdm.IsPresent -and $Node -ne 1)
                {
                write-host "Tweaking memory for $Nodeprefix$Node"
                $memorytweak = $NodeClone | Set-VMXmemory -MemoryMB 1536
                } 
            Write-Host -ForegroundColor Magenta " ==>Starting ScaleIONode$Node"
            # Set-VMXVnet -Adapter 0 -vnet vmnet2
            start-vmx -Path $NodeClone.Path -VMXName $NodeClone.CloneName | out-null
            # $NodeClone | Set-VMXSharedFolderState -enabled
            }
        else
            {
            Write-Warning "Node $Nodeprefix$node already exists"
                if ($configure.IsPresent)
                    {
                    Write-Warning "Please Delete VM´s First, use 
                    'get-vmx $Nodeprefix$Node | remove-vmx'
to remove the Machine or
                    'get-vmx $Nodeprefix | remove-vmx' 
to remove all Nodes"
                    exit
                    }


            }

}
$Logfile = "/tmp/install_sio.log"
write-host -ForegroundColor Magenta "Configuring Nodes, this may take a while
logging to $Logfile
"

foreach ($Node in $Startnode..(($Startnode-1)+$Nodes))
        {
        write-host -ForegroundColor Magenta " ==>waiting for Node $Nodeprefix$node"
        $ip="$subnet.19$Node"
        $NodeClone = get-vmx $Nodeprefix$node
        do {
            $ToolState = Get-VMXToolsState -config $NodeClone.config
            Write-Verbose "VMware tools are in $($ToolState.State) state"
            sleep 5
            }
        until ($ToolState.state -match "running")
        If (!$DefaultGateway) {$DefaultGateway = $Ip}
        write-host -ForegroundColor Magenta " ==>Configuring $Nodeprefix$node with $ip"
        $NodeClone | Set-VMXLinuxNetwork -ipaddress $ip -network "$subnet.0" -netmask "255.255.255.0" -gateway $DefaultGateway -device eth0 -Peerdns -DNS1 "$subnet.10" -DNSDOMAIN "$BuildDomain.local" -Hostname "$Nodeprefix$Node" -suse -rootuser $rootuser -rootpassword $rootpassword 
        $NodeClone | Invoke-VMXBash -Scriptblock "rpm --import /root/install/RPM-GPG-KEY-ScaleIO" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
        if (!($PsCmdlet.ParameterSetName -eq "sdsonly"))
            {
            if (($Node -in 1..2 -and (!$singlemdm)) -or ($Node -eq 1))
                {
                Write-Host -ForegroundColor Magenta " ==>trying MDM Install"
                $NodeClone | Invoke-VMXBash -Scriptblock "rpm -Uhv /root/install/EMC-ScaleIO-mdm*.rpm" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
                }
            
            if ($Node -eq 3)
                {
                Write-Host -ForegroundColor Magenta " ==>trying Gateway Install"
                $NodeClone | Invoke-VMXBash -Scriptblock "rpm -Uhv /root/install/jre-*-linux-x64.rpm" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
                $NodeClone | Invoke-VMXBash -Scriptblock "export SIO_GW_KEYTOOL=/usr/java/default/bin/;export GATEWAY_ADMIN_PASSWORD='Password123!';rpm -Uhv --nodeps  /root/install/EMC-ScaleIO-gateway*.rpm" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
                if (!$singlemdm)
                    {
                    Write-Host -ForegroundColor Magenta " ==>trying TB Install"
                    $NodeClone | Invoke-VMXBash -Scriptblock "rpm -Uhv /root/install/EMC-ScaleIO-tb*.rpm" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
                    Write-Host -ForegroundColor Magenta " ==>adding MDM to Gateway Server Config File"
                    $sed = "sed -i 's\mdm.ip.addresses=.*\mdm.ip.addresses=$mdm_ipa;$mdm_ipb\' /opt/emc/scaleio/gateway/webapps/ROOT/WEB-INF/classes/gatewayUser.properties" 
                    }
                else
                    {
                    Write-Host -ForegroundColor Magenta " ==>adding MDM's to Gateway Server Config File"
                    $sed = "sed -i 's\mdm.ip.addresses=.*\mdm.ip.addresses=$mdm_ipa;$mdm_ipa\' /opt/emc/scaleio/gateway/webapps/ROOT/WEB-INF/classes/gatewayUser.properties" 
                    }
                Write-Verbose $sed
                $NodeClone | Invoke-VMXBash -Scriptblock $sed -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
                $NodeClone | Invoke-VMXBash -Scriptblock "/etc/init.d/scaleio-gateway restart" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
                }
            Write-Host -ForegroundColor Magenta " ==>trying LIA Install"
            $NodeClone | Invoke-VMXBash -Scriptblock "rpm -Uhv /root/install/EMC-ScaleIO-lia*.rpm" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
            }
        if ($sds.IsPresent)
            {
            Write-Host -ForegroundColor Magenta " ==>trying SDS Install"
            $NodeClone | Invoke-VMXBash -Scriptblock "rpm -Uhv /root/install/EMC-ScaleIO-sds*.rpm" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
            }
        if ($sdc.IsPresent)
            {
            Write-Host -ForegroundColor Magenta " ==>trying SDC Install"
            $NodeClone | Invoke-VMXBash -Scriptblock "export MDM_IP=$mdm_ip;rpm -Uhv /root/install/EMC-ScaleIO-sdc*.rpm" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
            }
    }
if ($configure.IsPresent)
    {
    Write-Host -ForegroundColor Magenta "Configuring ScaleIO"
    $Logfile = "/tmp/configure_sio.log"
    write-host "Configuring ScaleIO"
    $mdmconnect = "scli --login --username admin --password $MDMPassword --mdm_ip $mdm_ip"

    if ($Primary)
        {
        Write-Host -ForegroundColor Magenta "We are now creating the ScaleIO Grid"
        Write-Host -ForegroundColor Magenta " ==>adding Primary MDM $mdm_ipa"
        $sclicmd =  "scli --add_primary_mdm --primary_mdm_ip $mdm_ipa --mdm_management_ip $mdm_ip --accept_license"
        Write-Verbose $sclicmd
        $Primary | Invoke-VMXBash -Scriptblock $sclicmd -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile

        Write-Host -ForegroundColor Magenta " ==>Setting password"
        $sclicmd =  "scli --login --username admin --password admin --mdm_ip $mdm_ipa;scli --set_password --old_password admin --new_password $MDMPassword  --mdm_ip $mdm_ipa"
        Write-Verbose $sclicmd
        $Primary | Invoke-VMXBash -Scriptblock $sclicmd -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile

        if (!$singlemdm.IsPresent)
            {
            Write-Host -ForegroundColor Magenta " ==>adding secondary MDM $mdm_ipb"
            $sclicmd = "$mdmconnect;scli --add_secondary_mdm --mdm_ip $mdm_ipa --secondary_mdm_ip $mdm_ipb --mdm_ip $mdm_ipa"
            Write-Verbose $sclicmd
            $Primary | Invoke-VMXBash -Scriptblock $sclicmd -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile 
            
            Write-Host -ForegroundColor Magenta " ==>adding tiebreaker $tb_ip"
            $sclicmd = "$mdmconnect;scli --add_tb --tb_ip $tb_ip --mdm_ip $mdm_ipa"
            Write-Verbose $sclicmd
            $Primary | Invoke-VMXBash -Scriptblock $sclicmd -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
            
            Write-Host -ForegroundColor Magenta " ==>switching to cluster mode"
            $sclicmd = "$mdmconnect;scli --switch_to_cluster_mode --mdm_ip $mdm_ipa"
            Write-Verbose $sclicmd
            $Primary | Invoke-VMXBash -Scriptblock $sclicmd -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
            }
        else
            {
            $mdm_ipb = $mdm_ipa
            }
        Write-Host -ForegroundColor Magenta "Storing locally"

        Set-LABSIOConfig -mdm_ipa $mdm_ipa -mdm_ipb $mdm_ipb -gateway_ip $tb_ip -system_name $SystemName -pool_name $StoragePoolName -pd_name $ProtectionDomainName 
        
        
        Write-Host -ForegroundColor Magenta " ==>adding protection domain $ProtectionDomainName"
        $sclicmd = "scli --add_protection_domain --protection_domain_name $ProtectionDomainName --mdm_ip $mdm_ip"
        $Primary | Invoke-VMXBash -Scriptblock "$mdmconnect;$sclicmd" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
        
        Write-Host -ForegroundColor Magenta " ==>adding storagepool $StoragePoolName"
        $sclicmd = "scli --add_storage_pool --storage_pool_name $StoragePoolName --protection_domain_name $ProtectionDomainName --mdm_ip $mdm_ip"
        Write-Verbose $sclicmd
        $Primary | Invoke-VMXBash -Scriptblock "$mdmconnect;$sclicmd" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile

        Write-Host -ForegroundColor Magenta " ==>adding renaming system to $SystemName"
        $sclicmd = "scli --rename_system --new_name $SystemName --mdm_ip $mdm_ip"
        Write-Verbose $sclicmd
        $Primary | Invoke-VMXBash -Scriptblock "$mdmconnect;$sclicmd" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
        }#end Primary
    foreach ($Node in $Startnode..(($Startnode-1)+$Nodes))
            {
            Write-Host -ForegroundColor Magenta " ==>adding sds $subnet.19$Node with /dev/sdb"
            $sclicmd = "scli --add_sds --sds_ip $subnet.19$Node --device_path /dev/sdb --device_name /dev/sdb  --sds_name ScaleIONode$Node --protection_domain_name $ProtectionDomainName --storage_pool_name $StoragePoolName --no_test --mdm_ip $mdm_ip"
            Write-Verbose $sclicmd
            $Primary | Invoke-VMXBash -Scriptblock "$mdmconnect;$sclicmd" -Guestuser $rootuser -Guestpassword $rootpassword -logfile $Logfile
            }
    write-host "Connect with ScaleIO UI to $mdm_ipa admin/Password123!"
    }

write-host "Login to the VM´s with root/admin"

}#end measuer
} #end default
}#end switch 



