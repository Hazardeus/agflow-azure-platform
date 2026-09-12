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

var solutionName = 'agflow'

module resourceGroups 'modules/resource-groups.bicep' = {
  name: 'resource-groups-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    solutionName: solutionName
  }
}

output deploymentLocation string = location
output environment string = environmentName
output solution string = solutionName
output platformResourceGroupName string = resourceGroups.outputs.platformResourceGroupName
output platformResourceGroupId string = resourceGroups.outputs.platformResourceGroupId
output workspacesResourceGroupName string = resourceGroups.outputs.workspacesResourceGroupName
output workspacesResourceGroupId string = resourceGroups.outputs.workspacesResourceGroupId
