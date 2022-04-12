# ---------------------------------------- #
# Classes                                  #
# ---------------------------------------- #

class ResourceManager : ActivedirectoryScanner.IResourceManager {
    [NLog.Logger]$Logger
    [ActiveDirectoryScanner.IConfiguration]$Configuration
    [ActiveDirectoryScanner.DatabaseMapper]$DatabaseMapper

    ResourceManager() {
        $this.Configuration = [ActiveDirectoryScanner.Configuration]::new()
        $this.Logger = [ActiveDirectoryScanner.Logger.Log]::new().Instance
    }
}

class GPOScriptLoader {
    [ActiveDirectoryScanner.IResourceManager]$m_resourceManager
    [ActiveDirectoryScanner.IConfiguration]$m_configuration
    [ActiveDirectoryScanner.DatabaseMapper]$m_dbMapper
    [bool]$m_wasComputerTokenUpdated
    [bool]$m_wasUserTokenUpdated
    [bool]$m_wasConfigurationLoadedFromInitFile
    [bool]$m_wasConfigurationUpdated
    [string]$GPO_SCRIPT_FILENAME = "install_config.ini"
    [string]$m_fullPathToGPOScript

    GPOScriptLoader([ActiveDirectoryScanner.IResourceManager]$resourceManager, [ActiveDirectoryScanner.IConfiguration]$configuration) {
        $this.m_dbMapper = $resourceManager.DatabaseMapper
        $this.m_resourceManager = $resourceManager
        $this.m_configuration = $configuration
        $this.m_fullPathToGPOScript = [System.IO.Path]::Combine($resourceManager.Configuration.LocalExecPath, $this.GPO_SCRIPT_FILENAME)
    }

    [void]RemoveConfigurationFile() {
        try {
            if ($($this.m_wasConfigurationLoadedFromInitFile)) {
                $this.m_resourceManager.Logger.Info("Deleting init config file")
                # Temporary
                Rename-Item -Path $this.m_fullPathToGPOScript -NewName "$($this.m_fullPathToGPOScript).old"
                $this.m_wasConfigurationLoadedFromInitFile = $false
            }
        }
        catch {
            $this.m_resourceManager.Logger.Error($_, "Failed to delete init config file")
        }
    }

    [bool]HasConfigurationInDB() {
        return ($($this.m_dbMapper.ConnectionConfigurations).Count)
    }

    [ActiveDirectoryScanner.ConnectionConfiguration]LoadConfigurationFromDB() {
        return $($this.m_dbMapper.ConnectionConfigurations.Where({ (1 -eq $($_.Id)) }, "First"))
    }

    [ActiveDirectoryScanner.ConnectionConfiguration]ParseConfiguration([System.IO.Stream]$fileStream, [ActiveDirectoryScanner.ConnectionConfiguration]$config) {
        $iniConfigurationSource = [Microsoft.Extensions.Configuration.Ini.IniConfigurationSource]::new()
        $iniConfigurationProvider = [Microsoft.Extensions.Configuration.Ini.IniConfigurationProvider]::new($iniConfigurationSource)
        $iniConfigurationProvider.Load($fileStream)

        $config.Id = 1
        $config.Hostname = [ActiveDirectoryScanner.IniExtensions]::GetAndThrowIfMissing($iniConfigurationProvider, "ERA_AGENT_PROPERTIES:P_HOSTNAME")
        $config.Port = [ActiveDirectoryScanner.IniExtensions]::GetAndThrowIfMissing($iniConfigurationProvider, "ERA_AGENT_PROPERTIES:P_PORT")
        $config.PeerCertificatePfx = [ActiveDirectoryScanner.IniExtensions]::GetAndThrowIfMissing($iniConfigurationProvider, "ERA_AGENT_PROPERTIES:P_CERT_CONTENT")
        $config.PeerCertificatePassword = [ActiveDirectoryScanner.IniExtensions]::GetAndThrowIfMissing($iniConfigurationProvider, "ERA_AGENT_PROPERTIES:P_CERT_PASSWORD")
        $config.CaCertificate = [ActiveDirectoryScanner.IniExtensions]::GetAndThrowIfMissing($iniConfigurationProvider, "ERA_AGENT_PROPERTIES:P_CERT_AUTH_CONTENT")
        $config.ADscannerUuid = [System.Guid]::NewGuid().ToString()

        return $config
    }

    [bool]TryToLoadConfigurationFromInitFile([ActiveDirectoryScanner.ConnectionConfiguration]$config) {
        if (-not([System.IO.File]::Exists($this.m_fullPathToGPOScript))) {
            return $false
        }

        $this.m_resourceManager.Logger.Info("Parsing GPO script $($this.m_fullPathToGPOScript)")
        $fileStream = [System.IO.FileStream]::new($this.m_fullPathToGPOScript, [System.IO.FileMode]::Open)
        $this.ParseConfiguration($fileStream, $config)
        $fileStream.Close()

        return $true
    }

