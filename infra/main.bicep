targetScope = 'subscription'

@description('Azure region used by the ag-flow platform.')
param location string = 'swedencentral'

@description('Deployment environment.')
@allowed([
  'lab'
  'dev'
  'prod'
])
param environmentName string = 'lab'

@description('VNet address space (CIDR). Environment-specific, no default.')
param vnetAddressPrefix string

@description('snet-control address prefix (CIDR). Environment-specific, no default.')
param controlSubnetPrefix string

@description('snet-workspaces address prefix (CIDR). Environment-specific, no default.')
param workspacesSubnetPrefix string

@description('snet-private-endpoints address prefix (CIDR). Environment-specific, no default.')
param privateEndpointsSubnetPrefix string

@description('Shared storage account SKU (redundancy). Environment-specific, no default.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_GZRS'
  'Standard_RAGZRS'
])
param storageSkuName string

@description('Blob soft-delete retention in days for shared storage. Environment-specific, no default.')
param blobSoftDeleteRetentionDays int

@description('Control-plane VM size. Environment-specific, no default.')
param vmSize string

@description('Control-plane VM priority. Environment-specific, no default.')
@allowed([
  'Regular'
  'Spot'
])
param vmPriority string

@description('Eviction policy applied when vmPriority is Spot. Ignored otherwise.')
@allowed([
  'Deallocate'
  'Delete'
])
param spotEvictionPolicy string

@description('Max hourly price cap (USD) when vmPriority is Spot, or -1 for no cap. Ignored otherwise.')
param spotMaxPrice int

@description('Control-plane VM admin username. Environment-specific, no default.')
param adminUsername string

@description('SSH public key for the control-plane VM admin user. Supplied at deploy time, not committed to Git.')
param adminSshPublicKey string

@description('Control-plane OS disk SKU. Environment-specific, no default.')
@allowed([
  'Standard_LRS'
  'Premium_LRS'
  'StandardSSD_LRS'
])
param osDiskSku string

@description('Control-plane persistent data disk SKU. Environment-specific, no default.')
@allowed([
  'Standard_LRS'
  'Premium_LRS'
  'StandardSSD_LRS'
])
param dataDiskSku string

@description('Control-plane persistent data disk size in GiB. Environment-specific, no default.')
param dataDiskSizeGiB int

@description('Control-plane persistent data disk host caching mode. Environment-specific, no default.')
@allowed([
  'None'
  'ReadOnly'
  'ReadWrite'
])
param dataDiskCaching string

var solutionName = 'agflow'

// Mirrors the naming formula in modules/resource-groups.bicep (ADR-0002).
// Module `scope` must be a deploy-time constant, so it cannot reference
// resourceGroups.outputs.platformResourceGroupName directly (BCP120).
var platformResourceGroupName = 'rg-${solutionName}-platform-${environmentName}'
var workspacesResourceGroupName = 'rg-${solutionName}-workspaces-${environmentName}'

module resourceGroups 'modules/resource-groups.bicep' = {
  name: 'resource-groups-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    solutionName: solutionName
  }
}

module networking 'modules/networking.bicep' = {
  name: 'networking-${environmentName}'
  scope: resourceGroup(platformResourceGroupName)
  params: {
    location: location
    environmentName: environmentName
    solutionName: solutionName
    vnetAddressPrefix: vnetAddressPrefix
    controlSubnetPrefix: controlSubnetPrefix
    workspacesSubnetPrefix: workspacesSubnetPrefix
    privateEndpointsSubnetPrefix: privateEndpointsSubnetPrefix
  }
  dependsOn: [
    resourceGroups
  ]
}

module identities 'modules/identities.bicep' = {
  name: 'identities-${environmentName}'
  scope: resourceGroup(platformResourceGroupName)
  params: {
    location: location
    environmentName: environmentName
    solutionName: solutionName
  }
  dependsOn: [
    resourceGroups
  ]
}

