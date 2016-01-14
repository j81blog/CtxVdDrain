<#
.NAME
	CtxVdDrain
.SYNOPSIS  
	Drains a given set of virtual desktops and puts them in maintenance mode and issues a shutdown.
.DESCRIPTION  
	Drains a given set of virtual desktops and puts them in maintenance mode and issues a shutdown.
.NOTES  
	File Name  : CtxVdDrain.ps1
	Author     : John Billekens - john@j81.nl
	Requires   : Citrix Delivery Controller 7.x
	Version    : 20160114.2124
.SYNTAX
	.\CtxVdDrain.ps1
#>

[cmdletbinding()]
Param(
)

$Host.UI.RawUI.WindowTitle = "CtxVdDrain"
$newsize = $Host.UI.RawUI.buffersize
$newsize.height = 3000
$newsize.width = 120
$Host.UI.RawUI.buffersize = $newsize
$newsize = $Host.UI.RawUI.WindowSize
$newsize.height = 50
$newsize.width = 120
$Host.UI.RawUI.WindowSize = $newsize
clear-host

IF (-not (Get-Module -Name Citrix.*)) {
	Import-Module Citrix.*
}
IF (-not (Get-PSSnapin -Name Citrix.* -ErrorAction SilentlyContinue)) {
	Add-PSSnapin Citrix.*
}

function PickList(){
	[cmdletbinding()]
	param(
		[string[]]$PickList,
		[String]$PickListPromptText,
		[Boolean]$PickListRequired
	)
	$iCounter=0
	$sPickListSelection=$null
	$sPickListItem=$null
	foreach($sPickListItem in $PickList){
		$aPickList += (,($iCounter,$sPickListItem))
		$iCounter++
	}
	Write-Host "`n$PickListPromptText`n"
	$sPickListItem=$null
	foreach ($sPickListItem in $aPickList){
		Write-Host $("`t"+$sPickListItem[0]+".`t"+$sPickListItem[1])
	}
	if ($PickListRequired) {
		while (!$Answer){
			Write-Host "`nRequired " -Fore Red -NoNewline
			$sPickListSelection = Read-Host "Enter Option Number"
			$Answer = $null
			try {
				if ([int]$sPickListSelection -is [int]) {
					if (([int]$sPickListSelection -ge 0) -and ([int]$sPickListSelection -lt $iCounter)) {
						$Answer = 1
					}
				}
			} catch {
				$Answer = $null
			}
		}
		return $aPickList[$sPickListSelection][1]
	} else {
		Write-Host "`nNot Required " -Fore White -NoNewline
		$sPickListSelection = Read-Host "Enter Option Number: "
		if($sPickListSelection){
			return $aPickList[$sPickListSelection][1]
		}
	}
}

Function Start-Countdown {
	Param(
		[Parameter(Mandatory=$false)][Int32]$Seconds = 10,
		[Parameter(Mandatory=$false)][string]$Message = ("Pausing for " + [string]$Seconds + " seconds...")
	)
	ForEach ($Count in (1..$Seconds)) {
		Write-Progress -Id 1 -Activity $Message -Status "Waiting for $Seconds seconds, $($Seconds - $Count) left" -PercentComplete (($Count / $Seconds) * 100)
		Start-Sleep -Seconds 1
	}
	Write-Progress -Id 1 -Activity $Message -Status "Completed" -PercentComplete 100 -Completed
}

$aMembers = @()
[int]$iProgressTotal = 0
Clear-Host
$sBrokerCatalogs = (Get-BrokerCatalog).Name
$sMenuChoiceText = "Please select a Machine Catalog"
$sBrokerCatalog = PickList $sBrokerCatalogs $sMenuChoiceText $true
If ((Get-BrokerCatalog -Name $sBrokerCatalog -ErrorAction SilentlyContinue).Count -ne 0) {
	Clear-Host
	Do {
		Clear-Host
		$aMembers = Get-BrokerMachine -CatalogName $sBrokerCatalog -MaxRecordCount 4000 | Where-Object {($_.InMaintenanceMode -ne "True") -and ($_.PowerState -eq "Off")}
		$aMembers | Set-BrokerMachine -InMaintenanceMode $True | Out-Null
		$aMembers = Get-BrokerMachine -CatalogName $sBrokerCatalog -MaxRecordCount 4000 | Where-Object {($_.RegistrationState -eq "Unregistered") -and ($_.PowerState -ne "Off")}
		$aMembers | Set-BrokerMachine -InMaintenanceMode $True | Out-Null
		$aMembers | New-BrokerHostingPowerAction -Action "Shutdown" | Out-Null
		$aMembers = Get-BrokerMachine -CatalogName $sBrokerCatalog -MaxRecordCount 4000 | Where-Object {($_.InMaintenanceMode -eq "True") -and ($_.RegistrationState -eq "Registered") -and ($_.PowerState -ne "Off") -and ($_.SessionCount -eq "0")}
		$aMembers | New-BrokerHostingPowerAction -Action "Shutdown" | Out-Null
		$aMembers = Get-BrokerMachine -CatalogName $sBrokerCatalog -MaxRecordCount 4000 | Where-Object {($_.InMaintenanceMode -ne "True") -and ($_.PowerState -ne "Off")}
		[int]$iProgressTotal = $aMembers.Count
		if ($iProgressTotal -eq 0) {
			break
		} else {
			$aMemberActions = $aMembers | Where-Object {($_.SessionCount -eq "0") -and ($_.SessionsEstablished -eq "0") -and ($_.SessionsPending -eq "0")}
			$aMemberActions | Set-BrokerMachine -InMaintenanceMode $True | Out-Null
			$aMemberActions | New-BrokerHostingPowerAction -Action "Shutdown" | Out-Null
			$aMembers = Get-BrokerMachine -CatalogName $sBrokerCatalog -MaxRecordCount 4000 | Where-Object {($_.InMaintenanceMode -ne "True") -and ($_.PowerState -ne "Off")}
			[int]$iProgressTotal = $aMembers.Count
			if ($iProgressTotal -eq 0) {
				break
			}
			Write-Host ""
			Write-Host ""
			Write-Host ""
			Write-Host ""
			Write-Host ""
			Write-Host ""
			Write-Host ""
			Write-Host ""
			Write-Host -Foregroundcolor Yellow " Busy..."
			Write-Host ""
			Write-Host " "$aMemberActions.Count"vm's shutdown this round."
			Write-Host " "$iProgressTotal" vm's to go."
			Start-Countdown -Seconds 120
		}
	} Until ($iProgressTotal -eq 0)
	
	Clear-Host
	Write-Host ""
	Write-Host ""
	Write-Host ""
	Write-Host -Foregroundcolor Green "Done! No more machines in use."
	Write-Host ""
} else {
	Write-Host ""
	Write-Host ""
	Write-Host ""
	Write-Host -Foregroundcolor Red "The item picked does not excists or something went wrong!"
	Write-Host ""
}

