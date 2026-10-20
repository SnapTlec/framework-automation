function Test-DirectoryWritable {
    <#
    .SYNOPSIS
    Valida diretórios e permissões de escrita.
    
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

    $testPath = Join-Path $Path ('.integration-write-test-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    try {
        $stream = [System.IO.File]::Open(
            $testPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $stream.Dispose()
        Remove-Item -LiteralPath $testPath -Force -ErrorAction Stop
        return $true
    }
    catch {
        if (Test-Path -LiteralPath $testPath) {
            Remove-Item -LiteralPath $testPath -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

Export-ModuleMember -Function Test-DirectoryWritable