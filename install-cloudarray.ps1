﻿<#
.Synopsis
   .\install-scaleio.ps1 
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
   https://community.emc.com/blogs/bottk/2015/02/05/labbuildrgoes-emc-cloudarray
.EXAMPLE
.\install-cloudarray.ps1 -ovf D:\Sources\CloudArray-ESXi5-5.1.0.6695\CloudArray-ESXi5-5.1.0.6695.ovf 
This will convert Cloudarray ESX Template 
.EXAMPLE
.\install-cloudarray.ps1 -MasterPath .\CloudArray-ESXi5-5.1.0.6695 -Defaults  
This will Install default Cloud Array
#>
[CmdletBinding()]
Param(
### import parameters
[Parameter(ParameterSetName = "import",Mandatory=$true)][String]
[ValidateScript({ Test-Path -Path $_ -Filter *.ov* -PathType Leaf})]$ovf,
[Parameter(ParameterSetName = "import",Mandatory=$false)][String]$mastername,
### install param
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)][ValidateRange(1,3)][int32]$Cachevols = 1,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)][ValidateSet(36GB,72GB,146GB)][uint64]$Cachevolsize = 146GB,

[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)][ValidateScript({ Test-Path -Path $_ -ErrorAction SilentlyContinue })]$MasterPath = ".\CloudArraymaster",



[Parameter(ParameterSetName = "defaults", Mandatory = $true)][switch]$Defaults,
[Parameter(ParameterSetName = "defaults", Mandatory = $false)][ValidateScript({ Test-Path -Path $_ })]$Defaultsfile=".\defaults.xml",


[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)][int32]$Nodes=1,

[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)][int32]$Startnode = 1,

[Parameter(ParameterSetName = "defaults", Mandatory = $false)]
[Parameter(ParameterSetName = "install",Mandatory=$false)][switch]$dedupe,


