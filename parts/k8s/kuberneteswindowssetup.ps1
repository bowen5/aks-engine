<#
    .SYNOPSIS
        Provisions VM as a Kubernetes agent.

    .DESCRIPTION
        Provisions VM as a Kubernetes agent.

        The parameters passed in are required, and will vary per-deployment.

        Notes on modifying this file:
        - This file extension is PS1, but it is actually used as a template from pkg/engine/template_generator.go
        - All of the lines that have braces in them will be modified. Please do not change them here, change them in the Go sources
        - Single quotes are forbidden, they are reserved to delineate the different members for the ARM template concat() call
#>
[CmdletBinding(DefaultParameterSetName="Standard")]
param(
    [string]
    [ValidateNotNullOrEmpty()]
    $MasterIP,

    [parameter()]
    [ValidateNotNullOrEmpty()]
    $KubeDnsServiceIp,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $MasterFQDNPrefix,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $Location,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $AgentKey,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $AADClientId,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $AADClientSecret, # base64

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $NetworkAPIVersion,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $TargetEnvironment
)

# These globals will not change between nodes in the same cluster, so they are not
# passed as powershell parameters

## SSH public keys to add to authorized_keys
$global:SSHKeys = @( {{ GetSshPublicKeysPowerShell }} )

## Certificates generated by aks-engine
$global:CACertificate = "{{WrapAsParameter "caCertificate"}}"
$global:AgentCertificate = "{{WrapAsParameter "clientCertificate"}}"

## Download sources provided by aks-engine
$global:KubeBinariesPackageSASURL = "{{WrapAsParameter "kubeBinariesSASURL"}}"
$global:WindowsKubeBinariesURL = "{{WrapAsParameter "windowsKubeBinariesURL"}}"
$global:KubeBinariesVersion = "{{WrapAsParameter "kubeBinariesVersion"}}"
$global:ContainerdUrl = "{{WrapAsParameter "windowsContainerdURL"}}"
$global:ContainerdSdnPluginUrl = "{{WrapAsParameter "windowsSdnPluginURL"}}"

## Docker Version
$global:DockerVersion = "{{WrapAsParameter "windowsDockerVersion"}}"

## ContainerD Usage
$global:ContainerRuntime = "{{WrapAsParameter "containerRuntime"}}"

## VM configuration passed by Azure
$global:WindowsTelemetryGUID = "{{WrapAsParameter "windowsTelemetryGUID"}}"
{{if eq GetIdentitySystem "adfs"}}
$global:TenantId = "adfs"
{{else}}
$global:TenantId = "{{WrapAsVariable "tenantID"}}"
{{end}}
$global:SubscriptionId = "{{WrapAsVariable "subscriptionId"}}"
$global:ResourceGroup = "{{WrapAsVariable "resourceGroup"}}"
$global:VmType = "{{WrapAsVariable "vmType"}}"
$global:SubnetName = "{{WrapAsVariable "subnetName"}}"
$global:MasterSubnet = "{{GetWindowsMasterSubnetARMParam}}"
$global:SecurityGroupName = "{{WrapAsVariable "nsgName"}}"
$global:VNetName = "{{WrapAsVariable "virtualNetworkName"}}"
$global:RouteTableName = "{{WrapAsVariable "routeTableName"}}"
$global:PrimaryAvailabilitySetName = "{{WrapAsVariable "primaryAvailabilitySetName"}}"
$global:PrimaryScaleSetName = "{{WrapAsVariable "primaryScaleSetName"}}"

$global:KubeClusterCIDR = "{{WrapAsParameter "kubeClusterCidr"}}"
$global:KubeServiceCIDR = "{{WrapAsParameter "kubeServiceCidr"}}"
$global:VNetCIDR = "{{WrapAsParameter "vnetCidr"}}"
{{if IsKubernetesVersionGe "1.16.0"}}
$global:KubeletNodeLabels = "{{GetAgentKubernetesLabels . "',variables('labelResourceGroup'),'"}}"
{{else}}
$global:KubeletNodeLabels = "{{GetAgentKubernetesLabelsDeprecated . "',variables('labelResourceGroup'),'"}}"
{{end}}
$global:KubeletConfigArgs = @( {{GetKubeletConfigKeyValsPsh .KubernetesConfig }} )

