
using module "..\Modules\Entity\Manifest.psm1"

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Service,

    [Parameter()]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [Parameter(Mandatory)]
    [ValidateSet(
        'Desenvolvimento',
        'Homologacao',
        'Producao'
    )]
    [string]$Enviromnet
)

$ErrorActionPreference = 'Stop'

$PROJECT_ROOT = if ($HOME_PROJECT) {
    (Resolve-Path -LiteralPath $HOME_PROJECT).Path
}
else {
    (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

$SERVICES_ROOT = Join-Path $PROJECT_ROOT 'Services'
$MODULES_ROOT = Join-Path $PROJECT_ROOT 'Modules'
$OUTPUT_BUILD = Join-Path $PSScriptRoot 'Artifacts'

Import-Module (Join-Path $MODULES_ROOT 'Core\Configuration\Configuration.psm1') -Force

function Resolve-ModuleReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Reference,

        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$ModulesRoot,

        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $referencePath = $Reference.Trim()

    $sourceDirectory = Split-Path -Parent $SourcePath

    $referencePath = $referencePath.Replace(
        '$PSScriptRoot',
        $sourceDirectory
    )

    $referencePath = $referencePath.Replace(
        '$HOME_PROJECT',
        $ProjectRoot
    )

    $hasPath = (
        [System.IO.Path]::IsPathRooted($referencePath) -or
        $referencePath.Contains('\') -or
        $referencePath.Contains('/') -or
        $referencePath.EndsWith('.psm1', [StringComparison]::OrdinalIgnoreCase)
    )

    if ($hasPath) {
        if (-not [System.IO.Path]::IsPathRooted($referencePath)) {
            $referencePath = Join-Path $sourceDirectory $referencePath
        }

        if (-not (Test-Path -LiteralPath $referencePath -PathType Leaf)) {
            throw "Dependência não encontrada: '$Reference', referenciada por '$SourcePath'."
        }

        $resolvedPath = (Resolve-Path -LiteralPath $referencePath).Path
    }
    else {
        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension(
            $referencePath
        )

        $matches = @(
            Get-ChildItem -LiteralPath $ModulesRoot `
                -Filter "$moduleName.psm1" `
                -File `
                -Recurse
        )

        if ($matches.Count -eq 0) {
            $builtInModule = Get-Module -ListAvailable -Name $moduleName |
                Where-Object {
                    $_.ModuleBase.StartsWith(
                        "$PSHOME\Modules",
                        [StringComparison]::OrdinalIgnoreCase
                    )
                } |
                Select-Object -First 1

            if ($null -ne $builtInModule) {
                return $null
            }

            throw "Módulo '$moduleName' não encontrado em '$ModulesRoot'. Origem: '$SourcePath'."
        }

        if ($matches.Count -gt 1) {
            throw "O módulo '$moduleName' é ambíguo. Use um caminho explícito na referência '$Reference'."
        }

        $resolvedPath = $matches[0].FullName
    }

    $modulesRootFull = [System.IO.Path]::GetFullPath($ModulesRoot).
        TrimEnd('\', '/') + '\'

    if (-not $resolvedPath.StartsWith(
        $modulesRootFull,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "O módulo '$resolvedPath' está fora do diretório de módulos do projeto."
    }

    return $resolvedPath
}

function Get-ModuleReferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $tokens = $null
    $parseErrors = $null

    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if ($parseErrors.Count -gt 0) {
        $details = $parseErrors |
            ForEach-Object { $_.Message }

        throw "Erro de sintaxe no módulo '$Path': $($details -join '; ')"
    }

    $references = [System.Collections.Generic.List[string]]::new()

    $usingStatements = $ast.FindAll(
        {
            param($node)

            $node -is [System.Management.Automation.Language.UsingStatementAst] -and
            $node.UsingStatementKind -eq
                [System.Management.Automation.Language.UsingStatementKind]::Module
        },
        $true
    )

    foreach ($statement in $usingStatements) {
        if (-not [string]::IsNullOrWhiteSpace($statement.Name)) {
            $references.Add($statement.Name)
        }
    }

    $commands = $ast.FindAll(
        {
            param($node)

            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Import-Module'
        },
        $true
    )

    foreach ($command in $commands) {
        $reference = $null

        foreach ($element in $command.CommandElements | Select-Object -Skip 1) {
            if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                continue
            }

            if (
                $element -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                $element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
            ) {
                $reference = $element.Value
                break
            }

            throw "Import-Module com referência dinâmica não suportada em '$Path'. Utilize um nome literal ou um caminho baseado em `$PSScriptRoot."
        }

        if ([string]::IsNullOrWhiteSpace($reference)) {
            throw "Não foi possível resolver um Import-Module em '$Path'."
        }

        $references.Add($reference)
    }

    return $references.ToArray()
}

function Resolve-ModuleDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$InitialModules,

        [Parameter(Mandatory)]
        [string]$ModulesRoot,

        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $resolvedModules = [System.Collections.Generic.Dictionary[string, string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    $pendingModules = [System.Collections.Generic.Queue[object]]::new()

    foreach ($module in $InitialModules) {
        $pendingModules.Enqueue(
            [PSCustomObject]@{
                Reference  = $module
                SourcePath = Join-Path $ProjectRoot 'Services\Manifest.psd1'
            }
        )
    }

    while ($pendingModules.Count -gt 0) {
        $item = $pendingModules.Dequeue()

        $modulePath = Resolve-ModuleReference `
            -Reference $item.Reference `
            -SourcePath $item.SourcePath `
            -ModulesRoot $ModulesRoot `
            -ProjectRoot $ProjectRoot

        if ($null -eq $modulePath) {
            continue
        }

        if ($resolvedModules.ContainsKey($modulePath)) {
            continue
        }

        $resolvedModules.Add($modulePath, $modulePath)

        Write-Host "Dependência identificada: $modulePath"

        $references = Get-ModuleReferences -Path $modulePath

        foreach ($reference in $references) {
            $pendingModules.Enqueue(
                [PSCustomObject]@{
                    Reference  = $reference
                    SourcePath = $modulePath
                }
            )
        }
    }

    return @($resolvedModules.Values)
}

function Copy-ModuleToPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [string]$ModulesRoot,

        [Parameter(Mandatory)]
        [string]$PackageModulesRoot
    )

    $modulesRootFull = [System.IO.Path]::GetFullPath($ModulesRoot).
        TrimEnd('\', '/') + '\'

    $relativePath = $ModulePath.Substring(
        $modulesRootFull.Length
    )

    $destinationPath = Join-Path $PackageModulesRoot $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath

    New-Item -ItemType Directory `
        -Path $destinationDirectory `
        -Force | Out-Null

    Copy-Item -LiteralPath $ModulePath `
        -Destination $destinationPath `
        -Force

    $moduleManifest = [System.IO.Path]::ChangeExtension(
        $ModulePath,
        '.psd1'
    )

    if (Test-Path -LiteralPath $moduleManifest -PathType Leaf) {
        Copy-Item -LiteralPath $moduleManifest `
            -Destination $destinationDirectory `
            -Force
    }

    return $destinationPath
}

$stagingRoot = $null

try {
    $servicePath = Join-Path $SERVICES_ROOT $Service

    if (-not (Test-Path -LiteralPath $servicePath -PathType Container)) {
        throw "Serviço '$Service' não encontrado em '$SERVICES_ROOT'."
    }

    $manifestPath = Join-Path $servicePath 'Manifest.psd1'

    $response = Get-Configuration -Path $manifestPath

    if (-not $response.Status) {
        throw "Manifesto inválido: $($response.Messages -join '; ')"
    }

    $manifest = [Manifest]$response.Data

    if ([string]::IsNullOrWhiteSpace($manifest.Version)) {
        throw "O manifesto do serviço '$Service' não define uma versão."
    }

    $effectiveVersion = if ([string]::IsNullOrWhiteSpace($Version)) {
        $manifest.Version
    }
    else {
        $Version
    }

    $mainFiles = @(
        'Main.psm1'
        'Runner.ps1'
        "Appsettings.$Enviromnet.psd1"
        'README.md'
    )

    foreach ($file in $mainFiles) {
        $filePath = Join-Path $servicePath $file

        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "Arquivo obrigatório não encontrado: '$filePath'."
        }
    }

    if (-not (Test-Path -LiteralPath $OUTPUT_BUILD -PathType Container)) {
        New-Item -ItemType Directory -Path $OUTPUT_BUILD -Force |
            Out-Null
    }

    $resolvedModules = Resolve-ModuleDependencies `
        -InitialModules $manifest.RequiredModules `
        -ModulesRoot $MODULES_ROOT `
        -ProjectRoot $PROJECT_ROOT

    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        "PowerShellBuild_$([guid]::NewGuid().ToString('N'))"
    )

    $packageRoot = Join-Path $stagingRoot $Service
    $packageModulesRoot = Join-Path $packageRoot 'Modules'

    New-Item -ItemType Directory -Path $packageModulesRoot -Force |
        Out-Null

    foreach ($modulePath in $resolvedModules) {
        Copy-ModuleToPackage `
            -ModulePath $modulePath `
            -ModulesRoot $MODULES_ROOT `
            -PackageModulesRoot $packageModulesRoot |
            Out-Null
    }

    foreach ($file in $mainFiles) {
        Copy-Item `
            -LiteralPath (Join-Path $servicePath $file) `
            -Destination $packageRoot `
            -Force
    }

    $nameFileZip = "$Service.$effectiveVersion.zip"
    $fullPath = Join-Path $OUTPUT_BUILD $nameFileZip

    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Force
    }

    Compress-Archive `
        -Path (Join-Path $packageRoot '*') `
        -DestinationPath $fullPath `
        -CompressionLevel Optimal `
        -ErrorAction Stop

    $hash = Get-FileHash -LiteralPath $fullPath -Algorithm SHA256

    $hashPath = "$fullPath.sha256"

    Set-Content `
        -LiteralPath $hashPath `
        -Value "$($hash.Hash)  $nameFileZip" `
        -Encoding ASCII

    Write-Host "Build concluído: $fullPath"
    Write-Host "SHA-256: $($hash.Hash)"

    return [PSCustomObject]@{
        Service     = $Service
        Version     = $effectiveVersion
        Artifact    = $fullPath
        HashFile    = $hashPath
        SHA256      = $hash.Hash
        Dependencies = $resolvedModules.Count
        Status      = 'Success'
    }
}
catch {
    Write-Error "Falha no build de '$Service': $($_.Exception.Message)"
    throw
}
finally {
    if (
        $null -ne $stagingRoot -and
        (Test-Path -LiteralPath $stagingRoot)
    ) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
