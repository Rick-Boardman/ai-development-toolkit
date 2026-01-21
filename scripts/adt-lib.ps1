Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AdtToolkitRoot {
    return (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
}

function Resolve-AdtProjectRoot {
    param([string]$ProjectRoot)

    if ($ProjectRoot -and $ProjectRoot.Trim().Length -gt 0) {
        return (Resolve-Path -LiteralPath $ProjectRoot).Path
    }

    # Default: assume toolkit is installed at <repoRoot>/_core/adt
    $toolkitRoot = Get-AdtToolkitRoot
    return (Resolve-Path -LiteralPath (Join-Path $toolkitRoot '..\..')).Path
}

function Write-AdtInfo {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host ("[ADT] {0}" -f $Message)
}

function New-AdtDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function New-AdtFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        $parent = Split-Path -Parent $Path
        if ($parent) {
            New-AdtDirectory -Path $parent
        }
        New-Item -ItemType File -Force -Path $Path | Out-Null
    }
}

function Add-AdtLineIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Line
    )

    New-AdtFile -Path $FilePath

    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { $content = '' }

    $pattern = "(?m)^\s*$([Regex]::Escape($Line))\s*$"
    if ($content -notmatch $pattern) {
        if ($content.Length -gt 0 -and $content[-1] -ne "`n") {
            Add-Content -LiteralPath $FilePath -Value ""
        }
        Add-Content -LiteralPath $FilePath -Value $Line
    }
}

function Read-AdtJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    } catch {
        throw "Failed to parse JSON: $Path. $($_.Exception.Message)"
    }
}

function Write-AdtJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Object
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-AdtDirectory -Path $parent
    }

    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-AdtJsonIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Object
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-AdtJson -Path $Path -Object $Object
        return $true
    }

    return $false
}

function Copy-AdtTemplateMissing {
    param(
        [Parameter(Mandatory = $true)][string]$TemplateDir,
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $TemplateDir)) {
        throw "Template directory not found: $TemplateDir"
    }

    $templateRoot = (Resolve-Path -LiteralPath $TemplateDir).Path
    $destRoot = (Resolve-Path -LiteralPath $ProjectDir -ErrorAction SilentlyContinue)
    if (-not $destRoot) {
        if (-not $DryRun) {
            New-AdtDirectory -Path $ProjectDir
        }
        $destRoot = (Resolve-Path -LiteralPath $ProjectDir -ErrorAction SilentlyContinue)
    }
    $destRootPath = if ($destRoot) { $destRoot.Path } else { $ProjectDir }

    # Ensure top-level folders exist
    if (-not $DryRun) {
        New-AdtDirectory -Path $destRootPath
    }

    # Recursively copy any missing files/dirs from template into the project.
    $items = Get-ChildItem -LiteralPath $templateRoot -Recurse -Force
    foreach ($item in $items) {
        $relative = $item.FullName.Substring($templateRoot.Length).TrimStart([char[]]'\\/')
        if (-not $relative) { continue }

        $destPath = Join-Path $destRootPath $relative

        if ($item.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $destPath)) {
                if ($DryRun) {
                    Write-AdtInfo "[dry-run] Would create directory: $destPath"
                } else {
                    New-AdtDirectory -Path $destPath
                }
            }
            continue
        }

        if (-not (Test-Path -LiteralPath $destPath)) {
            $destParent = Split-Path -Parent $destPath
            if ($destParent -and -not (Test-Path -LiteralPath $destParent)) {
                if ($DryRun) {
                    Write-AdtInfo "[dry-run] Would create directory: $destParent"
                } else {
                    New-AdtDirectory -Path $destParent
                }
            }

            if ($DryRun) {
                Write-AdtInfo "[dry-run] Would copy template file: $($item.FullName) -> $destPath"
            } else {
                Copy-Item -LiteralPath $item.FullName -Destination $destPath -Force
            }
        }
    }
}

function Get-AdtDefaultCapabilities {
    return [pscustomobject]@{
        schemaVersion = '20260121T000000Z'
        capabilities = [pscustomobject]@{
            autoMigrateSchema = $true
            driftRepair = 'safe'
            requireUpgradeIntent = $true
            coreModelEnabled = $true
            enforceCanonicalLeaves = 'warn'
        }
    }
}

function Ensure-AdtCapabilities {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [switch]$DryRun
    )

    $capPath = Join-Path (Join-Path $ProjectDir '_schema') 'capabilities.json'
    $defaultCaps = Get-AdtDefaultCapabilities

    if (-not (Test-Path -LiteralPath $capPath)) {
        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would create $capPath"
            return
        }

        Write-AdtJson -Path $capPath -Object $defaultCaps
        Write-AdtInfo 'Created .project/_schema/capabilities.json.'
    }
}

