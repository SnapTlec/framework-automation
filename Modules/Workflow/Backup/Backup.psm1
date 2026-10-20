function New-ExecutionBackup {
    <#
    .SYNOPSIS
    Cria e valida o ZIP da execução e registra os resultados da compactação.
    
    .DESCRIPTION
    Long description
    
    .PARAMETER Files
    Parameter description
    
    .PARAMETER BackupRoot
    Parameter description
    
    .PARAMETER ExecutionId
    Parameter description
    
    .PARAMETER CompressionLogPath
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
        [Parameter(Mandatory)][object[]]$Files,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ExecutionId,
        [Parameter(Mandatory)][string]$CompressionLogPath,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Configuration
    )

    $now = Get-Date
    $backupDirectory = Join-Path $BackupRoot (Join-Path $now.ToString('yyyy') (Join-Path $now.ToString('MM') $now.ToString('dd')))
    $zipPath = Join-Path $backupDirectory ('remessas_{0}.zip' -f $ExecutionId)
    $tempZipPath = Join-Path $backupDirectory ('.remessas_{0}.tmp.zip' -f $ExecutionId)
    $allSucceeded = $false
    $failureMessage = $null

    try {
        New-Item -ItemType Directory -Path $backupDirectory -Force -ErrorAction Stop | Out-Null
        if (Test-Path -LiteralPath $zipPath) {
            throw "O arquivo de backup já existe e não será sobrescrito: $zipPath"
        }

        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $archive = [System.IO.Compression.ZipFile]::Open($tempZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($file in $Files) {
                if (-not (Test-Path -LiteralPath $file.FullName -PathType Leaf)) {
                    throw "A remessa deixou de existir antes da compactação: $($file.FullName)"
                }

                $sourceFolder = if ($file.IsRemote) { 'REMOTE' } else { 'SOURCE' }
                $entryName = '{0}/{1}' -f $sourceFolder, $file.Name
                $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
                $inputStream = [System.IO.File]::OpenRead($file.FullName)
                try {
                    $entryStream = $entry.Open()
                    try {
                        $inputStream.CopyTo($entryStream)
                    }
                    finally {
                        $entryStream.Dispose()
                    }
                }
                finally {
                    $inputStream.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }

        # Validar se o ZIP pode ser aberto e se contém todas as remessas esperadas.
        $checkArchive = [System.IO.Compression.ZipFile]::OpenRead($tempZipPath)
        try {
            if ($checkArchive.Entries.Count -ne $Files.Count) {
                throw "Quantidade de entradas inesperada no ZIP. Esperado=$($Files.Count); Encontrado=$($checkArchive.Entries.Count)"
            }
        }
        finally {
            $checkArchive.Dispose()
        }

        Move-Item -LiteralPath $tempZipPath -Destination $zipPath -ErrorAction Stop
        $allSucceeded = $true
    }
    catch {
        $failureMessage = $_.Exception.Message
        if (Test-Path -LiteralPath $tempZipPath) {
            Remove-Item -LiteralPath $tempZipPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $zipPath) {
            # Não remover um ZIP definitivo se o erro tiver ocorrido após sua criação.
            $failureMessage = "$failureMessage; verifique o artefato existente em $zipPath"
        }
    }

    foreach ($file in $Files) {
        $entryName = '{0}/{1}' -f $(if ($file.IsRemote) { 'REMOTE' } else { 'SOURCE' }), $file.Name
        $status = if ($allSucceeded) { 'SUCCESS' } else { 'FAILED' }
        $message = if ($allSucceeded) { 'Arquivo incluído e validado no backup da execução.' } else { $failureMessage }

        try {
            Write-BusinessEvent `
                -Path $CompressionLogPath `
                -ExecutionId $ExecutionId `
                -Event 'COMPRESSION' `
                -FileName $file.Name `
                -Source $file.SourceName `
                -Status $status `
                -Message $message `
                -ZipPath $(if ($allSucceeded) { $zipPath } else { $null }) `
                -ZipEntry $entryName `
                -SourceOwner $file.SourceOwner `
                -SourceShareHost $file.SourceShareHost
        }
        catch {
            Write-AdminEvent -ExecutionId $ExecutionId -Level ERROR -Message "Não foi possível gravar o log de compactação para '$($file.Name)': $($_.Exception.Message)" -Configuration $Configuration
        }
    }

    if ($allSucceeded) {
        Write-AdminEvent -ExecutionId $ExecutionId -Level INFO -Message "Backup concluído: '$zipPath'; arquivos=$($Files.Count)." -Configuration $Configuration
        return [pscustomobject]@{ Success = $true; Path = $zipPath; Error = $null }
    }

    Write-AdminEvent -ExecutionId $ExecutionId -Level WARN -Message "Backup falhou, mas o transporte continuará. Detalhe: $failureMessage" -Configuration $Configuration
    return [pscustomobject]@{ Success = $false; Path = $null; Error = $failureMessage }
}

Export-ModuleMember -Function New-ExecutionBackup