[Parameter(ParameterSetName = "install", Mandatory = $true)][ValidateSet('vmnet2','vmnet3','vmnet4','vmnet5','vmnet6','vmnet7','vmnet9','vmnet10','vmnet11','vmnet12','vmnet13','vmnet14','vmnet15','vmnet16','vmnet17','vmnet18','vmnet19')]$VMnet = "vmnet2"


)
#requires -version 3.0
#requires -module vmxtoolkit 
switch ($PsCmdlet.ParameterSetName)
{
    "import"
        {
        if (!(($Mymaster = Get-Item $ovf).Extension -match "ovf" -or "ova"))
            {
            write-warning "no OVF Template found"
            exit
            }
        
        # if (!($mastername)) {$mastername = (Split-Path -Leaf $ovf).Replace(".ovf","")}
        # $Mymaster = Get-Item $ovf
        $Mastername = $Mymaster.Basename
        & $global:vmwarepath\OVFTool\ovftool.exe --lax --skipManifestCheck  --name=$mastername $ovf $PSScriptRoot #
        switch ($LASTEXITCODE)
            {
                1
                    {
                    Write-Warning "There was an error creating the Template"
                    exit
                    }
                default
                    {
                    Write-Host "Templyte creation succeded with $LASTEXITCODE"
                    }
                }
        $Content = Get-Content $PSScriptRoot\$mastername\$mastername.vmx
        $Content = $Content-notmatch 'snapshot.maxSnapshots'
        $Content | Set-Content $PSScriptRoot\$mastername\$mastername.vmx
        write-host -ForegroundColor Magenta "Now run .\install-cloudarray.ps1 -MasterPath .\$mastername -Defaults " 
        }
default
    {


            
            
    If ($Defaults.IsPresent)
            {
            $labdefaults = Get-labDefaults
            $vmnet = $labdefaults.vmnet
            $subnet = $labdefaults.MySubnet
            $BuildDomain = $labdefaults.BuildDomain
            $Sourcedir = $labdefaults.Sourcedir
            $Gateway = $labdefaults.Gateway
            $DefaultGateway = $labdefaults.Defaultgateway
            $DNS1 = $labdefaults.DNS1
            $configure = $true
            }



    $Nodeprefix = "Cloudarray"
    If (!($MasterVMX = get-vmx -path $MasterPath))
      {
       Write-Error "No Valid Master Found"
      break
     }
    

    $Basesnap = $MasterVMX | Get-VMXSnapshot | where Snapshot -Match "Base"
    if (!$Basesnap) 
        {

        Write-Host -ForegroundColor Magenta " ==>Tweaking VMX File"
        $Config = Get-VMXConfig -config $MasterVMX.Config
        $Config = $Config -notmatch 'snapshot.maxSnapshots'
        $Config | set-Content -Path $MasterVMX.Config


        Write-Host -ForegroundColor Magenta " ==>Base snap does not exist, creating now"
        $Basesnap = $MasterVMX | New-VMXSnapshot -SnapshotName BASE
        if (!$MasterVMX.Template) 
            {
            Write-Host -ForegroundColor Magenta " ==>Templating Master VMX"
            $template = $MasterVMX | Set-VMXTemplate
            }

        } #end basesnap
####Build Machines#

    foreach ($Node in $Startnode..(($Startnode-1)+$Nodes))
        {
        Write-Host -ForegroundColor Magenta " ==>Checking VM $Nodeprefix$node already Exists"
        If (!(get-vmx $Nodeprefix$node))
            {
            Write-Host -ForegroundColor Magenta " ==>Creating clone $Nodeprefix$node"
            $NodeClone = $MasterVMX | Get-VMXSnapshot | where Snapshot -Match "Base" | New-VMXClone -CloneName $Nodeprefix$node 
            Write-Host -ForegroundColor Magenta " ==>Creating Disks"
            $SCSI = 0
            foreach ($LUN in (2..(1+$Cachevols)))
                {
                $Diskname =  "SCSI$SCSI"+"_LUN$LUN"+"_$Cachevolsize.vmdk"
                Write-Host -ForegroundColor Magenta " ==>Building new Disk $Diskname"
                $Newdisk = New-VMXScsiDisk -NewDiskSize $Cachevolsize -NewDiskname $Diskname -Verbose -VMXName $NodeClone.VMXname -Path $NodeClone.Path 
                Write-Host -ForegroundColor Magenta " ==>Adding Disk $Diskname to $($NodeClone.VMXname)"
                $AddDisk = $NodeClone | Add-VMXScsiDisk -Diskname $Newdisk.Diskname -LUN $LUN -Controller $SCSI
                }
            Write-Host -ForegroundColor Magenta " ==>Setting ext-0"
            Set-VMXNetworkAdapter -Adapter 0 -ConnectionType custom -AdapterType vmxnet3 -config $NodeClone.Config  | Out-Null
            Set-VMXVnet -Adapter 0 -vnet $vmnet -config $NodeClone.Config  | Out-Null
            $Scenario = Set-VMXscenario -config $NodeClone.Config -Scenarioname $Nodeprefix -Scenario 6  | Out-Null
            $ActivationPrefrence = Set-VMXActivationPreference -config $NodeClone.Config -activationpreference $Node  | Out-Null
            # Set-VMXVnet -Adapter 0 -vnet vmnet2
            Write-Host -ForegroundColor Magenta " ==>Setting Display Name $($NodeClone.CloneName)@$Builddomain"
            Set-VMXDisplayName -config $NodeClone.Config -Displayname "$($NodeClone.CloneName)@$Builddomain"  | Out-Null
            if ($dedupe)
                {
                Write-Host -ForegroundColor Magenta " ==>Aligning Memory and cache for DeDupe"
                $NodeClone | Set-VMXmemory -MemoryMB 9216 | Out-Null
                $NodeClone | Set-VMXprocessor -Processorcount 4 | Out-Null
                } 
            Write-Host -ForegroundColor Magenta " ==>Starting $Nodeprefix$node"
            start-vmx -Path $NodeClone.config -VMXName $NodeClone.CloneName  | Out-Null
            } # end check vm
        else
            {
            Write-Warning "VM $Nodeprefix$node already exists"
            }
        }#end foreach
    write-Warning "Login to Cloudarray with admin / password"
    } # end default


}# end switch