    [ActiveDirectoryScanner.ConnectionConfiguration]LoadConfiguration() {
        if ($this.HasConfigurationInDB()) {
            $connectionConfiguration = $this.LoadConfigurationFromDB()
        }
        else {
            $connectionConfiguration = [ActiveDirectoryScanner.ConnectionConfiguration]::new()
            $this.m_wasConfigurationUpdated = $true
        }

        $this.m_wasConfigurationLoadedFromInitFile = $this.TryToLoadConfigurationFromInitFile($connectionConfiguration)

        if (-not($this.HasConfigurationInDB()) -and -not($this.m_wasConfigurationLoadedFromInitFile)) {
            throw "Please ensure GPO configuration $($this.m_fullPathToGPOScript) is present."
        }

        if (-not([System.String]::IsNullOrEmpty($this.m_configuration.Token))) {
            if ($connectionConfiguration.Token -ne $this.m_configuration.Token) {
                $connectionConfiguration.Token = $this.m_configuration.Token
                $this.m_wasComputerTokenUpdated = $true
            }
            elseif ($this.m_configuration.Token.Equals("none", [System.StringComparison]::InvariantCultureIgnoreCase)) {
                $connectionConfiguration.Token = $null
            }
            $this.m_wasConfigurationUpdated = $true
        }
        else {
            $this.m_configuration.Token = $connectionConfiguration.Token
        }

        if ($null -ne $this.m_configuration.UserConfiguration) {
            $connectionConfiguration.ConfigurationData = $this.m_configuration.UserConfiguration.SaveToBytes()
            $this.m_wasConfigurationUpdated = $true
        }

        if ($null -ne $connectionConfiguration.ConfigurationData) {
            $this.m_configuration.UserConfiguration = [ActiveDirectoryScanner.UserConfiguration]::LoadBytes($connectionConfiguration.ConfigurationData)
        }

        return $connectionConfiguration
    }

    [void]UpdateConfiguration([ActiveDirectoryScanner.ConnectionConfiguration]$config) {
        if ($this.m_wasConfigurationUpdated -or $this.m_wasConfigurationLoadedFromInitFile) {
            $this.m_resourceManager.Logger.Info("Updating configuration")
            $this.SaveConfiguration($config)
        }
    }

    [void]SaveConfiguration([ActiveDirectoryScanner.ConnectionConfiguration]$config) {
        if (0 -eq $($this.m_dbMapper.ConnectionConfigurations).Count) {
            $this.m_dbmapper.Add($config)
            return
        }
        $this.m_dbMapper.Update($config)      
    }

    [bool]WasComputerTokenUpdated() {
        return $($this.m_wasComputerTokenUpdated)
    }
}

class ADScannerComputers : ActiveDirectoryScanner.ADScannerComputers {
    [ActiveDirectoryScanner.IResourceManager]$resourceManager

    ADScannerComputers($resourceManager) : base($resourceManager) {}

    [bool]PerformCompueterSync([object]$Computers, [string]$GroupName) {
        $aDComputerState = [ActiveDirectoryScanner.ADComputerState]::new()
        $Computers | ForEach-Object {
            $Record = $_.DisplayName.ToLower()
            if (-not ([String]::IsNullOrEmpty($GroupName))) {
                $Record = "$GroupName\$Record"
            }
            $DeviceId = $_.DeviceId
            $computerRecord = [ActiveDirectoryScanner.ComputerRecord]::new()
            $computerRecord.Record = $Record
            $computerRecord.RecordSID = $DeviceId
            $aDComputerState.Computers.Add($computerRecord)

            if ($aDComputerState.GroupCounts.ContainsKey($GroupName)) {
                $aDComputerState.GroupCounts[$GroupName] += 1
            }
            else {
                $aDComputerState.GroupCounts.Add($GroupName, 1)
            }
        }
        $this.UpdateComputers($aDComputerState)
        return $aDComputerState.AllComputersValid
    }
}

# ---------------------------------------- #
# Internal functions                       #
# ---------------------------------------- #
function ParseArguments ([bool]$Debug = $false) {
    $resourceManager.Logger.Trace("Parsing input values")
    $configuration.DebugMode = $Debug
    $resourceManager.Logger.Info("Debug mode: $($configuration.DebugMode)")
    $configuration.MaxComputers = $MaxComputers
    $configuration.RequestInterval = $RequestInterval
    $configuration.Addonly = $Addonly
    $configuration.Token = $Token
    $configuration.SyncDisabledComputers = $SyncDisabledComputers

    if ($configuration.AddOnly) {
        $resourceManager.Logger.Info("AD Scanner will only import computers to the server")
    }

    if ($configuration.SyncDisabledComputers) {
        $resourceManager.Logger.Info("Synchronizing also disabled computers due to commandline argument")
    }
}

