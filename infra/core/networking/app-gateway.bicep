param webAppName string
param location string
param publicIPName string
param aiName string
param domainNameLabel string
param gatewaySubnetResourceId string
param gatewayName string
param enableZoneRedundancy bool = true
param enablePreventionMode bool = false

param allowedIps string[] = []

@description('Used by Application Gateway, the Base64 encoded CER/CRT certificate corresponding to the root certificate for Application Gateway.')
@secure()
param gatewayBase64EncodedCertificate string = ''
@secure()
param gatewayCertificatePassword string = ''

@description('The number of Azure Application Gateway capacity units to provision. This setting has a direct impact on consumption cost and is recommended to be left at the default value of 1')
param maxCapacity int = 1
param tags object = {}

resource appInsight 'Microsoft.Insights/components@2020-02-02' existing = {
  name: aiName
}

resource applicationGatewayPublicIpAddress 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIPName
  location: location
  tags: tags
  zones: enableZoneRedundancy
    ? [
        '1'
        '2'
        '3'
      ]
    : []
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: domainNameLabel
    }
  }
}

resource firewallPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-01-01' = {
  name: '${gatewayName}-waf-policy'
  location: location
  tags: tags
  properties: {
    policySettings: {
      state: 'Enabled'
      mode: enablePreventionMode ? 'Prevention' : 'Detection'
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      fileUploadEnforcement: true
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
          ruleGroupOverrides: []
        }
      ]
    }
    customRules: empty(allowedIps)
      ? []
      : [
          {
            priority: 5
            ruleType: 'MatchRule'
            action: enablePreventionMode ? 'Allow' : 'Log'
            name: 'allowIps'
            state: 'Enabled'
            matchConditions: [
              {
                matchValues: allowedIps
                matchVariables: [
                  {
                    variableName: 'RemoteAddr'
                  }
                ]
                operator: 'IPMatch'
                negationConditon: false
              }
            ]
          }
          {
            priority: 10
            ruleType: 'MatchRule'
            action: enablePreventionMode ? 'Block' : 'Log'
            name: 'blockAll'
            state: 'Enabled'
            matchConditions: [
              {
                matchValues: allowedIps
                matchVariables: [
                  {
                    variableName: 'RemoteAddr'
                  }
                ]
                operator: 'IPMatch'
                negationConditon: true
              }
            ]
          }
        ]
  }
}

