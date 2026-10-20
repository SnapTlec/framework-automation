param(
    [ValidateSet(
        "Desenvimento",
        "Homologacao",
        "Producao"
    )]
    [Parameter(Mandatory)]
    [string]$Enviromnet
)
$global:HOME_SERVICE = $PSScriptRoot
Import-Module "$HOME_SERVICE\Modules\Core\Configuration\Configuration.psm1"
Import-Module "$HOME_SERVICE\Modules\Core\Logging\Logging.psm1"
Import-Module "$HOME_SERVICE\Main.psm1"

$GLOBAL_CONFIG_PATH = ""
$ENVIROMNET_CONFIG_PATH = "$($HOME_SERVICE)\Appsettings.$($Enviromnet).psd1"

$globalConfig = Get-Configuration -Path $GLOBAL_CONFIG_PATH

#Inciar o log
Start-Log -Path $globalConfig.PATH.LOG

try {
    $enviromnetConfig = Get-Configuration -Path $ENVIROMNET_CONFIG_PATH
    Main -CONFIG $enviromnetConfig.Data
}
catch {
    Write-Log -Level 'ERROR' -Message "Ocorreu um erro durante a incialização do serviço: $($_)"
}
finally {
    Stop-Log
}

