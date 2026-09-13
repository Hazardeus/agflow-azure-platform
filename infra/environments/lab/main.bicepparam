using '../../main.bicep'

param location = 'swedencentral'
param environmentName = 'lab'

param vnetAddressPrefix = '10.20.0.0/16'
param controlSubnetPrefix = '10.20.1.0/24'
param workspacesSubnetPrefix = '10.20.2.0/24'
param privateEndpointsSubnetPrefix = '10.20.3.0/24'

param storageSkuName = 'Standard_LRS'
param blobSoftDeleteRetentionDays = 7

// ADR-0006: LAB control-plane compute — Spot is a LAB cost choice, not a PROD standard.
// ADR-0007: Standard_D2as_v5 fits the current Sweden Central LowPriorityCores quota (3);
// Standard_D4as_v5 remains a future LAB scale-up option once quota/demand justify it.
param vmSize = 'Standard_D2as_v5'
param vmPriority = 'Spot'
param spotEvictionPolicy = 'Deallocate'
param spotMaxPrice = -1

param adminUsername = 'agflowadmin'
// Not a secret, but operator-specific — must not be committed; set this env var before deploying.
param adminSshPublicKey = readEnvironmentVariable('AGFLOW_ADMIN_SSH_PUBLIC_KEY')

param osDiskSku = 'StandardSSD_LRS'

param dataDiskSku = 'StandardSSD_LRS'
param dataDiskSizeGiB = 128
param dataDiskCaching = 'None'