$global:UseManagedIdentityExtension = "{{WrapAsVariable "useManagedIdentityExtension"}}"
$global:UserAssignedClientID = "{{WrapAsVariable "userAssignedClientID"}}"
$global:UseInstanceMetadata = "{{WrapAsVariable "useInstanceMetadata"}}"

$global:LoadBalancerSku = "{{WrapAsVariable "loadBalancerSku"}}"
$global:ExcludeMasterFromStandardLB = "{{WrapAsVariable "excludeMasterFromStandardLB"}}"


# Windows defaults, not changed by aks-engine
$global:CacheDir = "c:\akse-cache"
$global:KubeDir = "c:\k"
$global:HNSModule = [Io.path]::Combine("$global:KubeDir", "hns.psm1")

$global:KubeDnsSearchPath = "svc.cluster.local"

$global:CNIPath = [Io.path]::Combine("$global:KubeDir", "cni")
$global:NetworkMode = "L2Bridge"
$global:CNIConfig = [Io.path]::Combine($global:CNIPath, "config", "`$global:NetworkMode.conf")
$global:CNIConfigPath = [Io.path]::Combine("$global:CNIPath", "config")


$global:AzureCNIDir = [Io.path]::Combine("$global:KubeDir", "azurecni")
$global:AzureCNIBinDir = [Io.path]::Combine("$global:AzureCNIDir", "bin")
$global:AzureCNIConfDir = [Io.path]::Combine("$global:AzureCNIDir", "netconf")

# Azure cni configuration
# $global:NetworkPolicy = "{{WrapAsParameter "networkPolicy"}}" # BUG: unused
$global:NetworkPlugin = "{{WrapAsParameter "networkPlugin"}}"
$global:VNetCNIPluginsURL = "{{WrapAsParameter "vnetCniWindowsPluginsURL"}}"

# Telemetry settings
$global:EnableTelemetry = "{{WrapAsVariable "enableTelemetry" }}";
$global:TelemetryKey = "{{WrapAsVariable "applicationInsightsKey" }}";

# CSI Proxy settings
$global:EnableCsiProxy = [System.Convert]::ToBoolean("{{WrapAsVariable "windowsEnableCSIProxy" }}");
$global:CsiProxyUrl = "{{WrapAsVariable "windowsCSIProxyURL" }}";

# Base64 representation of ZIP archive
$zippedFiles = "{{ GetKubernetesWindowsAgentFunctions }}"

# Extract ZIP from script
[io.file]::WriteAllBytes("scripts.zip", [System.Convert]::FromBase64String($zippedFiles))
Expand-Archive scripts.zip -DestinationPath "C:\\AzureData\\"

# Dot-source contents of zip. This should match the list in template_generator.go GetKubernetesWindowsAgentFunctions
. c:\AzureData\k8s\kuberneteswindowsfunctions.ps1
. c:\AzureData\k8s\windowsconfigfunc.ps1
. c:\AzureData\k8s\windowskubeletfunc.ps1
. c:\AzureData\k8s\windowscnifunc.ps1
. c:\AzureData\k8s\windowsazurecnifunc.ps1
. c:\AzureData\k8s\windowscsiproxyfunc.ps1
. c:\AzureData\k8s\windowsinstallopensshfunc.ps1
. c:\AzureData\k8s\windowscontainerdfunc.ps1

$useContainerD = ($global:ContainerRuntime -eq "containerd")

