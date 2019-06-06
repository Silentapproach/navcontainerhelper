﻿<# 
 .Synopsis
  Publish an AL Application (including Base App) to a NAV/BC Container
 .Description
  This function will replace the existing application (including base app) with a new application
  The application will be deployed using developer mode (same as used by VS Code)
 .Parameter containerName
  Name of the container to which you want to publish your AL Project
 .Parameter appFile
  Path of the appFile
 .Parameter appDotNetPackagesFolder
  Location of prokect specific dotnet reference assemblies. Default means that the app only uses standard DLLs.
  If your project is using custom DLLs, you will need to place them in this folder and the folder needs to be shared with the container.
 .Parameter credential
  Credentials of the container super user if using NavUserPassword authentication
 .Parameter useCleanDatabase
  Add this switch if you want to uninstall all extensioins and remove all C/AL objects in the range 1..1999999999.
  This switch is needed when turning a C/AL container into an AL Container.
 .Example
  Publish-NewApplicationToNavContainer -containerName test `
                                       -appFile (Join-Path $alProjectFolder ".output\$($appPublisher)_$($appName)_$($appVersion).app") `
                                       -appDotNetPackagesFolder (Join-Path $alProjectFolder ".netPackages") `
                                       -credential $credential

#>
function Publish-NewApplicationToNavContainer {
    Param(
        [string] $containerName = "navserver",
        [Parameter(Mandatory=$true)]
        [string] $appFile,
        [Parameter(Mandatory=$false)]
        [string] $appDotNetPackagesFolder,
        [Parameter(Mandatory=$false)]
        [pscredential] $credential,
        [switch] $useCleanDatabase
    )

    AssumeNavContainer -containerOrImageName $containerName -functionName $MyInvocation.MyCommand.Name

    Add-Type -AssemblyName System.Net.Http

    $customconfig = Get-NavContainerServerConfiguration -ContainerName $containerName

    if ($customConfig.Multitenant -eq "True") {
        throw "This script doesn't support multitenancy"
    }

    $containerAppDotNetPackagesFolder = ""
    if ($appDotNetPackagesFolder -and (Test-Path $appDotNetPackagesFolder)) {
        $containerAppDotNetPackagesFolder = Get-NavContainerPath -containerName $containerName -path $appDotNetPackagesFolder -throw
    }
    
    Invoke-ScriptInNavContainer -containerName $containerName -scriptblock { Param ( $appDotNetPackagesFolder )

        $serviceTierAddInsFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Add-ins").FullName
        $RTCAddInsFolder = (Get-Item "C:\Program Files (x86)\Microsoft Dynamics NAV\*\RoleTailored Client\Add-ins").FullName
    
        if (!(Test-Path (Join-Path $serviceTierAddInsFolder "RTCAddIns"))) {
            new-item -itemtype symboliclink -path $ServiceTierAddInsFolder -name "RTCAddIns" -value $RTCAddInsFolder | Out-Null
        }
        if (Test-Path (Join-Path $serviceTierAddInsFolder "ProjectDotNetPackages")) {
            (Get-Item (Join-Path $serviceTierAddInsFolder "ProjectDotNetPackages")).Delete()
        }
        if ($appDotNetPackagesFolder) {
            new-item -itemtype symboliclink -path $serviceTierAddInsFolder -name "ProjectDotNetPackages" -value $appDotNetPackagesFolder | Out-Null
        }

    } -argumentList $containerAppDotNetPackagesFolder

    if ($useCleanDatabase) {

        Invoke-ScriptInNavContainer -containerName $containerName -scriptblock { Param ( $customConfig )
            
            if (!(Test-Path "c:\run\my\license.flf")) {
                throw "Container must be started with a developer license in order to publish a new application"
            }

            Write-Host "Uninstalling apps"
            Get-NAVAppInfo $serverInstance | Uninstall-NAVApp -DoNotSaveData -WarningAction Ignore -Force

            $tenant = "default"
        
            if ($customConfig.databaseInstance) {
                $databaseServerInstance = "$($customConfig.databaseServer)\$($customConfig.databaseInstance)"
            }
            else {
                $databaseServerInstance = $customConfig.databaseServer
            }

            Write-Host "Removing C/AL Application Objects"
            Delete-NAVApplicationObject -DatabaseName $customConfig.databaseName -DatabaseServer $databaseServerInstance -Filter 'ID=1..1999999999' -SynchronizeSchemaChanges Force -Confirm:$false

        } -argumentList $customConfig
    }

    Publish-NavContainerApp -containerName $containerName -appFile $appFile -useDevEndpoint -scope Global
}
Export-ModuleMember -Function Publish-NewApplicationToNavContainer
