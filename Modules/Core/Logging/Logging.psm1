
$script:LogWriter = $null
$script:LogPath = $null

function Start-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        if ($null -ne $script:LogWriter) {
            $script:LogWriter.Dispose()
            $script:LogWriter = $null
        }

        $resolvedPath = $ExecutionContext.SessionState.Path.
            GetUnresolvedProviderPathFromPSPath($Path)

        if ([System.IO.Path]::GetExtension($resolvedPath) -ieq '.log') {
            $logFile = $resolvedPath
            $logDirectory = [System.IO.Path]::GetDirectoryName($logFile)
        }
        else {
            $logDirectory = $resolvedPath
            $logFile = Join-Path -Path $logDirectory -ChildPath (
                "$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            )
        }

        if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
            New-Item -Path $logDirectory -ItemType Directory -Force `
                -ErrorAction Stop | Out-Null
        }

        $encoding = [System.Text.UTF8Encoding]::new($false)

        $stream = [System.IO.FileStream]::new(
            $logFile,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )

        $script:LogWriter = [System.IO.StreamWriter]::new(
            $stream,
            $encoding
        )

        $script:LogWriter.AutoFlush = $true
        $script:LogPath = $logFile

        Write-Log -Level INFO -Message "Log iniciado: $logFile"

        return $logFile
    }
    catch {
        if ($null -ne $script:LogWriter) {
            $script:LogWriter.Dispose()
            $script:LogWriter = $null
        }

        $script:LogPath = $null

        throw "Falha ao inicializar o log: $($_.Exception.Message)"
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'WARNING', 'ERROR', 'FATAL')]
        [string]$Level,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $normalizedLevel = if ($Level -eq 'WARNING') {
        'WARN'
    }
    else {
        $Level
    }

    $entry = "[$timestamp] [$normalizedLevel] $Message"

    switch ($normalizedLevel) {
        'DEBUG' { $color = 'Gray' }
        'INFO'  { $color = 'Cyan' }
        'WARN'  { $color = 'Yellow' }
        'ERROR' { $color = 'Red' }
        'FATAL' { $color = 'Magenta' }
        default { $color = 'White' }
    }

    Write-Host $entry -ForegroundColor $color

    if ($null -ne $script:LogWriter) {
        try {
            $script:LogWriter.WriteLine($entry)
        }
        catch {
            throw "Falha ao gravar no log '$script:LogPath': $($_.Exception.Message)"
        }
    }

    return
}

function Write-AdminEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExecutionId,
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [System.Collections.IDictionary]$Configuration
    )

    $line = '{0} [{1}] executionId={2} {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $ExecutionId, $Message
    $logger = Get-Command -Name Write-Log -ErrorAction SilentlyContinue

    if ($logger) {
        try {
            Write-Log -Level $Level -Message $line
            return
        }
        catch {
            # Fallback local caso o módulo compartilhado de logging falhe.
        }
    }

    if ($Configuration -and $Configuration.Contains('ADMIN_LOG_DIR')) {
        try {
            $fallbackPath = Join-Path $Configuration['ADMIN_LOG_DIR'] ('Pagamento-Escritural-VAN-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
            Add-Content -LiteralPath $fallbackPath -Value $line -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Error "Não foi possível registrar o log administrativo. Evento original: $line. Falha de logging: $($_.Exception.Message)"
        }
    }
}

function Write-BusinessEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExecutionId,
        [Parameter(Mandatory)][string]$Event,
        [string]$FileName,
        [string]$Source,
        [string]$Status,
        [string]$Message,
        [string]$ZipPath,
        [string]$ZipEntry,
        [string]$SourceOwner,
        [string]$SourceShareHost
    )

    $record = [ordered]@{
        timestamp      = (Get-Date).ToString('o')
        executionId    = $ExecutionId
        event          = $Event
        fileName       = $FileName
        source         = $Source
        status         = $Status
        message        = $Message
        zipPath        = $ZipPath
        zipEntry       = $ZipEntry
        sourceOwner    = $SourceOwner
        sourceShareHost= $SourceShareHost
    }
    Add-JsonLine -Path $Path -Record $record
}

function Stop-Log {
    [CmdletBinding()]
    param()

    if ($null -ne $script:LogWriter) {
        try {
            $script:LogWriter.Flush()
            $script:LogWriter.Dispose()
        }
        finally {
            $script:LogWriter = $null
            $script:LogPath = $null
        }
    }

    return
}

function Add-JsonLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Record
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    }

    $mutexName = 'Local\PSI_' + ([System.Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant())) | ForEach-Object { $_.ToString('x2') } | Join-String -Separator '')
    # Join-String is unavailable on Windows PowerShell 5.1; build a portable mutex name below.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant()))
        $mutexSuffix = ([BitConverter]::ToString($hashBytes)).Replace('-', '').Substring(0, 24)
    }
    finally {
        $sha.Dispose()
    }
    $mutexName = 'Local\PSI_' + $mutexSuffix
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $locked = $false

    try {
        try {
            $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(10))
        }
        catch [System.Threading.AbandonedMutexException] {
            $locked = $true
        }

        if (-not $locked) {
            throw "Tempo esgotado aguardando bloqueio para gravar log: $Path"
        }

        $json = ($Record | ConvertTo-Json -Depth 8 -Compress)
        $encoding = New-Object System.Text.UTF8Encoding($false)
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read
        )
        try {
            $writer = New-Object System.IO.StreamWriter($stream, $encoding)
            try {
                $writer.WriteLine($json)
                $writer.Flush()
            }
            finally {
                $writer.Dispose()
            }
        }
        finally {
            if ($stream) { $stream.Dispose() }
        }
    }
    finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

Export-ModuleMember -Function   Start-Log, `
                                Write-Log, `
                                Stop-Log, `
                                Write-AdminEvent, `
                                Write-BusinessEvent, `
                                Add-JsonLine

