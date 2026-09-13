targetScope = 'resourceGroup'

@description('Azure region used by the ag-flow platform.')
param location string

@description('Deployment environment.')
param environmentName string

@description('Solution name used to derive resource names.')
param solutionName string

@description('Principal ID of the existing control-plane user-assigned managed identity (owned by modules/identities.bicep).')
param controlPlaneIdentityPrincipalId string

@description('gpt-5.3-codex GlobalStandard deployment capacity (RP-provided default; no minimum/step exposed by Azure). Environment-specific, no default.')
param codexDeploymentCapacity int

@description('text-embedding-3-large GlobalStandard deployment capacity (RP-provided default; no minimum/step exposed by Azure). Environment-specific, no default.')
param embeddingDeploymentCapacity int

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

// M6-B1: stable, environment-aware deployment names, independent of the pinned model version.
var codexDeploymentName = 'mdl-codex-${environmentName}'
var embeddingDeploymentName = 'mdl-embedding-${environmentName}'

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

// ADR-0009: one named project per environment; SystemAssigned identity matches current Foundry
// project-creation guidance, but grants no access — no RBAC assigned to it in M6 Phase 1.
resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2026-05-01' = {
  parent: foundryAccount
  name: foundryProjectName
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
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

// M6-B1: OpenAI Direct-from-Azure model deployments, version-pinned, no "latest".
resource codexDeployment 'Microsoft.CognitiveServices/accounts/deployments@2026-05-01' = {
  parent: foundryAccount
  name: codexDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: codexDeploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5.3-codex'
      version: '2026-02-24'
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2026-05-01' = {
  parent: foundryAccount
  name: embeddingDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: embeddingDeploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
  // Serialize sibling deployments — the RP rejects concurrent writes to the same account with RequestConflict.
  dependsOn: [
    codexDeployment
  ]
}

output codexDeploymentName string = codexDeployment.name
output embeddingDeploymentName string = embeddingDeployment.name