// ADR-0004: Virtual Machine Contributor on the ephemeral workspace resource group only.
module rbacWorkspaceRg 'modules/rbac-workspace-rg.bicep' = {
  name: 'rbac-workspace-rg-${environmentName}'
  scope: resourceGroup(workspacesResourceGroupName)
  params: {
    workspaceProvisionerPrincipalId: identities.outputs.workspaceProvisionerIdentityPrincipalId
  }
  dependsOn: [
    resourceGroups
  ]
}

// ADR-0004: custom-role join-only access scoped to snet-workspaces only.
module rbacWorkspaceSubnet 'modules/rbac-workspace-subnet.bicep' = {
  name: 'rbac-workspace-subnet-${environmentName}'
  scope: resourceGroup(platformResourceGroupName)
  params: {
    environmentName: environmentName
    vnetName: networking.outputs.vnetName
    workspaceProvisionerPrincipalId: identities.outputs.workspaceProvisionerIdentityPrincipalId
  }
  dependsOn: [
    resourceGroups
  ]
}

// ADR-0005: foundational shared Storage Account, no workload RBAC or data-plane children yet.
module storage 'modules/storage.bicep' = {
  name: 'storage-${environmentName}'
  scope: resourceGroup(platformResourceGroupName)
  params: {
    location: location
    environmentName: environmentName
    solutionName: solutionName
    storageSkuName: storageSkuName
    blobSoftDeleteRetentionDays: blobSoftDeleteRetentionDays
  }
  dependsOn: [
    resourceGroups
  ]
}

// ADR-0006: control-plane compute, LAB Public IP egress, durable data disk; both UAMIs attached, no new RBAC.
module controlPlaneCompute 'modules/control-plane-compute.bicep' = {
  name: 'control-plane-compute-${environmentName}'
  scope: resourceGroup(platformResourceGroupName)
  params: {
    location: location
    environmentName: environmentName
    solutionName: solutionName
    controlSubnetId: networking.outputs.controlSubnetId
    controlPlaneIdentityId: identities.outputs.controlPlaneIdentityId
    workspaceProvisionerIdentityId: identities.outputs.workspaceProvisionerIdentityId
    vmSize: vmSize
    vmPriority: vmPriority
    spotEvictionPolicy: spotEvictionPolicy
    spotMaxPrice: spotMaxPrice
    adminUsername: adminUsername
    adminSshPublicKey: adminSshPublicKey
    osDiskSku: osDiskSku
    dataDiskSku: dataDiskSku
    dataDiskSizeGiB: dataDiskSizeGiB
    dataDiskCaching: dataDiskCaching
  }
  dependsOn: [
    resourceGroups
  ]
}

output deploymentLocation string = location
output environment string = environmentName
output solution string = solutionName
output platformResourceGroupName string = resourceGroups.outputs.platformResourceGroupName
output platformResourceGroupId string = resourceGroups.outputs.platformResourceGroupId
output workspacesResourceGroupName string = resourceGroups.outputs.workspacesResourceGroupName
output workspacesResourceGroupId string = resourceGroups.outputs.workspacesResourceGroupId
output vnetId string = networking.outputs.vnetId
output workspaceSubnetId string = networking.outputs.workspaceSubnetId
output controlPlaneIdentityId string = identities.outputs.controlPlaneIdentityId
output controlPlaneIdentityClientId string = identities.outputs.controlPlaneIdentityClientId
output workspaceProvisionerIdentityId string = identities.outputs.workspaceProvisionerIdentityId
output workspaceProvisionerIdentityClientId string = identities.outputs.workspaceProvisionerIdentityClientId
output storageAccountId string = storage.outputs.storageAccountId
output storageAccountName string = storage.outputs.storageAccountName
output controlPlaneVmId string = controlPlaneCompute.outputs.controlPlaneVmId
output controlPlaneVmName string = controlPlaneCompute.outputs.controlPlaneVmName
output controlPlaneNicId string = controlPlaneCompute.outputs.controlPlaneNicId
output controlPlanePrivateIp string = controlPlaneCompute.outputs.controlPlanePrivateIp
output controlPlanePublicIpId string = controlPlaneCompute.outputs.controlPlanePublicIpId
output controlPlaneDataDiskId string = controlPlaneCompute.outputs.controlPlaneDataDiskId
