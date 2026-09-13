targetScope = 'resourceGroup'

@description('Azure region used by the ag-flow platform.')
param location string

@description('Deployment environment.')
param environmentName string

@description('Solution name used to derive resource names.')
param solutionName string

@description('Principal ID of the existing control-plane user-assigned managed identity (owned by modules/identities.bicep).')
param controlPlaneIdentityPrincipalId string

var commonTags = {
  solution: solutionName
  environment: environmentName
  managedBy: 'bicep'
  purpose: 'ai-foundry'
}

// ADR-0008: deterministic, globally-unique account name; also used as customSubDomainName.
var foundryAccountName = toLower('aif-${solutionName}-${environmentName}-${uniqueString(subscription().id)}')
var foundryProjectName = 'proj-${solutionName}-${environmentName}'

// ADR-0008: verified built-in "Foundry User" role — keyless data-plane inference/project access.
var foundryUserRoleDefinitionId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

// ADR-0008: SystemAssigned identity is required by Foundry for project management (allowProjectManagement);
// it is independent of, and does not replace, the control-plane UAMI. No RBAC is granted to it.
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2026-05-01' = {
  name: foundryAccountName
  location: location
  tags: commonTags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryAccountName
    disableLocalAuth: true
    // ADR-0008: temporary M6 posture; Private Endpoint/DNS migration is M7 scope.
    publicNetworkAccess: 'Enabled'
  }
}

// ADR-0008: one named project per environment; no project-level identity until a concrete need exists.
resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2026-05-01' = {
  parent: foundryAccount
  name: foundryProjectName
  location: location
  tags: commonTags
  properties: {}
}

resource foundryUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: foundryUserRoleDefinitionId
}

// ADR-0008: keyless data-plane inference access for the control-plane identity, scoped to this account only.
resource controlPlaneFoundryUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryAccount.id, controlPlaneIdentityPrincipalId, foundryUserRoleDefinition.id)
  scope: foundryAccount
  properties: {
    roleDefinitionId: foundryUserRoleDefinition.id
    principalId: controlPlaneIdentityPrincipalId
    principalType: 'ServicePrincipal'
    description: 'ADR-0008: control-plane keyless inference access to the Foundry account.'
  }
}

output foundryAccountId string = foundryAccount.id
output foundryAccountName string = foundryAccount.name
output foundryAccountEndpoint string = foundryAccount.properties.endpoint
output foundryProjectId string = foundryProject.id
output foundryProjectName string = foundryProject.name
