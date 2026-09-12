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