try
{
    # Set to false for debugging.  This will output the start script to
    # c:\AzureData\CustomDataSetupScript.log, and then you can RDP
    # to the windows machine, and run the script manually to watch
    # the output.
    if ($true) {
        Write-Log "Provisioning $global:DockerServiceName... with IP $MasterIP"

        $global:globalTimer = [System.Diagnostics.Stopwatch]::StartNew()

        $configAppInsightsClientTimer = [System.Diagnostics.Stopwatch]::StartNew()
        # Get app insights binaries and set up app insights client
        mkdir c:\k\appinsights
        DownloadFileOverHttp -Url "https://globalcdn.nuget.org/packages/microsoft.applicationinsights.2.11.0.nupkg" -DestinationPath "c:\k\appinsights\microsoft.applicationinsights.2.11.0.zip"
        Expand-Archive -Path "c:\k\appinsights\microsoft.applicationinsights.2.11.0.zip" -DestinationPath "c:\k\appinsights"
        $appInsightsDll = "c:\k\appinsights\lib\net46\Microsoft.ApplicationInsights.dll"
        [Reflection.Assembly]::LoadFile($appInsightsDll)
        $conf = New-Object "Microsoft.ApplicationInsights.Extensibility.TelemetryConfiguration"
        $conf.DisableTelemetry = -not $global:enableTelemetry
        $conf.InstrumentationKey = $global:TelemetryKey
        $global:AppInsightsClient = New-Object "Microsoft.ApplicationInsights.TelemetryClient"($conf)

        $global:AppInsightsClient.Context.Properties["correlation_id"] = New-Guid
        $global:AppInsightsClient.Context.Properties["cri"] = "docker"
        $global:AppInsightsClient.Context.Properties["cri_version"] = $global:DockerVersion
        $global:AppInsightsClient.Context.Properties["k8s_version"] = $global:KubeBinariesVersion
        $global:AppInsightsClient.Context.Properties["lb_sku"] = $global:LoadBalancerSku
        $global:AppInsightsClient.Context.Properties["location"] = $Location
        $global:AppInsightsClient.Context.Properties["os_type"] = "windows"
        $global:AppInsightsClient.Context.Properties["os_version"] = Get-WindowsVersion
        $global:AppInsightsClient.Context.Properties["network_plugin"] = $global:NetworkPlugin
        $global:AppInsightsClient.Context.Properties["network_plugin_version"] = Get-CniVersion
        $global:AppInsightsClient.Context.Properties["network_mode"] = $global:NetworkMode
        $global:AppInsightsClient.Context.Properties["subscription_id"] = $global:SubscriptionId

        $vhdId = ""
        if (Test-Path "c:\vhd-id.txt") {
            $vhdId = Get-Content "c:\vhd-id.txt"
        }
        $global:AppInsightsClient.Context.Properties["vhd_id"] = $vhdId

        $imdsProperties = Get-InstanceMetadataServiceTelemetry
        foreach ($key in $imdsProperties.keys) {
            $global:AppInsightsClient.Context.Properties[$key] = $imdsProperties[$key]
        }

        $configAppInsightsClientTimer.Stop()
        $global:AppInsightsClient.TrackMetric("Config-AppInsightsClient", $configAppInsightsClientTimer.Elapsed.TotalSeconds)

        # Install OpenSSH if SSH enabled
        $sshEnabled = [System.Convert]::ToBoolean("{{ WindowsSSHEnabled }}")

        if ( $sshEnabled ) {
            Write-Log "Install OpenSSH"
            $installOpenSSHTimer = [System.Diagnostics.Stopwatch]::StartNew()
            Install-OpenSSH -SSHKeys $SSHKeys
            $installOpenSSHTimer.Stop()
            $global:AppInsightsClient.TrackMetric("Install-OpenSSH", $installOpenSSHTimer.Elapsed.TotalSeconds)
        }

        Write-Log "Apply telemetry data setting"
        Set-TelemetrySetting -WindowsTelemetryGUID $global:WindowsTelemetryGUID

        Write-Log "Resize os drive if possible"
        $resizeTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Resize-OSDrive
        $resizeTimer.Stop()
        $global:AppInsightsClient.TrackMetric("Resize-OSDrive", $resizeTimer.Elapsed.TotalSeconds)

        Write-Log "Initialize data disks"
        Initialize-DataDisks

        Write-Log "Create required data directories as needed"
        Initialize-DataDirectories


        if ($useContainerD) {
            Write-Log "Installing ContainerD"
            $containerdTimer = [System.Diagnostics.Stopwatch]::StartNew()
            Install-Containerd -ContainerdUrl $global:ContainerdUrl
            $containerdTimer.Stop()
            $global:AppInsightsClient.TrackMetric("Install-ContainerD", $containerdTimer.Elapsed.TotalSeconds)
            # TODO: disable/uninstall Docker later
        } else {
            Write-Log "Install docker"
            $dockerTimer = [System.Diagnostics.Stopwatch]::StartNew()
            Install-Docker -DockerVersion $global:DockerVersion
            Set-DockerLogFileOptions
            $dockerTimer.Stop()
            $global:AppInsightsClient.TrackMetric("Install-Docker", $dockerTimer.Elapsed.TotalSeconds)
        }

        Write-Log "Download kubelet binaries and unzip"
        Get-KubePackage -KubeBinariesSASURL $global:KubeBinariesPackageSASURL

        # this overwrite the binaries that are download from the custom packge with binaries
        # The custom package has a few files that are nessary for future steps (nssm.exe)
        # this is a temporary work around to get the binaries until we depreciate
        # custom package and nssm.exe as defined in #3851.
        if ($global:WindowsKubeBinariesURL){
            Write-Log "Overwriting kube node binaries from $global:WindowsKubeBinariesURL"
            Get-KubeBinaries -KubeBinariesURL $global:WindowsKubeBinariesURL
        }

        Write-Log "Write Azure cloud provider config"
        Write-AzureConfig `
            -KubeDir $global:KubeDir `
            -AADClientId $AADClientId `
            -AADClientSecret $([System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($AADClientSecret))) `
            -TenantId $global:TenantId `
            -SubscriptionId $global:SubscriptionId `
            -ResourceGroup $global:ResourceGroup `
            -Location $Location `
            -VmType $global:VmType `
            -SubnetName $global:SubnetName `
            -SecurityGroupName $global:SecurityGroupName `
            -VNetName $global:VNetName `
            -RouteTableName $global:RouteTableName `
            -PrimaryAvailabilitySetName $global:PrimaryAvailabilitySetName `
            -PrimaryScaleSetName $global:PrimaryScaleSetName `
            -UseManagedIdentityExtension $global:UseManagedIdentityExtension `
            -UserAssignedClientID $global:UserAssignedClientID `
            -UseInstanceMetadata $global:UseInstanceMetadata `
            -LoadBalancerSku $global:LoadBalancerSku `
            -ExcludeMasterFromStandardLB $global:ExcludeMasterFromStandardLB `
            -TargetEnvironment $TargetEnvironment

        {{if IsAzureStackCloud}}
        $azureStackConfigFile = [io.path]::Combine($global:KubeDir, "azurestackcloud.json")
        $envJSON = "{{ GetBase64EncodedEnvironmentJSON }}"
        [io.file]::WriteAllBytes($azureStackConfigFile, [System.Convert]::FromBase64String($envJSON))
        {{end}}

        Write-Log "Write ca root"
        Write-CACert -CACertificate $global:CACertificate `
            -KubeDir $global:KubeDir

        if ($global:EnableCsiProxy) {
            New-CsiProxyService -CsiProxyPackageUrl $global:CsiProxyUrl -KubeDir $global:KubeDir
        }

        Write-Log "Write kube config"
        Write-KubeConfig -CACertificate $global:CACertificate `
            -KubeDir $global:KubeDir `
            -MasterFQDNPrefix $MasterFQDNPrefix `
            -MasterIP $MasterIP `
            -AgentKey $AgentKey `
            -AgentCertificate $global:AgentCertificate

        Write-Log "Create the Pause Container kubletwin/pause"
        $infraContainerTimer = [System.Diagnostics.Stopwatch]::StartNew()
        New-InfraContainer -KubeDir $global:KubeDir -ContainerRuntime $global:ContainerRuntime
        $infraContainerTimer.Stop()
        $global:AppInsightsClient.TrackMetric("New-InfraContainer", $infraContainerTimer.Elapsed.TotalSeconds)

        if (-not (Test-ContainerImageExists -Image "kubletwin/pause" -ContainerRuntime $global:ContainerRuntime)) {
            Write-Log "Could not find container with name kubletwin/pause"
            if ($useContainerD) {
                $o = ctr -n k8s.io image list
                Write-Log $o
            } else {
                $o = docker image list
                Write-Log $o
            }
            throw "kubletwin/pause container does not exist!"
        }

        Write-Log "Configuring networking with NetworkPlugin:$global:NetworkPlugin"

        # Configure network policy.
        Get-HnsPsm1 -HNSModule $global:HNSModule
        Import-Module $global:HNSModule

        if ($global:NetworkPlugin -eq "azure") {
            Write-Log "Installing Azure VNet plugins"
            Install-VnetPlugins -AzureCNIConfDir $global:AzureCNIConfDir `
                -AzureCNIBinDir $global:AzureCNIBinDir `
                -VNetCNIPluginsURL $global:VNetCNIPluginsURL

            Set-AzureCNIConfig -AzureCNIConfDir $global:AzureCNIConfDir `
                -KubeDnsSearchPath $global:KubeDnsSearchPath `
                -KubeClusterCIDR $global:KubeClusterCIDR `
                -MasterSubnet $global:MasterSubnet `
                -KubeServiceCIDR $global:KubeServiceCIDR `
                -VNetCIDR $global:VNetCIDR `
                -TargetEnvironment $TargetEnvironment

            if ($TargetEnvironment -ieq "AzureStackCloud") {
                GenerateAzureStackCNIConfig `
                    -TenantId $global:TenantId `
                    -SubscriptionId $global:SubscriptionId `
                    -ResourceGroup $global:ResourceGroup `
                    -AADClientId $AADClientId `
                    -KubeDir $global:KubeDir `
                    -AADClientSecret $([System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($AADClientSecret))) `
                    -NetworkAPIVersion $NetworkAPIVersion `
                    -AzureEnvironmentFilePath $([io.path]::Combine($global:KubeDir, "azurestackcloud.json")) `
                    -IdentitySystem "{{ GetIdentitySystem }}"
            }
        }
        elseif ($global:NetworkPlugin -eq "kubenet") {
            Write-Log "Fetching additional files needed for kubenet"
            if ($useContainerD) {
                # TODO: CNI may need to move to c:\program files\containerd\cni\bin with ContainerD
                Install-SdnBridge -Url $global:ContainerdSdnPluginUrl -CNIPath $global:CNIPath
            } else {
                Update-WinCNI -CNIPath $global:CNIPath
            }
            Get-HnsPsm1 -HNSModule $global:HNSModule
        }

        New-ExternalHnsNetwork


        Write-Log "Write kubelet startfile with pod CIDR of $podCIDR"
        Install-KubernetesServices `
            -KubeletConfigArgs $global:KubeletConfigArgs `
            -KubeBinariesVersion $global:KubeBinariesVersion `
            -NetworkPlugin $global:NetworkPlugin `
            -NetworkMode $global:NetworkMode `
            -KubeDir $global:KubeDir `
            -AzureCNIBinDir $global:AzureCNIBinDir `
            -AzureCNIConfDir $global:AzureCNIConfDir `
            -CNIPath $global:CNIPath `
            -CNIConfig $global:CNIConfig `
            -CNIConfigPath $global:CNIConfigPath `
            -MasterIP $MasterIP `
            -KubeDnsServiceIp $KubeDnsServiceIp `
            -MasterSubnet $global:MasterSubnet `
            -KubeClusterCIDR $global:KubeClusterCIDR `
            -KubeServiceCIDR $global:KubeServiceCIDR `
            -HNSModule $global:HNSModule `
            -KubeletNodeLabels $global:KubeletNodeLabels `
            -UseContainerD $useContainerD



        Get-LogCollectionScripts

        Write-Log "Disable Internet Explorer compat mode and set homepage"
        Set-Explorer

        Write-Log "Adjust pagefile size"
        Adjust-PageFileSize

        Write-Log "Start preProvisioning script"
        PREPROVISION_EXTENSION

        Write-Log "Update service failure actions"
        Update-ServiceFailureActions -ContainerRuntime $global:ContainerRuntime

        Adjust-DynamicPortRange
        Register-LogsCleanupScriptTask
        Register-NodeResetScriptTask
        Update-DefenderPreferences

        if (Test-Path $CacheDir)
        {
            Write-Log "Removing aks-engine bits cache directory"
            Remove-Item $CacheDir -Recurse -Force
        }

        $global:globalTimer.Stop()
        $global:AppInsightsClient.TrackMetric("TotalDuration", $global:globalTimer.Elapsed.TotalSeconds)
        $global:AppInsightsClient.Flush()

        Write-Log "Setup Complete, reboot computer"
        Restart-Computer
    }
    else
    {
        # keep for debugging purposes
        Write-Log ".\CustomDataSetupScript.ps1 -MasterIP $MasterIP -KubeDnsServiceIp $KubeDnsServiceIp -MasterFQDNPrefix $MasterFQDNPrefix -Location $Location -AgentKey $AgentKey -AADClientId $AADClientId -AADClientSecret $AADClientSecret -NetworkAPIVersion $NetworkAPIVersion -TargetEnvironment $TargetEnvironment"
    }
}
catch
{
    $exceptionTelemtry = New-Object "Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry"
    $exceptionTelemtry.Exception = $_.Exception
    $global:AppInsightsClient.TrackException($exceptionTelemtry)
    $global:AppInsightsClient.Flush()

    Write-Error $_
    exit 1
}
