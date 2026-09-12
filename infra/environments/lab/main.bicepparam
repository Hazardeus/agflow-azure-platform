using '../../main.bicep'

param location = 'swedencentral'
param environmentName = 'lab'

param vnetAddressPrefix = '10.20.0.0/16'
param controlSubnetPrefix = '10.20.1.0/24'
param workspacesSubnetPrefix = '10.20.2.0/24'
param privateEndpointsSubnetPrefix = '10.20.3.0/24'
