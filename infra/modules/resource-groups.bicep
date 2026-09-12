targetScope = 'subscription'

@description('Azure region used by the ag-flow platform.')
param location string

@description('Deployment environment.')
param environmentName string

@description('Solution name used to derive resource names.')
param solutionName string

var commonTags = {
  solution: solutionName
  environment: environmentName
  managedBy: 'bicep'
}

var platformResourceGroupName = 'rg-${solutionName}-platform-${environmentName}'
var workspacesResourceGroupName = 'rg-${solutionName}-workspaces-${environmentName}'

resource platformResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: platformResourceGroupName
  location: location
  tags: union(commonTags, {
    purpose: 'platform'
  })
}

resource workspacesResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: workspacesResourceGroupName
  location: location
  tags: union(commonTags, {
    purpose: 'workspaces'
  })
}

output platformResourceGroupName string = platformResourceGroup.name
output platformResourceGroupId string = platformResourceGroup.id
output workspacesResourceGroupName string = workspacesResourceGroup.name
output workspacesResourceGroupId string = workspacesResourceGroup.id
