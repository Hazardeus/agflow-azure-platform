targetScope = 'resourceGroup'

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
  purpose: 'identity'
}

var controlPlaneIdentityName = 'id-${solutionName}-control-plane-${environmentName}'
var workspaceProvisionerIdentityName = 'id-${solutionName}-workspace-provisioner-${environmentName}'

// ADR-0004: created now with no RBAC; permissions are added when a real consumer exists.
resource controlPlaneIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: controlPlaneIdentityName
  location: location
  tags: commonTags
}

// ADR-0004: used by devpod-ui/OpenTofu; RBAC granted by the rbac-workspace-* modules.
resource workspaceProvisionerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: workspaceProvisionerIdentityName
  location: location
  tags: commonTags
}

output controlPlaneIdentityId string = controlPlaneIdentity.id
output controlPlaneIdentityPrincipalId string = controlPlaneIdentity.properties.principalId
output controlPlaneIdentityClientId string = controlPlaneIdentity.properties.clientId
output workspaceProvisionerIdentityId string = workspaceProvisionerIdentity.id
output workspaceProvisionerIdentityPrincipalId string = workspaceProvisionerIdentity.properties.principalId
output workspaceProvisionerIdentityClientId string = workspaceProvisionerIdentity.properties.clientId