function Get-AdtCapabilities {
    param([Parameter(Mandatory = $true)][string]$ProjectDir)

    $capPath = Join-Path (Join-Path $ProjectDir '_schema') 'capabilities.json'
    $caps = Read-AdtJson -Path $capPath

    if (-not $caps) {
        $caps = Get-AdtDefaultCapabilities
    }

    return $caps
}

function Ensure-AdtState {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [switch]$DryRun
    )

    $stateDir = Join-Path $ProjectDir 'state'
    $statePath = Join-Path $stateDir 'adt-state.json'

    if (-not (Test-Path -LiteralPath $statePath)) {
        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would create $statePath"
            return
        }

        $state = [pscustomobject]@{
            toolkit = 'adt'
            bootstrapCompleted = $true
            lastBootstrapAt = (Get-Date).ToUniversalTime().ToString('o')
        }

        Write-AdtJson -Path $statePath -Object $state
        Write-AdtInfo 'Created .project/state/adt-state.json.'
    }
}

function Ensure-AdtProjectStructure {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [switch]$DryRun
    )

    $toolkitRoot = Get-AdtToolkitRoot
    $templateDir = Join-Path $toolkitRoot 'project-template'
    $projectDir = Join-Path $RepoRoot '.project'

    Copy-AdtTemplateMissing -TemplateDir $templateDir -ProjectDir $projectDir -DryRun:$DryRun

    Ensure-AdtCapabilities -ProjectDir $projectDir -DryRun:$DryRun
    Ensure-AdtState -ProjectDir $projectDir -DryRun:$DryRun

    # Scratchpad
    $scratchpad = Join-Path $RepoRoot '.scratchpad'
    if (-not (Test-Path -LiteralPath $scratchpad)) {
        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would create $scratchpad"
        } else {
            New-AdtDirectory -Path $scratchpad
        }
    }

    # Gitignore
    $gitignorePath = Join-Path $RepoRoot '.gitignore'
    if ($DryRun) {
        Write-AdtInfo "[dry-run] Would ensure .scratchpad/ is in $gitignorePath"
    } else {
        Add-AdtLineIfMissing -FilePath $gitignorePath -Line '.scratchpad/'
    }

    # Copilot instructions (best-effort; do not overwrite existing content)
    $githubDir = Join-Path $RepoRoot '.github'
    $copilotPath = Join-Path $githubDir 'copilot-instructions.md'
    if (-not (Test-Path -LiteralPath $githubDir)) {
        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would create $githubDir"
        } else {
            New-AdtDirectory -Path $githubDir
        }
    }

    if (-not (Test-Path -LiteralPath $copilotPath)) {
        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would create $copilotPath with ADT snippet"
        } else {
            New-AdtFile -Path $copilotPath
        }
    }

    # If snippet exists, add a bootstrap block only if no ADT reference exists.
    $snippetPath = Join-Path $toolkitRoot 'COPILOT-INSTRUCTIONS-SNIPPET.md'
    $snippet = $null
    if (Test-Path -LiteralPath $snippetPath) {
        $raw = Get-Content -LiteralPath $snippetPath -Raw
        $m = [regex]::Match($raw, '## Option A[^\n]*\n\s*```markdown\s*(?<body>[\s\S]*?)\s*```', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($m.Success) {
            $snippet = $m.Groups['body'].Value.Trim()
        }
    }

    $content = ''
    if (Test-Path -LiteralPath $copilotPath) {
        $content = Get-Content -LiteralPath $copilotPath -Raw
    }

    $hasAdt = ($content -match '(?i)\bADT\b' -or $content -match '_core/adt/INSTRUCTIONS\.md' -or $content -match '\.project/')
    if (-not $hasAdt -and $snippet) {
        $startMarker = '<!-- ADT BOOTSTRAP START -->'
        $endMarker = '<!-- ADT BOOTSTRAP END -->'
        $block = @(
            $startMarker,
            '',
            $snippet,
            '',
            '> **Stop Condition**: If you have not read `.project/now.md`, stop and read it before proceeding.',
            '',
            $endMarker,
            ''
        ) -join "`n"

        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would prepend ADT bootstrap block to $copilotPath"
        } else {
            Set-Content -LiteralPath $copilotPath -Value ($block + $content) -Encoding UTF8
        }
    }

    return $projectDir
}

function Invoke-AdtGit {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.WorkingDirectory = $RepoRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.Arguments = ($Arguments -join ' ')

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        Stdout = $stdout
        Stderr = $stderr
        Args = $Arguments
    }
}

