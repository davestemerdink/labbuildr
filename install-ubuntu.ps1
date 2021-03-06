﻿<#
.Synopsis
   .\install-ubuntu.ps1 
.DESCRIPTION
  install-scaleio is  the a vmxtoolkit solutionpack for configuring and deploying scaleio svm´s
      
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
   https://community.emc.com/blogs/bottk/
.EXAMPLE
.\install-Ubuntu.ps1
This will install 3 Ubuntu Nodes Ubuntu1 -Ubuntu3 from the Default Ubuntu Master , in the Default 192.168.2.0 network, IP .221 - .223

#>
[CmdletBinding(DefaultParametersetName = "defaults",
    SupportsShouldProcess=$true,
    ConfirmImpact="Medium")]
Param(
[Parameter(ParameterSetName = "defaults", Mandatory = $true)]
[switch]$Defaults,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$False)]
[ValidateRange(1,3)]
[int32]$Disks = 1,
[Parameter(ParameterSetName = "install",Mandatory = $false)]
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[ValidateSet('16_4','15_4')]
[string]$ubuntu_ver = "16_4",
[Parameter(ParameterSetName = "install",Mandatory = $false)]
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[ValidateSet('cinnamon','none')]
[string]$Desktop = "none",
[Parameter(ParameterSetName = "install",Mandatory=$false)]
[ValidateScript({ Test-Path -Path $_ -ErrorAction SilentlyContinue })]
$Sourcedir = 'h:\sources',
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)]
[ValidateRange(1,9)]
[int32]$Nodes=1,
[Parameter(ParameterSetName = "install",Mandatory=$false)]
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[int32]$Startnode = 1,
[Parameter(ParameterSetName = "install",Mandatory=$false)]
[ValidateScript({$_ -match [IPAddress]$_ })]
[ipaddress]$subnet = "192.168.2.0",
[Parameter(ParameterSetName = "install",Mandatory=$False)]
[ValidateLength(1,15)][ValidatePattern("^[a-zA-Z0-9][a-zA-Z0-9-]{1,15}[a-zA-Z0-9]+$")]
[string]$BuildDomain = "labbuildr",
[Parameter(ParameterSetName = "install",Mandatory = $false)]
[ValidateSet('vmnet1', 'vmnet2','vmnet3')]
$vmnet = "vmnet2",
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[ValidateScript({ Test-Path -Path $_ })]
$Defaultsfile=".\defaults.xml",
[Parameter(ParameterSetName = "install",Mandatory = $false)]
[Parameter(ParameterSetName = "defaults", Mandatory = $false)][switch]$forcedownload,
[int]$ip_startrange = 200
#[Parameter(ParameterSetName = "install",Mandatory = $false)]
#[Parameter(ParameterSetName = "defaults", Mandatory = $false)][switch]$SIOGateway
)
#requires -version 3.0
#requires -module vmxtoolkit
If ($ConfirmPreference -match "none")
    {$Confirm = $false}
else
    {$Confirm = $true}
$Builddir = $PSScriptRoot
$Scriptdir = Join-Path $Builddir "Scripts"
If ($Defaults.IsPresent)
    {
    $labdefaults = Get-labDefaults
    $vmnet = $labdefaults.vmnet
    $subnet = $labdefaults.MySubnet
    $BuildDomain = $labdefaults.BuildDomain
    try
        {
        $Sourcedir = $labdefaults.Sourcedir
        }
    catch [System.Management.Automation.ValidationMetadataException]
        {
        Write-Warning "Could not test Sourcedir Found from Defaults, USB stick connected ?"
        Break
        }
    catch [System.Management.Automation.ParameterBindingException]
        {
        Write-Warning "No valid Sourcedir Found from Defaults, USB stick connected ?"
        Break
        }
    try
        {
        $Masterpath = $LabDefaults.Masterpath
        }
    catch
        {
        # Write-Host -ForegroundColor Gray " ==> No Masterpath specified, trying default"
        $Masterpath = $Builddir
        }
     $Hostkey = $labdefaults.HostKey
     $Gateway = $labdefaults.Gateway
     $DefaultGateway = $labdefaults.Defaultgateway
     $DNS1 = $labdefaults.DNS1
     $DNS2 = $labdefaults.DNS2
    }
if ($LabDefaults.custom_domainsuffix)
	{
	$custom_domainsuffix = $LabDefaults.custom_domainsuffix
	}
else
	{
	$custom_domainsuffix = "local"
	}

if (!$DNS2)
    {
    $DNS2 = $DNS1
    }
if (!$Masterpath) {$Masterpath = $Builddir}

$ip_startrange = $ip_startrange+$Startnode

switch ($ubuntu_ver)
    {
    "16_4"
        {
        $netdev = "ens160"
        }
    default
        {
        $netdev= "eth0"
        }
    }
[System.Version]$subnet = $Subnet.ToString()
$Subnet = $Subnet.major.ToString() + "." + $Subnet.Minor + "." + $Subnet.Build
$rootuser = "root"
$Guestpassword = "Password123!"
[uint64]$Disksize = 100GB
$scsi = 0
$Nodeprefix = "Ubuntu"
$Required_Master = "Ubuntu$ubuntu_ver"

