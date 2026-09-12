targetScope = 'resourceGroup'

@description('Principal ID of the workspace provisioner user-assigned managed identity.')
param workspaceProvisionerPrincipalId string

// Azure built-in "Virtual Machine Contributor" role definition ID (ADR-0004).
// Verified against https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/compute#virtual-machine-contributor
var vmContributorRoleDefinitionId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

resource vmContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: vmContributorRoleDefinitionId
}

// ADR-0004: workspace provisioner may manage VM/NIC/disk resources only within this resource group.
resource workspaceProvisionerVmContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, workspaceProvisionerPrincipalId, vmContributorRoleDefinition.id)
  properties: {
    roleDefinitionId: vmContributorRoleDefinition.id
    principalId: workspaceProvisionerPrincipalId
    principalType: 'ServicePrincipal'
    description: 'ADR-0004: devpod-ui/OpenTofu workspace VM/NIC/disk provisioning.'
  }
}
