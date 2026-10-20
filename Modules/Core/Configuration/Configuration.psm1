Import-Module "$HOME_PROJECT\Modules\Core\Validation\Validation.psm1" -Force
function Get-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $messages = [System.Collections.Generic.List[string]]::new()
    $data = $null

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Arquivo de configuração não encontrado: $Path"
        }

        if ([System.IO.Path]::GetExtension($Path) -ne '.psd1') {
            throw "Formato de configuração inválido. Esperado: .psd1"
        }


        $data = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop

        if ($data -isnot [System.Collections.IDictionary]) {
            throw "O arquivo deve conter uma tabela de configuração válida."
        }

        $messages.Add("Configuração carregada com sucesso.")
    }
    catch {
        $data = $null
        $messages.Add($_.Exception.Message)
    }

    return [PSCustomObject]@{
        Status   = ($null -ne $data)
        Messages = [string[]]$messages.ToArray()
        Data     = $data
    }
}

Export-ModuleMember -Function Get-Configuration