resource appGateway 'Microsoft.Network/applicationGateways@2024-01-01' = {
  name: gatewayName
  location: location
  tags: tags
  zones: enableZoneRedundancy
    ? [
        '1'
        '2'
        '3'
      ]
    : []
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: maxCapacity < 2 ? 2 : maxCapacity
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: gatewaySubnetResourceId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: applicationGatewayPublicIpAddress.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
      {
        name: 'port_443'
        properties: {
          port: 443
        }
      }
    ]
    sslCertificates: !empty(gatewayBase64EncodedCertificate) && !empty(gatewayCertificatePassword)
      ? [
          {
            name: 'appGatewayCert'
            properties: {
              data: gatewayBase64EncodedCertificate
              password: gatewayCertificatePassword
            }
          }
        ]
      : []
    backendAddressPools: [
      {
        name: 'webappBackEnd'
        properties: {
          backendAddresses: [
            {
              fqdn: '${webAppName}.azurewebsites.net'
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'webapp-http-setting'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          hostName: '${webAppName}.azurewebsites.net'
          pickHostNameFromBackendAddress: false
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', gatewayName, 'webapp-http-probe')
          }
        }
      }
      {
        name: 'webapp-https-setting'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          hostName: '${webAppName}.azurewebsites.net'
          pickHostNameFromBackendAddress: false
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', gatewayName, 'webapp-https-probe')
          }
        }
      }
    ]
    httpListeners: union(
      [
        {
          name: 'port-80-listener'
          properties: {
            frontendIPConfiguration: {
              id: resourceId(
                'Microsoft.Network/applicationGateways/frontEndIPConfigurations',
                gatewayName,
                'appGwPublicFrontendIp'
              )
            }
            frontendPort: {
              id: resourceId('Microsoft.Network/applicationGateways/frontEndPorts', gatewayName, 'port_80')
            }
            protocol: 'Http'
            requireServerNameIndication: false
          }
        }
      ],
      !empty(gatewayBase64EncodedCertificate) && !empty(gatewayCertificatePassword)
        ? [
            {
              name: 'port-443-listener'
              properties: {
                frontendIPConfiguration: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/frontEndIPConfigurations',
                    gatewayName,
                    'appGwPublicFrontendIp'
                  )
                }
                frontendPort: {
                  id: resourceId('Microsoft.Network/applicationGateways/frontEndPorts', gatewayName, 'port_443')
                }
                protocol: 'Https'
                requireServerNameIndication: false
                sslCertificate: {
                  id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', gatewayName, 'appGatewayCert')
                }
              }
            }
          ]
        : []
    )
    requestRoutingRules: union(
      [
        {
          name: 'default-http-routing-rule'
          properties: {
            ruleType: 'Basic'
            priority: 1
            httpListener: {
              id: resourceId('Microsoft.Network/applicationGateways/httpListeners', gatewayName, 'port-80-listener')
            }
            backendAddressPool: {
              id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', gatewayName, 'webappBackEnd')
            }
            backendHttpSettings: {
              id: resourceId(
                'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
                gatewayName,
                'webapp-http-setting'
              )
            }
            rewriteRuleSet: {
              id: resourceId(
                'Microsoft.Network/applicationGateways/rewriteRuleSets',
                gatewayName,
                'easy-auth-rewrite-rule-set'
              )
            }
          }
        }
      ],
      !empty(gatewayBase64EncodedCertificate) && !empty(gatewayCertificatePassword)
        ? [
            {
              name: 'default-https-routing-rule'
              properties: {
                ruleType: 'Basic'
                priority: 2
                httpListener: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/httpListeners',
                    gatewayName,
                    'port-443-listener'
                  )
                }
                backendAddressPool: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/backendAddressPools',
                    gatewayName,
                    'webappBackEnd'
                  )
                }
                backendHttpSettings: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
                    gatewayName,
                    'webapp-https-setting'
                  )
                }
                rewriteRuleSet: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/rewriteRuleSets',
                    gatewayName,
                    'easy-auth-rewrite-rule-set'
                  )
                }
              }
            }
          ]
        : []
    )    
    probes: [
      {
        name: 'webapp-http-probe'
        properties: {
          protocol: 'Http'
          host: '${webAppName}.azurewebsites.net'
          port: 80
          path: '/'
          interval: 30
          timeout: 120
          unhealthyThreshold: 8
          pickHostNameFromBackendHttpSettings: false
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
              '401'
            ]
          }
        }
      }
      {
        name: 'webapp-https-probe'
        properties: {
          protocol: 'Https'
          host: '${webAppName}.azurewebsites.net'
          port: 443
          path: '/'
          interval: 30
          timeout: 120
          unhealthyThreshold: 8
          pickHostNameFromBackendHttpSettings: false
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
              '401'
            ]
          }
        }
      }
    ]
    rewriteRuleSets: [
      {
        name: 'easy-auth-rewrite-rule-set'
        properties: {
          rewriteRules: [
            {
              ruleSequence: 100
              name: 'add-forwarded-host-header'
              actionSet: {
                requestHeaderConfigurations: [
                  {
                    headerName: 'X-Forwarded-Host'
                    headerValue: '{var_host}'
                  }
                ]
              }
            }
          ]
        }
      }
    ]
    firewallPolicy: {
      id: firewallPolicy.id
    }
  }
}

resource appGatewaylogToAnalytics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: appGateway
  name: 'logToAnalytics'
  properties: {
    workspaceId: appInsight.properties.WorkspaceResourceId
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayPerformanceLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayFirewallLog'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

#disable-next-line outputs-should-not-contain-secrets
output fqdn string = '${empty(gatewayBase64EncodedCertificate) ? 'http' : 'https' }://${applicationGatewayPublicIpAddress.properties.dnsSettings.fqdn}'
