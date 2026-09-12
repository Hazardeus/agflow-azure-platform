targetScope = 'resourceGroup'

@description('Azure region used by the ag-flow platform.')
param location string

@description('Deployment environment.')
param environmentName string

@description('Solution name used to derive resource names.')
param solutionName string

@description('Storage account SKU (redundancy). Environment-specific, no default.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_GZRS'
  'Standard_RAGZRS'
])
param storageSkuName string

@description('Blob soft-delete retention in days. Environment-specific, no default.')
@minValue(1)
@maxValue(365)
param blobSoftDeleteRetentionDays int

var commonTags = {
  solution: solutionName
  environment: environmentName
  managedBy: 'bicep'
  purpose: 'storage'
}

// ADR-0005 naming formula. <=24 chars only guaranteed for the current @allowed environment names (lab/dev/prod).
var storageAccountName = toLower('st${solutionName}${environmentName}${take(uniqueString(subscription().id), 12)}')

// ADR-0005: foundational account only, no consumer-specific RBAC or data-plane children yet.
resource storageAccount 'Microsoft.Storage/storageAccounts@2026-04-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: storageSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    // Explicit M4 hardening beyond ADR-0005's minimum baseline (see ADR-0005).
    allowCrossTenantReplication: false
    networkAcls: {
      defaultAction: 'Allow'
      // No trusted-services bypass yet; must not become a silent exception if defaultAction later moves to Deny.
      bypass: 'None'
    }
  }
}

// ADR-0005: baseline data protection; no lifecycle policy or containers until a consumer exists.
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2026-04-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: blobSoftDeleteRetentionDays
    }
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