#$mastervmx = test-labmaster -Master $Required_Master -MasterPath $MasterPath -Confirm:$Confirm

###### checking master Present
try
    {
    $MasterVMX = test-labmaster -Masterpath $MasterPath -Master $Required_Master -Confirm:$Confirm -erroraction stop
    }
catch
    {
    Write-Warning "Required Master $Required_Master not found
    please download and extraxt $Required_Master to .\$Required_Master
    see: 
    ------------------------------------------------
    get-help $($MyInvocation.MyCommand.Name) -online
    ------------------------------------------------"
    exit
    }
####
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
$StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
####Build Machines#
$machinesBuilt = @()
foreach ($Node in $Startnode..(($Startnode-1)+$Nodes))
    {
        Write-Host -ForegroundColor White "Checking for $Nodeprefix$node"
        If (!(get-vmx $Nodeprefix$node -WarningAction SilentlyContinue))
        {
        Write-Host -ForegroundColor Magenta "==>Creating $Nodeprefix$node"
        try
            {
            $NodeClone = $MasterVMX | Get-VMXSnapshot | where Snapshot -Match "Base" | New-VMXLinkedClone -CloneName $Nodeprefix$Node # -clonepath $Builddir
            }
        catch
            {
            Write-Warning "Error creating VM"
            return
            }
        If ($Node -eq 1){$Primary = $NodeClone}
        $Config = Get-VMXConfig -config $NodeClone.config
        Write-Host -ForegroundColor Magenta " ==> Tweaking Config"
        Write-Host -ForegroundColor Magenta " ==> Creating Disks"
        foreach ($LUN in (1..$Disks))
            {
            $Diskname =  "SCSI$SCSI"+"_LUN$LUN.vmdk"
            Write-Host -ForegroundColor Magenta " ==> Building new Disk $Diskname"
            $Newdisk = New-VMXScsiDisk -NewDiskSize $Disksize -NewDiskname $Diskname -Verbose -VMXName $NodeClone.VMXname -Path $NodeClone.Path 
            Write-Host -ForegroundColor Magenta " ==> Adding Disk $Diskname to $($NodeClone.VMXname)"
            $AddDisk = $NodeClone | Add-VMXScsiDisk -Diskname $Newdisk.Diskname -LUN $LUN -Controller $SCSI
            }
        Write-Host -ForegroundColor Magenta " ==> Setting NIC0 to HostOnly"
        $Netadapter = Set-VMXNetworkAdapter -Adapter 0 -ConnectionType hostonly -AdapterType vmxnet3 -config $NodeClone.Config
        if ($vmnet)
            {
            Write-Host -ForegroundColor Magenta " ==> Configuring NIC 0 for $vmnet"
            Set-VMXNetworkAdapter -Adapter 0 -ConnectionType custom -AdapterType vmxnet3 -config $NodeClone.Config -WarningAction SilentlyContinue | Out-Null
            Set-VMXVnet -Adapter 0 -vnet $vmnet -config $NodeClone.Config | Out-Null
            }

        $Displayname = $NodeClone | Set-VMXDisplayName -DisplayName "$($NodeClone.CloneName)@$BuildDomain"
        $MainMem = $NodeClone | Set-VMXMainMemory -usefile:$false
       <# if ($node -eq 3)
            {
            Write-Host -ForegroundColor Magenta " ==> Setting Gateway Memory to 3 GB"
            $NodeClone | Set-VMXmemory -MemoryMB 3072 | Out-Null
            }#>
        $Scenario = $NodeClone |Set-VMXscenario -config $NodeClone.Config -Scenarioname Ubuntu -Scenario 7
        $ActivationPrefrence = $NodeClone |Set-VMXActivationPreference -config $NodeClone.Config -activationpreference $Node
        Write-Host -ForegroundColor Magenta " ==> Starting $Nodeprefix$Node"
        start-vmx -Path $NodeClone.Path -VMXName $NodeClone.CloneName | Out-Null
        $machinesBuilt += $($NodeClone.cloneName).tolower()
        }
    else
        {
        write-Warning "Machine $Nodeprefix$node already Exists"
        }
    }
