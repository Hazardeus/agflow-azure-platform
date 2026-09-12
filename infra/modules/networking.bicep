targetScope = 'resourceGroup'

@description('Azure region used by the ag-flow platform.')
param location string

@description('Deployment environment.')
param environmentName string

@description('Solution name used to derive resource names.')
param solutionName string

@description('VNet address space (CIDR).')
param vnetAddressPrefix string

@description('snet-control address prefix (CIDR).')
param controlSubnetPrefix string

@description('snet-workspaces address prefix (CIDR).')
param workspacesSubnetPrefix string

@description('snet-private-endpoints address prefix (CIDR).')
param privateEndpointsSubnetPrefix string

var commonTags = {
  solution: solutionName
  environment: environmentName
  managedBy: 'bicep'
  purpose: 'networking'
}

var vnetName = 'vnet-${solutionName}-${environmentName}'
var controlNsgName = 'nsg-${solutionName}-control-${environmentName}'
var workspacesNsgName = 'nsg-${solutionName}-workspaces-${environmentName}'

resource controlNsg 'Microsoft.Network/networkSecurityGroups@2025-09-01' = {
  name: controlNsgName
  location: location
  tags: commonTags
}

resource workspacesNsg 'Microsoft.Network/networkSecurityGroups@2025-09-01' = {
  name: workspacesNsgName
  location: location
  tags: commonTags
}

resource vnet 'Microsoft.Network/virtualNetworks@2025-09-01' = {
  name: vnetName
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

// Declared as child resources (rather than inline) so each subnet can be
// referenced symbolically for NSG association and module outputs.
resource controlSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-09-01' = {
  parent: vnet
  name: 'snet-control'
  properties: {
    addressPrefix: controlSubnetPrefix
    defaultOutboundAccess: false
    privateEndpointNetworkPolicies: 'Enabled'
    networkSecurityGroup: {
      id: controlNsg.id
    }
  }
}

resource workspacesSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-09-01' = {
  parent: vnet
  name: 'snet-workspaces'
  properties: {
    addressPrefix: workspacesSubnetPrefix
    defaultOutboundAccess: false
    privateEndpointNetworkPolicies: 'Enabled'
    networkSecurityGroup: {
      id: workspacesNsg.id
    }
  }
  dependsOn: [
    controlSubnet
  ]
}

resource privateEndpointsSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-09-01' = {
  parent: vnet
  name: 'snet-private-endpoints'
  properties: {
    addressPrefix: privateEndpointsSubnetPrefix
    defaultOutboundAccess: false
    privateEndpointNetworkPolicies: 'Enabled'
  }
  dependsOn: [
    workspacesSubnet
  ]
}

output vnetName string = vnet.name
output vnetId string = vnet.id
output controlSubnetId string = controlSubnet.id
output workspaceSubnetId string = workspacesSubnet.id
output privateEndpointSubnetId string = privateEndpointsSubnet.id
output controlNsgId string = controlNsg.id
output workspacesNsgId string = workspacesNsg.id