function Get-AdtUtcNow {
    return (Get-Date).ToUniversalTime().ToString('o')
}

function Get-AdtMigrationStatePath {
    param([Parameter(Mandatory = $true)][string]$ProjectDir)
    $stateDir = Join-Path (Join-Path $ProjectDir '_schema') 'state'
    return (Join-Path $stateDir 'migrations.json')
}

function Read-AdtMigrationState {
    param([Parameter(Mandatory = $true)][string]$ProjectDir)

    $path = Get-AdtMigrationStatePath -ProjectDir $ProjectDir
    $state = Read-AdtJson -Path $path

    if (-not $state) {
        $state = [pscustomobject]@{
            schemaVersion = '20260121T000000Z'
            migrations = @()
        }
    }

    return $state
}

function Write-AdtMigrationState {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [Parameter(Mandatory = $true)]$State
    )

    $path = Get-AdtMigrationStatePath -ProjectDir $ProjectDir
    Write-AdtJson -Path $path -Object $State
}

function Find-AdtMigrationEntry {
    param(
        [Parameter(Mandatory = $true)]$MigrationState,
        [Parameter(Mandatory = $true)][string]$Id
    )

    foreach ($entry in $MigrationState.migrations) {
        if ($entry.id -eq $Id) {
            return $entry
        }
    }

    return $null
}

function Add-AdtMigrationLog {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [Parameter(Mandatory = $true)][string]$MigrationId,
        [Parameter(Mandatory = $true)][bool]$Changed,
        [Parameter(Mandatory = $true)][string]$Notes
    )

    $path = Join-Path (Join-Path $ProjectDir 'record') 'migrations.md'
    New-AdtFile -Path $path

    $today = (Get-Date).ToString('yyyy-MM-dd')
    $stamp = Get-AdtUtcNow

    $changedText = 'no'
    if ($Changed) { $changedText = 'yes' }

    $entry = @(
        "## $today",
        '',
        "- Migration: $MigrationId",
        ("- Changed: {0}" -f $changedText),
        "- Notes: $Notes",
        "- At: $stamp",
        ''
    ) -join "`n"

    $existing = Get-Content -LiteralPath $path -Raw
    Set-Content -LiteralPath $path -Value ($entry + $existing) -Encoding UTF8
}

function Invoke-AdtMigrations {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [switch]$DryRun,
        [switch]$Force
    )

    $migrationsDir = Join-Path (Join-Path $ProjectDir '_schema') 'migrations'
    if (-not (Test-Path -LiteralPath $migrationsDir)) {
        return
    }

    $state = Read-AdtMigrationState -ProjectDir $ProjectDir
    $scripts = Get-ChildItem -LiteralPath $migrationsDir -Filter '*.ps1' | Sort-Object Name

    foreach ($script in $scripts) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script.FullName).Hash
        $migrationId = [System.IO.Path]::GetFileNameWithoutExtension($script.Name)
        $existing = Find-AdtMigrationEntry -MigrationState $state -Id $migrationId
        $isNew = (-not $existing)

        $shouldRun = $Force
        if (-not $shouldRun) {
            if (-not $existing) {
                $shouldRun = $true
            } elseif ($existing.scriptHash -ne $hash) {
                $shouldRun = $true
            } elseif ($existing.succeeded -ne $true) {
                $shouldRun = $true
            }
        }

        if (-not $shouldRun) {
            continue
        }

        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would run migration $migrationId ($($script.Name))"
            continue
        }

        Write-AdtInfo "Running migration: $migrationId"
        $result = $null
        $succeeded = $true
        $failureMessage = $null

        try {
            $result = & $script.FullName -ProjectRoot $RepoRoot
        } catch {
            $succeeded = $false
            $failureMessage = $_.Exception.Message
        }

        $changed = $false
        $notes = ''

        if ($null -ne $result) {
            try {
                $changed = [bool]$result.changed
            } catch {
                $changed = $false
            }
            try {
                $notes = [string]$result.notes
            } catch {
                $notes = ''
            }
        } elseif (-not $succeeded -and $failureMessage) {
            $notes = "ERROR: $failureMessage"
        }

        if (-not $existing) {
            $existing = [pscustomobject]@{ id = $migrationId }
            $state.migrations += $existing
        }

        $existing | Add-Member -Force -NotePropertyName 'script' -NotePropertyValue $script.Name
        $existing | Add-Member -Force -NotePropertyName 'scriptHash' -NotePropertyValue $hash
        $existing | Add-Member -Force -NotePropertyName 'lastRunAt' -NotePropertyValue (Get-AdtUtcNow)
        $existing | Add-Member -Force -NotePropertyName 'succeeded' -NotePropertyValue $succeeded
        $existing | Add-Member -Force -NotePropertyName 'changed' -NotePropertyValue $changed
        $existing | Add-Member -Force -NotePropertyName 'notes' -NotePropertyValue $notes

        Write-AdtMigrationState -ProjectDir $ProjectDir -State $state

        if ($changed -or $isNew) {
            Add-AdtMigrationLog -ProjectDir $ProjectDir -MigrationId $migrationId -Changed:$changed -Notes $notes
        }

        if (-not $succeeded) {
            throw "Migration failed: $migrationId"
        }
    }
}

