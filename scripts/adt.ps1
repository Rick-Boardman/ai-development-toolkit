[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [string]$ProjectRoot,

    # upgrade
    [string]$Leaf,
    [string]$IntentFile,
    [switch]$NoVerify,

    # common
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'adt-lib.ps1')

function Show-AdtHelp {
    Write-Host @'
ADT (Evergreen) CLI

Usage:
  powershell -ExecutionPolicy Bypass -File _core\adt\scripts\adt.ps1 <command> [options]

Commands:
  reconcile        Ensure structure, apply migrations (if enabled), update core catalog
  migrate          Run .project/_schema/migrations (idempotent)
  core             Rebuild .project/state/core-catalog.json
  upgrade          Upgrade a leaf submodule with intent+verify+record

Common options:
  -ProjectRoot <path>   Repo root (defaults to assuming _core/adt install)
  -DryRun               Show what would change without changing it

migrate options:
  -Force                Run all migrations (even if already applied)

upgrade options:
  -Leaf <name>          Leaf id (e.g. adt or core.vr.hud) OR path under repo
  -IntentFile <path>    Relative path to an intent file (optional)
  -NoVerify             Skip verification commands (not recommended)

Examples:
  powershell -ExecutionPolicy Bypass -File _core\adt\scripts\adt.ps1 reconcile
  powershell -ExecutionPolicy Bypass -File _core\adt\scripts\adt.ps1 migrate -Force
  powershell -ExecutionPolicy Bypass -File _core\adt\scripts\adt.ps1 upgrade -Leaf adt
'@
}

$repoRoot = Resolve-AdtProjectRoot -ProjectRoot $ProjectRoot
Write-AdtInfo "repo root = $repoRoot"

switch ($Command.ToLowerInvariant()) {
    'help' { Show-AdtHelp; exit 0 }

    'reconcile' {
        $projectDir = Ensure-AdtProjectStructure -RepoRoot $repoRoot -DryRun:$DryRun
        $caps = Get-AdtCapabilities -ProjectDir $projectDir

        if ($caps.capabilities.autoMigrateSchema -eq $true) {
            Invoke-AdtMigrations -RepoRoot $repoRoot -ProjectDir $projectDir -DryRun:$DryRun -Force:$Force
        }

        if ($caps.capabilities.coreModelEnabled -eq $true) {
            $null = Invoke-AdtCoreCatalog -RepoRoot $repoRoot -ProjectDir $projectDir -Capabilities $caps -DryRun:$DryRun
        }

        Write-AdtInfo 'reconcile complete.'
        exit 0
    }

    'migrate' {
        $projectDir = Ensure-AdtProjectStructure -RepoRoot $repoRoot -DryRun:$DryRun
        Invoke-AdtMigrations -RepoRoot $repoRoot -ProjectDir $projectDir -DryRun:$DryRun -Force:$Force
        Write-AdtInfo 'migrate complete.'
        exit 0
    }

    'core' {
        $projectDir = Ensure-AdtProjectStructure -RepoRoot $repoRoot -DryRun:$DryRun
        $caps = Get-AdtCapabilities -ProjectDir $projectDir
        $null = Invoke-AdtCoreCatalog -RepoRoot $repoRoot -ProjectDir $projectDir -Capabilities $caps -DryRun:$DryRun
        Write-AdtInfo 'core catalog updated.'
        exit 0
    }

    'upgrade' {
        if (-not $Leaf) {
            throw 'Missing -Leaf. Example: -Leaf adt'
        }

        $projectDir = Ensure-AdtProjectStructure -RepoRoot $repoRoot -DryRun:$DryRun
        $caps = Get-AdtCapabilities -ProjectDir $projectDir
        Invoke-AdtUpgrade -RepoRoot $repoRoot -Leaf $Leaf -Capabilities $caps -DryRun:$DryRun -NoVerify:$NoVerify -IntentFile $IntentFile
        exit 0
    }

    default {
        Show-AdtHelp
        throw "Unknown command: $Command"
    }
}
