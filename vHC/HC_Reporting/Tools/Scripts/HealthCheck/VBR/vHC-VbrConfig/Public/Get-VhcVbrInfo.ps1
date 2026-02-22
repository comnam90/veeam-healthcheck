#Requires -Version 5.1

function Get-VhcVbrInfo {
    <#
    .Synopsis
        Collects VBR version, database configuration, and MFA settings.
        Outputs _vbrinfo.csv. Should be the last collector to run as it reads
        many registry paths that must not block earlier collectors if they fail.
    .Parameter VBRVersion
        Major VBR version integer (as returned by Get-VhcMajorVersion).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [int] $VBRVersion
    )

    Write-LogFile "Collecting VBR Version info... (VBRVersion=$VBRVersion)"

    $version          = $null
    $fixes            = $null
    $dbServerPath     = $null
    $instancePath     = $null
    $pgDbHost         = $null
    $pgDbDbName       = $null
    $msDbHost         = $null
    $msDbName         = $null
    $dbType           = $null
    $MFAGlobalSetting = $null

    # Registry reads - all silently continue to tolerate remote-execution scenarios
    try {
        $instancePath   = Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\" `
                                           -Name "SqlInstanceName"  -ErrorAction SilentlyContinue
        $dbServerPath   = Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\" `
                                           -Name "SqlServerName"    -ErrorAction SilentlyContinue
        $dbType         = Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\DatabaseConfigurations" `
                                           -Name "SqlActiveConfiguration" -ErrorAction SilentlyContinue
        $pgDbHost       = Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\DatabaseConfigurations\PostgreSql" `
                                           -Name "SqlHostName"      -ErrorAction SilentlyContinue
        $pgDbDbName     = Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\DatabaseConfigurations\PostgreSql" `
                                           -Name "SqlDatabaseName"  -ErrorAction SilentlyContinue
        $msDbHost       = Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\DatabaseConfigurations\MsSql" `
                                           -Name "SqlServerName"    -ErrorAction SilentlyContinue
        $msDbName       = Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\DatabaseConfigurations\MsSql" `
                                           -Name "SqlDatabaseName"  -ErrorAction SilentlyContinue

        if ($dbType.SqlActiveConfiguration -ne "PostgreSql") {
            if (-not $instancePath -or $instancePath.SqlInstanceName -eq "") {
                $instancePath = Get-ItemProperty `
                    -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\DatabaseConfigurations\MsSql" `
                    -Name "SqlInstanceName" -ErrorAction SilentlyContinue
            }
        }

        # DLL version and patch notes
        $coreRegPath = Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\" `
                                        -Name "CorePath" -ErrorAction SilentlyContinue
        if ($coreRegPath) {
            $dllPath = Join-Path -Path $coreRegPath.CorePath -ChildPath "Veeam.Backup.Core.dll" -Resolve -ErrorAction SilentlyContinue
            if ($dllPath) {
                $dllFile = Get-Item -Path $dllPath -ErrorAction SilentlyContinue
                if ($dllFile) {
                    $version = $dllFile.VersionInfo.ProductVersion
                    $fixes   = $dllFile.VersionInfo.Comments
                }
            }
        }
    } catch {
        Write-LogFile "Get-VhcVbrInfo: failed to read registry values: $($_.Exception.Message)" -LogLevel "WARNING"
    }

    # MFA global setting - only available on VBR 12+; fails gracefully on earlier versions
    try {
        Write-LogFile "Getting MFA Global Setting"
        $MFAGlobalSetting = [Veeam.Backup.Core.SBackupOptions]::get_GlobalMFA()
    } catch {
        Write-LogFile "Failed to get MFA Global Setting, likely pre-VBR 12"
        $MFAGlobalSetting = "N/A - Pre VBR 12"
    }

    [pscustomobject][ordered]@{
        'Version'   = $version
        'Fixes'     = $fixes
        'SqlServer' = $dbServerPath.SqlServerName
        'Instance'  = $instancePath.SqlInstanceName
        'PgHost'    = $pgDbHost.SqlHostName
        'PgDb'      = $pgDbDbName.SqlDatabaseName
        'MsHost'    = $msDbHost.SqlServerName
        'MsDb'      = $msDbName.SqlDatabaseName
        'DbType'    = $dbType.SqlActiveConfiguration
        'MFA'       = $MFAGlobalSetting
    } | Export-VhcCsv -FileName '_vbrinfo.csv'

    Write-LogFile "Collecting VBR Version info...DONE"
}
