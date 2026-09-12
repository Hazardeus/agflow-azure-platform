targetScope = 'resourceGroup'

@description('Deployment environment.')
param environmentName string

@description('Name of the existing Bicep-owned VNet (contains snet-workspaces).')
param vnetName string

@description('Principal ID of the workspace provisioner user-assigned managed identity.')
param workspaceProvisionerPrincipalId string

// ADR-0004: no built-in role grants join-only access without also granting
// subnet write/delete (Network Contributor) or unrelated VNet-level read
// (Windows 365 Network User). This custom role expresses exactly the two
// actions the workspace provisioner needs on snet-workspaces.
var subnetJoinerRoleDefinitionName = guid(subscription().id, environmentName, 'agflow-workspace-subnet-joiner')

// Azure custom role display names must be unique tenant-wide; the logical
// role remains "Agflow Workspace Subnet Joiner" (ADR-0004).
var subnetJoinerRoleDisplayName = 'Agflow Workspace Subnet Joiner - ${environmentName}-${uniqueString(subscription().id)}'

resource workspacesSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-09-01' existing = {
  name: '${vnetName}/snet-workspaces'
}

resource subnetJoinerRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: subnetJoinerRoleDefinitionName
  properties: {
    roleName: subnetJoinerRoleDisplayName
    description: 'ADR-0004: read and join snet-workspaces only. No subnet/VNet write or delete.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Network/virtualNetworks/subnets/read'
          'Microsoft.Network/virtualNetworks/subnets/join/action'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
    // Durable Bicep-owned platform infrastructure, assignable only within the platform resource group (ADR-0004).
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

// ADR-0004: assignment scoped to snet-workspaces only — not the VNet, not the resource group.
resource workspaceProvisionerSubnetJoinAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspacesSubnet.id, workspaceProvisionerPrincipalId, subnetJoinerRoleDefinition.id)
  scope: workspacesSubnet
  properties: {
    roleDefinitionId: subnetJoinerRoleDefinition.id
    principalId: workspaceProvisionerPrincipalId
    principalType: 'ServicePrincipal'
    description: 'ADR-0004: devpod-ui/OpenTofu joins workspace NICs to snet-workspaces only.'
  }
}

output subnetJoinerRoleDefinitionId string = subnetJoinerRoleDefinition.id
