Import-Module -Name '.\AzureADScanner'
Import-Module Microsoft.Graph.Identity.DirectoryManagement

# Connect to MS Graph API using certificate, see: https://docs.microsoft.com/graph/powershell/app-only?tabs=azure-portal for instructions
$ClientId = "00000000-0000-0000-0000-000000000000"
$TenantId = "00000000-0000-0000-0000-000000000000"
$CertificateFile = "path\to\certificate.p12"

Connect-MgGraph -ClientID $ClientId -TenantId $TenantId -Certificate $CertificateFile # Cert can also be loaded from certstore on windows

# Get devices from AAD, see https://docs.microsoft.com/powershell/module/microsoft.graph.identity.directorymanagement/get-mgdevice for options
$AADDevices = Get-MgDevice

# Synchronize devices
$Token = "<base64 token>"
$AADDevices | Invoke-AzureADSync -Token $Token
