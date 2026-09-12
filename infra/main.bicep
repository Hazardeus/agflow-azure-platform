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

output deploymentLocation string = location
output environment string = environmentName
output solution string = solutionName