function EnsureDirectory {
    try {
        [System.IO.Directory]::CreateDirectory($configuration.AppDataPath) | Out-Null
        $directorySecurity = [System.Security.AccessControl.DirectorySecurity]::new($configuration.AppDataPath, ([System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner))
        $directorySecurity.SetOwner([System.Security.Principal.WindowsIdentity]::GetCurrent().User) 
        $directorySecurity.ResetAccessRule(
            [System.Security.AccessControl.FileSystemAccessRule]::new(
                [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
                [System.Security.AccessControl.FileSystemRights]::FullControl,
                ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
        )
        $directorySecurity.SetAccessRuleProtection($true, $false)
        Set-Acl -Path $configuration.AppDataPath -AclObject $directorySecurity
    }
    catch {
        $resourceManager.Logger.Error("There was problem to create directory $($configuration.AppDataPath)")
        throw $_
    } 
}

# ---------------------------------------- #
# Public functions                         #
# ---------------------------------------- #
function Invoke-AzureADSync {
    [CmdletBinding()]
    param (
        [Parameter()]
        [int]
        $MaxComputers = 100,

        [Parameter()]
        [string]
        $GroupName,

        [Parameter()]
        [int]
        $RequestInterval = 60,

        [Parameter()]
        [switch]
        $Addonly,

        [Parameter()]
        [string]
        $Token,

        [Parameter()]
        [switch]
        $SyncDisabledComputers = $false,

        [Parameter()]
        [switch]
        $Force,

        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [object]
        $Computers

    )

    Begin {
        $ComputerObj = @()
    }

    Process {
        $ComputerObj += $Computers
    }

    End {
        $resourceManager = [ResourceManager]::new()
        $configuration = $resourceManager.Configuration
    
        # Start main
        try {
            $resourceManager.Logger.Trace("Starting program")

            $Debug = ($true -eq $MyInvocation.BoundParameters.Debug.IsPresent)
            ParseArguments($Debug)
            EnsureDirectory

            $databaseMapper = [ActiveDirectoryScanner.DatabaseMapper]::new($resourceManager)
            $resourceManager.DatabaseMapper = $databaseMapper
            $gPOScriptLoader = [GPOScriptLoader]::new($resourceManager, $configuration)
            $ConnectionConfiguration = $gPOScriptLoader.LoadConfiguration()
            $grpcClient = [ActiveDirectoryScanner.GrpcClient.GrpcClient]::new($ConnectionConfiguration, $resourceManager)
        
            if (-not([String]::IsNullOrEmpty($configuration.Token))) {
                try {
                    $aDScannerComputers = [ADScannerComputers]::new($resourceManager)
                    $resourceManager.Logger.Info("Maximum number of computer in one request: $($configuration.MaxComputers)")

                    if (($true -eq $Force) -or ($true -eq $gPOScriptLoader.WasComputerTokenUpdated())) {
                        $resourceManager.Logger.Info("Synchronisation forced / Access token was updated -> Resent all computers records")
                        $grpcClient.Send(
                            $databaseMapper.GetListOfAllComputers(),
                            $databaseMapper.GetListOfComputersToDelete(),
                            $databaseMapper.GetListOfGroupsToDelete()
                        )
                    }
                    $flag = $aDScannerComputers.PerformCompueterSync($ComputerObj, $GroupName)
                    $grpcClient.Send(
                        $databaseMapper.GetListOfComputersToAddAndUpdate(),
                        $databaseMapper.GetListOfComputersToDelete(),
                        $databaseMapper.GetListOfGroupsToDelete()
                    )
                    $resourceManager.Logger.Info("Saving changes to the database")
                    $databaseMapper.SaveChanges() | Out-Null
                }
                catch {
                    $resourceManager.Logger.Error("Computer synchronization failed.")
                    throw $_
                }
            }
            $gPOScriptLoader.RemoveConfigurationFile()
            $resourceManager.Logger.Info("Synchronization ended.")
            if ($false -eq $flag) {
                $resourceManager.Logger.Warn("Not all computers were synchronize. See above for issues with individual computers")
            }
            $gPOScriptLoader.UpdateConfiguration($ConnectionConfiguration)
            $databaseMapper.SaveChanges() | Out-Null
        }
        catch {
            $resourceManager.Logger.Error($_, "Program failed with error")
            throw $_
            exit 1
        }
        finally {
            $resourceManager.Logger.Info("Program finished")
            [NLog.LogManager]::Shutdown()
        }
    }
}
