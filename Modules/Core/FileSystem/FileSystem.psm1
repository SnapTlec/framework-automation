function Get-ShareHost {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -match '^\\\\([^\\]+)\\') {
        return $Matches[1]
    }
    return $null
}

function Get-RemFiles {
    <#
    .SYNOPSIS
    Descobre arquivos .REM nas origens configuradas.
    
    .DESCRIPTION
    Localiza as remessas elegíveis nas origens principal e remota. Deve concentrar os critérios de seleção dos arquivos, como a extensão .REM.
    
    .PARAMETER Path
    Parameter description
    
    .PARAMETER SourceName
    Parameter description
    
    .PARAMETER IsRemote
    Parameter description
    
    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SourceName,
        [bool]$IsRemote = $false
    )

    $items = Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction Stop |
        Where-Object { $_.Extension -ieq '.REM' } |
        Sort-Object -Property Name

    $results = @()
    foreach ($item in $items) {
        $owner = $null
        $shareHost = $null

        if ($IsRemote) {
            $owner = Get-SourceOwner -Path $item.FullName
            $shareHost = Get-ShareHost -Path $item.FullName
        }

        $results += [pscustomobject]@{
            Name          = $item.Name
            FullName      = $item.FullName
            SourceName    = $SourceName
            IsRemote      = $IsRemote
            SourceOwner   = $owner
            SourceShareHost = $shareHost
            Length        = $item.Length
            LastWriteTimeUtc = $item.LastWriteTimeUtc
        }
    }

    return $results
}

function Get-FileSha256 {
    <#
    .SYNOPSIS
    Calcula o hash para validação da integridade dos arquivos.
    
    .DESCRIPTION
    Long description
    
    .PARAMETER Path
    Parameter description
    
    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Move-RemFileSafely {
    <#
    .SYNOPSIS
    Transporta os arquivos com cópia controlada, validação e remoção segura da origem.
    
    .DESCRIPTION
    Long description
    
    .PARAMETER File
    Parameter description
    
    .PARAMETER DestinationDirectory
    Parameter description
    
    .PARAMETER ExecutionId
    Parameter description
    
    .PARAMETER OperationalLogPath
    Parameter description
    
    .PARAMETER Configuration
    Parameter description
    
    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$File,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [Parameter(Mandatory)][string]$ExecutionId,
        [Parameter(Mandatory)][string]$OperationalLogPath,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Configuration
    )

    $destinationPath = Join-Path $DestinationDirectory $File.Name
    $temporaryPath = Join-Path $DestinationDirectory ('.{0}.{1}.partial' -f $File.Name, $ExecutionId)

    if (Test-Path -LiteralPath $destinationPath) {
        $message = "Destino já contém um arquivo com o mesmo nome; nenhuma sobrescrita foi realizada."
        Write-AdminEvent -ExecutionId $ExecutionId -Level WARN -Message "Conflito de destino para '$($File.FullName)': '$destinationPath'." -Configuration $Configuration
        Write-BusinessEvent -Path $OperationalLogPath -ExecutionId $ExecutionId -Event 'TRANSPORT' -FileName $File.Name -Source $File.SourceName -Status 'CONFLICT' -Message $message -SourceOwner $File.SourceOwner -SourceShareHost $File.SourceShareHost
        return [pscustomobject]@{ Success = $false; Status = 'CONFLICT'; Message = $message }
    }

    try {
        if (-not (Test-Path -LiteralPath $File.FullName -PathType Leaf)) {
            throw "Arquivo de origem não existe mais: $($File.FullName)"
        }

        $sourceHashBefore = Get-FileSha256 -Path $File.FullName
        Copy-Item -LiteralPath $File.FullName -Destination $temporaryPath -ErrorAction Stop
        $temporaryHash = Get-FileSha256 -Path $temporaryPath

        if ($sourceHashBefore -ne $temporaryHash) {
            throw 'A validação SHA-256 da cópia temporária falhou.'
        }

        if (Test-Path -LiteralPath $destinationPath) {
            throw "O destino foi criado por outro processo durante o transporte: $destinationPath"
        }

        # O arquivo só se torna visível para a VAN depois da cópia validada e da renomeação.
        [System.IO.File]::Move($temporaryPath, $destinationPath)

        $destinationHash = Get-FileSha256 -Path $destinationPath
        if ($sourceHashBefore -ne $destinationHash) {
            throw "A validação SHA-256 no destino falhou: $destinationPath"
        }

        try {
            Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
        }
        catch {
            $message = "Destino confirmado, mas não foi possível remover a origem. Requer reconciliação: $($_.Exception.Message)"
            Write-AdminEvent -ExecutionId $ExecutionId -Level ERROR -Message "Falha parcial para '$($File.Name)'. Origem='$($File.FullName)'; destino='$destinationPath'. $message" -Configuration $Configuration
            Write-BusinessEvent -Path $OperationalLogPath -ExecutionId $ExecutionId -Event 'TRANSPORT' -FileName $File.Name -Source $File.SourceName -Status 'PARTIAL' -Message $message -SourceOwner $File.SourceOwner -SourceShareHost $File.SourceShareHost
            return [pscustomobject]@{ Success = $false; Status = 'PARTIAL'; Message = $message }
        }

        $message = "Remessa disponibilizada no destino; origem removida após validação SHA-256."
        Write-AdminEvent -ExecutionId $ExecutionId -Level INFO -Message "Transporte concluído para '$($File.Name)': '$($File.FullName)' -> '$destinationPath'." -Configuration $Configuration
        Write-BusinessEvent -Path $OperationalLogPath -ExecutionId $ExecutionId -Event 'TRANSPORT' -FileName $File.Name -Source $File.SourceName -Status 'SUCCESS' -Message $message -SourceOwner $File.SourceOwner -SourceShareHost $File.SourceShareHost

        return [pscustomobject]@{ Success = $true; Status = 'SUCCESS'; Message = $message }
    }
    catch {
        $message = $_.Exception.Message

        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }

        # Se o destino definitivo já existir, não o excluímos: a VAN pode já tê-lo consumido.
        $destinationExists = Test-Path -LiteralPath $destinationPath
        $status = if ($destinationExists) { 'PARTIAL' } else { 'FAILED' }

        Write-AdminEvent -ExecutionId $ExecutionId -Level ERROR -Message "Falha no transporte de '$($File.Name)'. Origem preservada quando possível. Detalhe: $message" -Configuration $Configuration
        Write-BusinessEvent -Path $OperationalLogPath -ExecutionId $ExecutionId -Event 'TRANSPORT' -FileName $File.Name -Source $File.SourceName -Status $status -Message $message -SourceOwner $File.SourceOwner -SourceShareHost $File.SourceShareHost

        return [pscustomobject]@{ Success = $false; Status = $status; Message = $message }
    }
}
function Get-SourceOwner {
    <#
    .SYNOPSIS
    Obtém o proprietário ou a identidade disponível para o arquivo de origem.
    
    .DESCRIPTION
    Long description
    
    .PARAMETER Path
    Parameter description
    
    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    param([Parameter(Mandatory)][string]$Path)

    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        return $acl.Owner
    }
    catch {
        return $null
    }
}

Export-ModuleMember -Function   Get-ShareHost, `
                                Get-RemFiles, `
                                Get-FileShare256, `
                                Move-RemFileSafely, `
                                Get-SourceOwner