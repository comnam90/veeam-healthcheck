#Requires -Version 5.1

function Get-VhcCredentialsAndNotifications {
    <#
    .Synopsis
        Collects email notification settings and stored credentials (name/username only —
        Veeam cmdlets never expose passwords).
        Exports _EmailNotification.csv, _Credentials.csv.
        Source: Get-VBRConfig.ps1 lines 1435–1457.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting credentials and notification settings..."
    Write-LogFile $message

    $emailNotification = $null
    $credentials       = $null

    try {
        $emailNotification = Get-VBRMailNotification
        Write-LogFile "Email notification settings collected"
    } catch {
        Write-LogFile "Email Notification Settings collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $credentials = Get-VBRCredentials |
            Select-Object Name, UserName, Description, CurrentUser, LastModified
        Write-LogFile "Found $(@($credentials).Count) credentials"
    } catch {
        Write-LogFile "Credentials collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    $emailNotification | Export-VhcCsv -FileName '_EmailNotification.csv'
    $credentials       | Export-VhcCsv -FileName '_Credentials.csv'

    Write-LogFile ($message + "DONE")
}