function Get-AdtCoreRoot {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    return (Join-Path $RepoRoot '_core')
}

function Get-AdtLeafMetadata {
    param([Parameter(Mandatory = $true)][string]$LeafDir)

    $leafPath = Join-Path (Join-Path $LeafDir '.core') 'leaf.json'
    if (-not (Test-Path -LiteralPath $leafPath)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $leafPath -Raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-AdtIndexMetadata {
    param([Parameter(Mandatory = $true)][string]$IndexDir)

    $indexPath = Join-Path (Join-Path $IndexDir '.core') 'index.json'
    if (-not (Test-Path -LiteralPath $indexPath)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Invoke-AdtCoreCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [Parameter(Mandatory = $true)]$Capabilities,
        [switch]$DryRun
    )

    $coreRoot = Get-AdtCoreRoot -RepoRoot $RepoRoot
    $catalogPath = Join-Path (Join-Path $ProjectDir 'state') 'core-catalog.json'

    $catalog = [pscustomobject]@{
        schemaVersion = '20260121T000000Z'
        generatedAt = Get-AdtUtcNow
        nodes = @()
        errors = @()
    }

    if (-not (Test-Path -LiteralPath $coreRoot)) {
        if ($Capabilities.capabilities.coreModelEnabled -eq $true) {
            $catalog.errors += "_core/ directory not found but coreModelEnabled=true"
        }

        if (-not $DryRun) {
            Write-AdtJson -Path $catalogPath -Object $catalog
        }

        return $catalog
    }

    $nodeDirs = Get-ChildItem -LiteralPath $coreRoot -Directory -Force

    foreach ($dir in $nodeDirs) {
        $id = $dir.Name
        $nodePath = $dir.FullName

        $leafMeta = Get-AdtLeafMetadata -LeafDir $nodePath
        $indexMeta = Get-AdtIndexMetadata -IndexDir $nodePath

        $kind = $null
        $meta = $null
        $nodeErrors = @()

        if ($leafMeta) {
            $kind = 'leaf'
            $meta = $leafMeta
        } elseif ($indexMeta) {
            $kind = 'index'
            $meta = $indexMeta
        } else {
            $kind = 'unknown'
            $nodeErrors += 'Missing .core/leaf.json or .core/index.json'
        }

        $catalog.nodes += [pscustomobject]@{
            id = $id
            path = "_core/$id"
            kind = $kind
            meta = $meta
            errors = $nodeErrors
        }
    }

    # Canonical leaf enforcement
    $mode = [string]$Capabilities.capabilities.enforceCanonicalLeaves
    foreach ($n in $catalog.nodes) {
        if ($n.kind -ne 'index') { continue }
        if (-not $n.meta) { continue }

        $canon = $n.meta.canonicalLeaves
        if (-not $canon) { continue }

        foreach ($leafId in $canon) {
            $exists = $false
            foreach ($candidate in $catalog.nodes) {
                if ($candidate.id -eq $leafId) { $exists = $true; break }
            }

            if (-not $exists) {
                $msg = "Index '$($n.id)' requires canonical leaf '$leafId' but it was not found under _core/"
                if ($mode -eq 'error') {
                    $catalog.errors += $msg
                } elseif ($mode -eq 'warn') {
                    $catalog.errors += "WARN: $msg"
                }
            }
        }
    }

    if ($DryRun) {
        Write-AdtInfo "[dry-run] Would write core catalog: $catalogPath"
    } else {
        Write-AdtJson -Path $catalogPath -Object $catalog
    }

    return $catalog
}

function Invoke-AdtUpgrade {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Leaf,
        [Parameter(Mandatory = $true)]$Capabilities,
        [switch]$DryRun,
        [switch]$NoVerify,
        [string]$IntentFile
    )

    $projectDir = Join-Path $RepoRoot '.project'
    $intentDir = Join-Path (Join-Path $projectDir 'record') 'upgrade-intents'

    $leafPath = $Leaf
    if ($leafPath -notmatch '[/\\]') {
        $leafPath = Join-Path (Join-Path $RepoRoot '_core') $Leaf
    } else {
        $leafPath = Join-Path $RepoRoot $Leaf
    }

    $leafRel = $leafPath.Replace($RepoRoot, '').TrimStart('\\').TrimStart('/')

    if ($Capabilities.capabilities.requireUpgradeIntent -eq $true) {
        $hasIntent = $false
        if ($IntentFile) {
            $intentAbs = Join-Path $RepoRoot $IntentFile
            $hasIntent = Test-Path -LiteralPath $intentAbs
        } elseif (Test-Path -LiteralPath $intentDir) {
            $matches = Get-ChildItem -LiteralPath $intentDir -Filter "*${Leaf}*.md" -ErrorAction SilentlyContinue
            $hasIntent = ($matches -and $matches.Count -gt 0)
        }

        if (-not $hasIntent) {
            throw "Upgrade intent required but not found. Create an intent in .project/record/upgrade-intents/ (or pass -IntentFile)."
        }
    }

    if ($DryRun) {
        Write-AdtInfo "[dry-run] Would update submodule: $leafRel"
        return
    }

    $before = Invoke-AdtGit -RepoRoot $RepoRoot -Arguments @('submodule','status', $leafRel)
    if ($before.ExitCode -ne 0) {
        throw "git submodule status failed for ${leafRel}: $($before.Stderr)"
    }

    Write-AdtInfo "Updating submodule: $leafRel"
    $update = Invoke-AdtGit -RepoRoot $RepoRoot -Arguments @('submodule','update','--remote','--merge', $leafRel)
    if ($update.ExitCode -ne 0) {
        throw "git submodule update failed for ${leafRel}: $($update.Stderr)"
    }

    $after = Invoke-AdtGit -RepoRoot $RepoRoot -Arguments @('submodule','status', $leafRel)

    $success = $true
    $verifyOutput = ''

    if (-not $NoVerify) {
        $leafMeta = Get-AdtLeafMetadata -LeafDir $leafPath
        if ($leafMeta -and $leafMeta.upgradeVerification -and $leafMeta.upgradeVerification.commands) {
            foreach ($cmd in $leafMeta.upgradeVerification.commands) {
                $shell = [string]$cmd.shell
                $command = [string]$cmd.command
                $command = $command.Replace('<repoRoot>', $RepoRoot)
                $command = $command.Replace('<leafPath>', $leafRel)

                Write-AdtInfo "Verifying ($($cmd.name))"

                try {
                    if ($shell -eq 'powershell') {
                        $out = & powershell -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1 | Out-String
                    } elseif ($shell -eq 'pwsh') {
                        $out = & pwsh -NoProfile -Command $command 2>&1 | Out-String
                    } elseif ($shell -eq 'cmd') {
                        $out = & cmd /c $command 2>&1 | Out-String
                    } else {
                        $out = & bash -lc $command 2>&1 | Out-String
                    }
                    $verifyOutput += $out
                } catch {
                    $success = $false
                    $verifyOutput += ($_.Exception.Message + "`n")
                    break
                }
            }
        }
    }

    if (-not $success) {
        Write-AdtInfo 'Verification failed; rolling back submodule pointer.'
        $null = Invoke-AdtGit -RepoRoot $RepoRoot -Arguments @('checkout','--', $leafRel)
        $null = Invoke-AdtGit -RepoRoot $RepoRoot -Arguments @('submodule','update','--init','--recursive', $leafRel)
    }

    # Record result
    $resultsDir = Join-Path (Join-Path $projectDir 'record') 'upgrade-results'
    New-AdtDirectory -Path $resultsDir

    $date = (Get-Date).ToString('yyyy-MM-dd')
    $resultPath = Join-Path $resultsDir ("{0}-{1}.md" -f $date, $Leaf)

    $body = @(
        "# Upgrade Result: $Leaf",
        '',
        "- Leaf path: $leafRel",
        "- At (UTC): $(Get-AdtUtcNow)",
        "- Before: $($before.Stdout.Trim())",
        "- After: $($after.Stdout.Trim())",
        "- Success: $($success)",
        '',
        '## Verification output',
        '```text',
        ($verifyOutput.Trim()),
        '```',
        ''
    ) -join "`n"

    Set-Content -LiteralPath $resultPath -Value $body -Encoding UTF8

    if (-not $success) {
        throw "Upgrade failed verification. See $resultPath"
    }

    Write-AdtInfo "Upgrade succeeded. Recorded: $resultPath"
}