Write-Host -ForegroundColor White "Starting Node Configuration"

    
foreach ($Node in $machinesBuilt)
    {
        $ip="$subnet.$ip_startrange"
        $NodeClone = get-vmx $Node
        Write-Host -ForegroundColor Magenta " ==> Waiting for $node to boot"

        do {
            $ToolState = Get-VMXToolsState -config $NodeClone.config
            Write-Verbose "VMware tools are in $($ToolState.State) state"
            sleep 5
            }
        until ($ToolState.state -match "running")
        Write-Host -ForegroundColor Gray " ==> Setting Shared Folders"
        $NodeClone | Set-VMXSharedFolderState -enabled | Out-Null
        # $Nodeclone | Set-VMXSharedFolder -remove -Sharename Sources # | Out-Null
        Write-Host -ForegroundColor Gray " ==> Adding Shared Folders"        
        $NodeClone | Set-VMXSharedFolder -add -Sharename Sources -Folder $Sourcedir  | Out-Null
        
        If ($ubuntu_ver -lt "16")
            {
            $Scriptblock = "systemctl disable iptables.service"
            Write-Verbose $Scriptblock
            $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null
    
            ##### selectiung fastest apt mirror
            ## sudo netselect -v -s10 -t20 `wget -q -O- https://launchpad.net/ubuntu/+archivemirrors | grep 
        
            <#
            $Scriptblock = "systemctl stop iptables.service"
            Write-Verbose $Scriptblock
            $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword
            ssh-keygen -f /etc/ssh/ssh_host_rsa_key -N '' -t rsa
            ssh-keygen -f /etc/ssh/ssh_host_dsa_key -N '' -t dsa
            #>

            }

        Write-Host -ForegroundColor Gray " ==> Configuring SSH"
        $Scriptblock = "sed -i '/PermitRootLogin without-password/ c\PermitRootLogin yes' /etc/ssh/sshd_config"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword  | Out-Null
        
        $Scriptblock = "/usr/bin/ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa -force"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword  | Out-Null
    
        $Scriptblock = "/usr/bin/ssh-keygen -f /etc/ssh/ssh_host_rsa_key -N '' -t rsa"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword  | Out-Null

        $Scriptblock = "/usr/bin/ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword  | Out-Null

        if ($Hostkey)
            {
            $Scriptblock = "echo '$Hostkey' >> /root/.ssh/authorized_keys"
            Write-Verbose $Scriptblock
            $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null
            }

        $Scriptblock = "cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys;chmod 0600 /root/.ssh/authorized_keys"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

        Write-Host -ForegroundColor Magenta "==> Configuring Guest network for $netdev"

        $Scriptblock = "echo 'auto lo' > /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null


        $Scriptblock = "echo 'iface lo inet loopback' >> /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null


        $Scriptblock = "echo 'auto $netdev' >> /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

        $Scriptblock = "echo 'iface $netdev inet static' >> /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

        Write-Host -ForegroundColor Gray " ==> Setting IP $ip for $netdev"
        $Scriptblock = "echo 'address $ip' >> /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

        Write-Host -ForegroundColor Gray " ==> Setting Gateway $DefaultGateway"
        $Scriptblock = "echo 'gateway $DefaultGateway' >> /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

        $Scriptblock = "echo 'netmask 255.255.255.0' >> /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

        $Scriptblock = "echo 'network $subnet.0' >> /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

        $Scriptblock = "echo 'broadcast $subnet.255' >> /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null
        
        Write-Host -ForegroundColor Gray " ==> Setting DNS $DNS1 $DNS2"
        $Scriptblock = "echo 'dns-nameservers $DNS1 $DNS2' >> /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

        $Scriptblock = "echo 'dns-search $BuildDomain.$Custom_DomainSuffix' >> /etc/network/interfaces"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null
        
        Write-Host -ForegroundColor Gray " ==> setting hostname $Node"
        $Scriptblock = "echo '127.0.0.1       localhost' > /etc/hosts; echo '$ip $Node $Node.$BuildDomain.$Custom_DomainSuffix' >> /etc/hosts; hostname $Node"
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

        Write-Host -ForegroundColor Magenta "==> Restarting Guest Network"
        $Scriptblock = "/etc/init.d/networking restart"
        Write-Verbose $Scriptblock
        $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

        Write-Host -ForegroundColor Cyan " ==>Testing default Route, make sure that Gateway is reachable ( eg. install and start OpenWRT )
        if failures occur, you might want to open a 2nd labbuildr windows and run start-vmx OpenWRT "
        $Scriptblock = "DEFAULT_ROUTE=`$(ip route show default | awk '/default/ {print `$3}');ping -c 1 `$DEFAULT_ROUTE"
        Write-Verbose $Scriptblock
        $Bashresult = $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword     
        ###
        switch ($Desktop)
            {
                'cinnamon'
                {
                Write-Host -ForegroundColor Magenta " ==> downloading and configuring $Desktop as Desktop, this may take a while"
                $Scriptblock = "apt-get update >> /tmp/cinamon.log;apt-get install -y cinnamon-desktop-environment xinit >> /tmp/cinamon.log"
                Write-Verbose $Scriptblock
                $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null

                Write-host -ForegroundColor White " for full screen resolution, run /usr/bin/vmware-config-tools.pl -d"

                Write-Host -ForegroundColor Magenta " ==> starting login manager"
                $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null
                $Scriptblock = "systemctl enable lightdm >> /tmp/lightdm.log;systemctl start lightdm >> /tmp/lightdm.log"
                Write-Verbose $Scriptblock
                $NodeClone | Invoke-VMXBash -Scriptblock $Scriptblock -Guestuser $Rootuser -Guestpassword $Guestpassword | Out-Null
                }
            default
                {
                }
            }

        ####

        $ip_startrange++
    
    
    }
$StopWatch.Stop()
Write-host -ForegroundColor White "Deployment took $($StopWatch.Elapsed.ToString())"
Write-Host -ForegroundColor Yellow "Login to the VM´s with root/Password123!"
    






