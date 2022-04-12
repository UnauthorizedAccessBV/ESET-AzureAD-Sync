# ESET PROTECT - AzureAD Sync Tool

## Introduction

This is a PowerShell module that wraps the official [ESET Active Directory Scanner](https://go.eset.eu/ecp-ads) to allow synchronization of AzureAD joined systems with [ESET PROTECT Cloud](https://help.eset.com/protect_cloud/en-US/index.html) through the [Microsoft Graph API](https://docs.microsoft.com/en-us/graph/use-the-api). It takes an object with at least the following information:

```powershell
# DeviceId can be any string as long as it's unique to the device
$Computers = @{
    "DisplayName" = "Computer-Display-Name"
    "DeviceId" = "00000000-0000-0000-0000-000000000000"
}
```

## Requirements

- PowerShell v7 or higher
- The Microsoft.Graph.Identity.DirectoryManagement PowerShell module
- An ESET PROTECT account with the [AD Scanner Access Token: Write](https://help.eset.com/protect_cloud/en-US/admin_ar_permissions_list.html) permission
- An [Agent GPO Deployment Script](https://help.eset.com/protect_cloud/en-US/fs_agent_deploy_gpo_sccm.html)
- An [Active Directory Synchronization Token](https://support.eset.com/en/kb7760-active-directory-scanner)
- The [Microsoft.Graph.Identity.DirectoryManagement](https://docs.microsoft.com/powershell/module/microsoft.graph.identity.directorymanagement) PowerShell module:

```powershell
Install-Module Microsoft.Graph.Identity.DirectoryManagement
```

## Usage

First, download the [ESET Active Directory Scanner](https://go.eset.eu/ecp-ads) and extract it to the [ActiveDirectoryScanner](AzureADScanner/ActiveDirectoryScanner/) folder. You can also use the helper script to do this for you:

```powershell
./Get-ADScanner.ps1
```

A very basic usage example would be something like this:

```powershell
Import-Module '.\AzureADScanner'

$Token = "<base64 token>"
$Computers = @{
    "DisplayName" = "DESKTOP-ABC123"
    "DeviceId" = "e5b71636-7d5e-4904-8b13-c03b8efc611f"
}

$Computers | Invoke-AzureADSync -Token $Token
```

A more advanced example can be found in the [ADSync.ps1](ADSync.ps1) file.

## Parameters

The following parameters are currently supported:

| **Name**               |              **Description**               |          **Default**          | **Required** |                  **Remarks** |
| ---------------------- | :----------------------------------------: | :---------------------------: | :----------: | ---------------------------: |
| **`-Computers`**       | Object containing computers to synchronize |           **`''`**            |   **Yes**    |            Pipeline variable |
| **`-InstallConfig`**   |      Path to **`install_config.ini`**      | **`$PWD\install_config.ini`** |      No      |                              |
| **`-MaxComputers`**    | Maximum number of computers to synchronize |           **`100`**           |      No      |                              |
| **`-GroupName`**       |     Child group to place computers in      |           **`''`**            |      No      |                              |
| **`-RequestInterval`** |              Request interval              |           **`60`**            |      No      |                              |
| **`-Addonly`**         |   Only add new computers, do not delete    |          **`false`**          |      No      |                              |
| **`-Token`**           |               AD Sync token                |           **`''`**            |      No      | Only required for first run. |
| **`-Force`**           |            Force synchonization            |          **`false`**          |      No      |                              |
