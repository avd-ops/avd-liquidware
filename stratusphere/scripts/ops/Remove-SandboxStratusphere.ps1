<#
.SYNOPSIS
  Deallocates or tears down a sandbox Stratusphere UX environment, removing VNet peering on the test VM VNet first and disarming aa-avdlz-runs schedules.
  Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE at the repo root). Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  Follows the peered VNet teardown order and safety conventions:
    - With -DeallocateOnly: stops the appliance VMs in rg-<Name>-<Environment>-stratusphere to halt
      the compute meter while keeping disks, VNet, peering, and Key Vault intact.
    - Without -DeallocateOnly: requires -DiscardLastCopy (decision 0016: never delete the last copy,
      even with -Force), removes the peering link on the remote test VM VNet first so no Disconnected
      peering is left behind, deletes rg-<Name>-<Environment>-stratusphere, and disarms any pending
      ssux-shutdown-<Name>-* and ssux-teardown-<Name>-* jobSchedules and schedules in aa-avdlz-runs.

.EXAMPLE
  ./scripts/ops/Remove-SandboxStratusphere.ps1 -DeallocateOnly
.EXAMPLE
  ./scripts/ops/Remove-SandboxStratusphere.ps1 -WhatIf -DiscardLastCopy
.EXAMPLE
  ./scripts/ops/Remove-SandboxStratusphere.ps1 -Force -DiscardLastCopy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
  [Alias('NamePrefix')] [ValidatePattern('^[a-z0-9]{2,8}$')] [string] $Name = 'ssux',
  [ValidateSet('dev', 'test', 'prod')] [string] $Environment = 'dev',
  [ValidatePattern('^([a-z0-9]{2,8})?$')] [string] $TestVmName = '',
  [string] $PeerVnetId = '',
  [switch] $DeallocateOnly,
  [switch] $Force,
  [switch] $DiscardLastCopy
)

$ErrorActionPreference = 'Stop'
foreach ($m in 'Az.Accounts', 'Az.Network') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $m
}

$resolvedPeerVnetId = $PeerVnetId
if (-not $resolvedPeerVnetId) {
  $vnet = $null
  if ($TestVmName) {
    $testVmRg = "rg-$TestVmName-$Environment-vm"
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $testVmRg -Name "vnet-$TestVmName-vm" -ErrorAction SilentlyContinue
  }
  else {
    $vnet = @(Get-AzVirtualNetwork | Where-Object { $_.ResourceGroupName -like "rg-*-$Environment-vm" -and $_.Name -like 'vnet-*-vm' }) | Select-Object -First 1
  }
  if ($vnet) { $resolvedPeerVnetId = $vnet.Id }
}

$cleanupParams = @{
  Action          = 'Cleanup'
  Role            = @('Hub')
  NamePrefix      = $Name
  Environment     = $Environment
  DeallocateOnly  = $DeallocateOnly.IsPresent
  Force           = $Force.IsPresent
  DiscardLastCopy = $DiscardLastCopy.IsPresent
}
if ($resolvedPeerVnetId) { $cleanupParams.PeerVnetId = $resolvedPeerVnetId }
if ($WhatIfPreference) { $cleanupParams.WhatIf = $true }

& (Join-Path $PSScriptRoot 'Deploy-Stratusphere.ps1') @cleanupParams
exit $LASTEXITCODE
