targetScope = 'resourceGroup'

@description('Azure region used by the ag-flow platform.')
param location string

@description('Deployment environment.')
param environmentName string

@description('Solution name used to derive resource names.')
param solutionName string

@description('Resource ID of the existing snet-control subnet.')
param controlSubnetId string

@description('Resource ID of the existing control-plane user-assigned managed identity.')
param controlPlaneIdentityId string

@description('Resource ID of the existing workspace-provisioner user-assigned managed identity.')
param workspaceProvisionerIdentityId string

@description('Control-plane VM size. Environment-specific, no default.')
param vmSize string

@description('Control-plane VM priority. Environment-specific, no default.')
@allowed([
  'Regular'
  'Spot'
])
param vmPriority string

@description('Eviction policy applied when vmPriority is Spot. Ignored otherwise.')
@allowed([
  'Deallocate'
  'Delete'
])
param spotEvictionPolicy string

@description('Max hourly price cap (USD) when vmPriority is Spot, or -1 for no cap. Ignored otherwise.')
param spotMaxPrice int

@description('Control-plane VM admin username.')
param adminUsername string

@description('SSH public key for the control-plane VM admin user. Not a secret, but operator-specific — supplied at deploy time.')
param adminSshPublicKey string

@description('OS disk SKU (redundancy/performance tier). Environment-specific, no default.')
@allowed([
  'Standard_LRS'
  'Premium_LRS'
  'StandardSSD_LRS'
])
param osDiskSku string

@description('Persistent data disk SKU. Environment-specific, no default.')
@allowed([
  'Standard_LRS'
  'Premium_LRS'
  'StandardSSD_LRS'
])
param dataDiskSku string

@description('Persistent data disk size in GiB. Environment-specific, no default.')
param dataDiskSizeGiB int

@description('Persistent data disk host caching mode. Environment-specific, no default.')
@allowed([
  'None'
  'ReadOnly'
  'ReadWrite'
])
param dataDiskCaching string

var commonTags = {
  solution: solutionName
  environment: environmentName
  managedBy: 'bicep'
  purpose: 'control-plane'
}

var publicIpName = 'pip-${solutionName}-control-${environmentName}'
var nicName = 'nic-${solutionName}-control-${environmentName}'
var osDiskName = 'disk-${solutionName}-control-os-${environmentName}'
var dataDiskName = 'disk-${solutionName}-control-data-${environmentName}'
var vmName = 'vm-${solutionName}-control-${environmentName}'

// ADR-0006 §2: Spot-only properties must not appear when a future environment chooses Regular priority.
var isSpot = vmPriority == 'Spot'
var spotProperties = isSpot ? {
  evictionPolicy: spotEvictionPolicy
  billingProfile: {
    maxPrice: spotMaxPrice
  }
} : {}

// ADR-0006 §3: LAB explicit outbound path; egress-only intent enforced by the NSG rule in networking.bicep, not here.
resource controlPlanePublicIp 'Microsoft.Network/publicIPAddresses@2025-09-01' = {
  name: publicIpName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource controlPlaneNic 'Microsoft.Network/networkInterfaces@2025-09-01' = {
  name: nicName
  location: location
  tags: commonTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: controlSubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: controlPlanePublicIp.id
          }
        }
      }
    ]
  }
}

// ADR-0006 §8: independent resource so VM delete/recreate and Spot deallocation never destroy this disk.
resource controlPlaneDataDisk 'Microsoft.Compute/disks@2026-03-02' = {
  name: dataDiskName
  location: location
  tags: commonTags
  sku: {
    name: dataDiskSku
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: dataDiskSizeGiB
  }
}

resource controlPlaneVm 'Microsoft.Compute/virtualMachines@2026-04-01' = {
  name: vmName
  location: location
  tags: commonTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${controlPlaneIdentityId}': {}
      '${workspaceProvisionerIdentityId}': {}
    }
  }
  properties: union(
    {
      hardwareProfile: {
        vmSize: vmSize
      }
      priority: vmPriority
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: 'ubuntu-24_04-lts'
          sku: 'server'
          version: 'latest'
        }
        osDisk: {
          name: osDiskName
          createOption: 'FromImage'
          caching: 'ReadWrite'
          deleteOption: 'Delete'
          managedDisk: {
            storageAccountType: osDiskSku
          }
        }
        // ADR-0006 §8: Attach + fixed LUN 0 + Detach — reuses the same durable disk, never recreates it.
        dataDisks: [
          {
            lun: 0
            createOption: 'Attach'
            deleteOption: 'Detach'
            caching: dataDiskCaching
            managedDisk: {
              id: controlPlaneDataDisk.id
            }
          }
        ]
      }
      osProfile: {
        computerName: vmName
        adminUsername: adminUsername
        customData: base64(loadTextContent('../bootstrap/control-plane-cloud-init.yaml'))
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: adminSshPublicKey
              }
            ]
          }
          patchSettings: {
            patchMode: 'AutomaticByPlatform'
            assessmentMode: 'AutomaticByPlatform'
          }
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: controlPlaneNic.id
          }
        ]
      }
      // ADR-0006 §7: Gen2 image required for Trusted Launch/Secure Boot/vTPM.
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
        }
      }
    },
    spotProperties
  )
}

output controlPlaneVmId string = controlPlaneVm.id
output controlPlaneVmName string = controlPlaneVm.name
output controlPlaneNicId string = controlPlaneNic.id
output controlPlanePrivateIp string = controlPlaneNic.properties.ipConfigurations[0].properties.privateIPAddress
output controlPlanePublicIpId string = controlPlanePublicIp.id
output controlPlaneDataDiskId string = controlPlaneDataDisk.id
