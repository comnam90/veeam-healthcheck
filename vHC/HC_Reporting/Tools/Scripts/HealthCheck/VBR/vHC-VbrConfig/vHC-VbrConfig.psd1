@{
    ModuleVersion     = '1.0.0'
    RootModule        = 'vHC-VbrConfig.psm1'
    PowerShellVersion = '5.1'
    Description       = 'VBR configuration collector module for Veeam Health Check'
    Author            = 'Veeam Health Check'
    # Lock down to an explicit list once all Public functions are stable.
    # Do NOT use @() here - an empty array prevents all exports regardless of Export-ModuleMember.
    FunctionsToExport = '*'
}
