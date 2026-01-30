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
    }
    catch {
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

function Get-AdtSchemasRoot {
    return (Join-Path (Get-AdtToolkitRoot) 'schemas')
}

function Get-AdtSchemaPath {
    param([Parameter(Mandatory = $true)][string]$SchemaFileName)

    return (Join-Path (Get-AdtSchemasRoot) $SchemaFileName)
}

function Get-AdtJsonTypeName {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) { return 'null' }

    if ($Value -is [string]) { return 'string' }
    if ($Value -is [bool]) { return 'boolean' }
    if ($Value -is [int] -or $Value -is [long]) { return 'integer' }
    if ($Value -is [double] -or $Value -is [decimal] -or $Value -is [float]) { return 'number' }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) { return 'array' }

    # ConvertFrom-Json returns PSCustomObject for objects.
    return 'object'
}

function Test-AdtValueAgainstSchema {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)]$Schema,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $errors = @()

    if ($Schema.PSObject.Properties.Name -contains 'const') {
        if ($Value -ne $Schema.const) {
            $errors += "$Path must equal '$($Schema.const)'"
        }
        return $errors
    }

    if ($Schema.PSObject.Properties.Name -contains 'enum') {
        $ok = $false
        foreach ($v in $Schema.enum) {
            if ($Value -eq $v) { $ok = $true; break }
        }
        if (-not $ok) {
            $errors += "$Path must be one of: $([string]::Join(', ', $Schema.enum))"
        }
        return $errors
    }

    if ($Schema.PSObject.Properties.Name -contains 'type') {
        $expected = [string]$Schema.type
        $actual = Get-AdtJsonTypeName -Value $Value
        $typeOk = $true

        if ($expected -eq 'number') {
            $typeOk = ($actual -eq 'number' -or $actual -eq 'integer')
        }
        else {
            $typeOk = ($actual -eq $expected)
        }

        if (-not $typeOk) {
            $errors += "$Path must be a $expected (got $actual)"
            return $errors
        }
    }

    $minLength = $null
    if ($Schema.PSObject.Properties.Name -contains 'minLength') {
        $minLength = [int]$Schema.minLength
    }
    if ($minLength -ne $null -and $Value -is [string]) {
        if ($Value.Length -lt $minLength) {
            $errors += "$Path must be at least $minLength characters"
        }
    }

    $valueType = Get-AdtJsonTypeName -Value $Value
    if ($valueType -eq 'object') {
        $propNames = @()
        foreach ($p in $Value.PSObject.Properties) {
            $propNames += $p.Name
        }

        if ($Schema.PSObject.Properties.Name -contains 'required') {
            foreach ($req in $Schema.required) {
                if (-not ($propNames -contains $req)) {
                    $errors += "$Path.$req is required"
                }
            }
        }

        $additionalProperties = $true
        if ($Schema.PSObject.Properties.Name -contains 'additionalProperties') {
            $additionalProperties = [bool]$Schema.additionalProperties
        }

        $schemaProps = $null
        if ($Schema.PSObject.Properties.Name -contains 'properties') {
            $schemaProps = $Schema.properties
        }

        if (-not $additionalProperties -and $schemaProps) {
            foreach ($pn in $propNames) {
                if (-not ($schemaProps.PSObject.Properties.Name -contains $pn)) {
                    $errors += "$Path.$pn is not allowed"
                }
            }
        }

        if ($schemaProps) {
            foreach ($prop in $schemaProps.PSObject.Properties) {
                $pn = $prop.Name
                if ($propNames -contains $pn) {
                    $child = $Value.$pn
                    $errors += Test-AdtValueAgainstSchema -Value $child -Schema $schemaProps.$pn -Path ("$Path.$pn")
                }
            }
        }
    }
    elseif ($valueType -eq 'array') {
        if ($Schema.PSObject.Properties.Name -contains 'items') {
            $i = 0
            foreach ($item in $Value) {
                $errors += Test-AdtValueAgainstSchema -Value $item -Schema $Schema.items -Path ("$Path[$i]")
                $i++
            }
        }
    }

    return $errors
}

function Test-AdtJsonAgainstSchema {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )

    if (-not (Test-Path -LiteralPath $InstancePath)) {
        return [pscustomobject]@{ ok = $false; errors = @("File not found: $InstancePath") }
    }
    if (-not (Test-Path -LiteralPath $SchemaPath)) {
        return [pscustomobject]@{ ok = $false; errors = @("Schema not found: $SchemaPath") }
    }

    $instance = Read-AdtJson -Path $InstancePath
    $schema = Read-AdtJson -Path $SchemaPath

    if (-not $schema) {
        return [pscustomobject]@{ ok = $false; errors = @("Failed to load schema: $SchemaPath") }
    }

    $errs = @(Test-AdtValueAgainstSchema -Value $instance -Schema $schema -Path '$')
    return [pscustomobject]@{ ok = ($errs.Count -eq 0); errors = $errs }
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
                }
                else {
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
                }
                else {
                    New-AdtDirectory -Path $destParent
                }
            }

            if ($DryRun) {
                Write-AdtInfo "[dry-run] Would copy template file: $($item.FullName) -> $destPath"
            }
            else {
                Copy-Item -LiteralPath $item.FullName -Destination $destPath -Force
            }
        }
    }
}

function Get-AdtDefaultCapabilities {
    return [pscustomobject]@{
        schemaVersion = '20260121T000000Z'
        capabilities  = [pscustomobject]@{
            autoMigrateSchema      = $true
            driftRepair            = 'safe'
            requireUpgradeIntent   = $true
            coreModelEnabled       = $true
            enforceCanonicalLeaves = 'warn'
            schemaValidation       = 'warn'
            dependencyEnforcement  = 'warn'
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
            toolkit            = 'adt'
            bootstrapCompleted = $true
            lastBootstrapAt    = (Get-Date).ToUniversalTime().ToString('o')
        }

        Write-AdtJson -Path $statePath -Object $state
        Write-AdtInfo 'Created .project/state/adt-state.json.'
    }
}

function Ensure-AdtProjectScaffold {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [switch]$DryRun
    )

    $projectDir = Join-Path $RepoRoot '.project'
    if (-not (Test-Path -LiteralPath $projectDir)) {
        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would create $projectDir"
        }
        else {
            New-AdtDirectory -Path $projectDir
        }
    }

    Ensure-AdtCapabilities -ProjectDir $projectDir -DryRun:$DryRun
    Ensure-AdtState -ProjectDir $projectDir -DryRun:$DryRun
    return $projectDir
}

function Invoke-AdtSchemaValidation {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [Parameter(Mandatory = $true)]$Capabilities,
        [switch]$ThrowOnError
    )

    $mode = 'warn'
    try {
        if ($Capabilities -and $Capabilities.capabilities -and $Capabilities.capabilities.schemaValidation) {
            $mode = [string]$Capabilities.capabilities.schemaValidation
        }
    }
    catch { }

    if ($mode -eq 'off') {
        return @()
    }

    $errors = @()

    # Capabilities
    $capPath = Join-Path (Join-Path $ProjectDir '_schema') 'capabilities.json'
    $capSchema = Get-AdtSchemaPath -SchemaFileName 'project.capabilities.schema.json'
    $capRes = Test-AdtJsonAgainstSchema -InstancePath $capPath -SchemaPath $capSchema
    if (-not $capRes.ok) {
        foreach ($e in $capRes.errors) { $errors += "capabilities.json: $e" }
    }

    # Dependencies state (if present)
    $depsPath = Join-Path (Join-Path $ProjectDir 'state') 'dependencies.json'
    if (Test-Path -LiteralPath $depsPath) {
        $depsSchema = Get-AdtSchemaPath -SchemaFileName 'project.dependencies.schema.json'
        $depsRes = Test-AdtJsonAgainstSchema -InstancePath $depsPath -SchemaPath $depsSchema
        if (-not $depsRes.ok) {
            foreach ($e in $depsRes.errors) { $errors += "dependencies.json: $e" }
        }
    }

    # Core node metadata
    $coreRoot = Join-Path $RepoRoot '_core'
    if (Test-Path -LiteralPath $coreRoot) {
        $leafSchema = Get-AdtSchemaPath -SchemaFileName 'core.leaf.schema.json'
        $indexSchema = Get-AdtSchemaPath -SchemaFileName 'core.index.schema.json'

        $metaFiles = Get-ChildItem -LiteralPath $coreRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\.core\\\\(leaf|index)\.json$" }

        foreach ($f in $metaFiles) {
            $schemaPath = $indexSchema
            if ($f.Name -eq 'leaf.json') { $schemaPath = $leafSchema }
            $res = Test-AdtJsonAgainstSchema -InstancePath $f.FullName -SchemaPath $schemaPath
            if (-not $res.ok) {
                foreach ($e in $res.errors) { $errors += "${($f.FullName.Replace($RepoRoot, '').TrimStart('\\','/'))}: $e" }
            }
        }
    }

    if ($errors.Count -gt 0) {
        foreach ($e in $errors) {
            if ($mode -eq 'warn') {
                Write-AdtInfo "WARN: schema validation: $e"
            }
        }

        if ($mode -eq 'error' -or $ThrowOnError) {
            throw "Schema validation failed with $($errors.Count) error(s)."
        }
    }

    return $errors
}

function Invoke-AdtDriftRepair {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [Parameter(Mandatory = $true)]$Capabilities,
        [switch]$DryRun
    )

    $mode = 'safe'
    try {
        if ($Capabilities -and $Capabilities.capabilities -and $Capabilities.capabilities.driftRepair) {
            $mode = [string]$Capabilities.capabilities.driftRepair
        }
    }
    catch { }

    if ($mode -eq 'off') {
        return
    }

    $toolkitRoot = Get-AdtToolkitRoot
    $templateDir = Join-Path $toolkitRoot 'project-template'
    Copy-AdtTemplateMissing -TemplateDir $templateDir -ProjectDir $ProjectDir -DryRun:$DryRun

    # Project-side safe drift repair only (do NOT modify submodules under _core).
    $scratchpad = Join-Path $RepoRoot '.scratchpad'
    if (-not (Test-Path -LiteralPath $scratchpad)) {
        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would create $scratchpad"
        }
        else {
            New-AdtDirectory -Path $scratchpad
        }
    }

    $gitignorePath = Join-Path $RepoRoot '.gitignore'
    if ($DryRun) {
        Write-AdtInfo "[dry-run] Would ensure .scratchpad/ is in $gitignorePath"
    }
    else {
        Add-AdtLineIfMissing -FilePath $gitignorePath -Line '.scratchpad/'
    }

    $githubDir = Join-Path $RepoRoot '.github'
    $copilotPath = Join-Path $githubDir 'copilot-instructions.md'
    if (-not (Test-Path -LiteralPath $githubDir)) {
        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would create $githubDir"
        }
        else {
            New-AdtDirectory -Path $githubDir
        }
    }
    if (-not (Test-Path -LiteralPath $copilotPath)) {
        if ($DryRun) {
            Write-AdtInfo "[dry-run] Would create $copilotPath with ADT snippet"
        }
        else {
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
        }
        else {
            Set-Content -LiteralPath $copilotPath -Value ($block + $content) -Encoding UTF8
        }
    }
}

function Ensure-AdtProjectStructure {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [switch]$DryRun
    )

    $projectDir = Ensure-AdtProjectScaffold -RepoRoot $RepoRoot -DryRun:$DryRun
    $caps = Get-AdtCapabilities -ProjectDir $projectDir
    Invoke-AdtDriftRepair -RepoRoot $RepoRoot -ProjectDir $projectDir -Capabilities $caps -DryRun:$DryRun

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
        Stdout   = $stdout
        Stderr   = $stderr
        Args     = $Arguments
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
            migrations    = @()
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
            }
            elseif ($existing.scriptHash -ne $hash) {
                $shouldRun = $true
            }
            elseif ($existing.succeeded -ne $true) {
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
        }
        catch {
            $succeeded = $false
            $failureMessage = $_.Exception.Message
        }

        $changed = $false
        $notes = ''

        if ($null -ne $result) {
            try {
                $changed = [bool]$result.changed
            }
            catch {
                $changed = $false
            }
            try {
                $notes = [string]$result.notes
            }
            catch {
                $notes = ''
            }
        }
        elseif (-not $succeeded -and $failureMessage) {
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

function Get-AdtRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $basePath = (Resolve-Path -LiteralPath $Base).Path
    $full = (Resolve-Path -LiteralPath $FullPath).Path
    if ($full.StartsWith($basePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($basePath.Length).TrimStart([char[]]@('\', '/'))
    }
    return $FullPath
}

function Find-AdtCoreNodes {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $coreRoot = Get-AdtCoreRoot -RepoRoot $RepoRoot
    if (-not (Test-Path -LiteralPath $coreRoot)) {
        return @()
    }

    $dirs = Get-ChildItem -LiteralPath $coreRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue
    $nodes = @()

    foreach ($d in $dirs) {
        $coreMetaDir = Join-Path $d.FullName '.core'
        if (-not (Test-Path -LiteralPath $coreMetaDir)) { continue }

        $leafPath = Join-Path $coreMetaDir 'leaf.json'
        $indexPath = Join-Path $coreMetaDir 'index.json'
        if ((Test-Path -LiteralPath $leafPath) -or (Test-Path -LiteralPath $indexPath)) {
            $nodes += $d.FullName
        }
    }

    return $nodes
}

function Get-AdtLeafMetadata {
    param([Parameter(Mandatory = $true)][string]$LeafDir)

    $leafPath = Join-Path (Join-Path $LeafDir '.core') 'leaf.json'
    if (-not (Test-Path -LiteralPath $leafPath)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $leafPath -Raw | ConvertFrom-Json)
    }
    catch {
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
    }
    catch {
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
        generatedAt   = Get-AdtUtcNow
        nodes         = @()
        errors        = @()
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

    $nodeDirs = Find-AdtCoreNodes -RepoRoot $RepoRoot

    # Build a quick lookup map (id -> node).
    $nodeMap = @{}

    foreach ($nodePath in $nodeDirs) {
        $relFromCore = Get-AdtRelativePath -Base $coreRoot -FullPath $nodePath
        $id = $relFromCore -replace '\\', '/'
        if (-not $id) { continue }

        $leafMeta = Get-AdtLeafMetadata -LeafDir $nodePath
        $indexMeta = Get-AdtIndexMetadata -IndexDir $nodePath

        $kind = $null
        $meta = $null
        $nodeErrors = @()

        if ($leafMeta) {
            $kind = 'leaf'
            $meta = $leafMeta
        }
        elseif ($indexMeta) {
            $kind = 'index'
            $meta = $indexMeta
        }
        else {
            $kind = 'unknown'
            $nodeErrors += 'Missing .core/leaf.json or .core/index.json'
        }

        $node = [pscustomobject]@{
            id     = $id
            path   = ("_core/{0}" -f $id)
            kind   = $kind
            meta   = $meta
            errors = $nodeErrors
        }

        $catalog.nodes += $node
        $nodeMap[$id] = $node
    }

    # Canonical leaf enforcement
    $mode = [string]$Capabilities.capabilities.enforceCanonicalLeaves
    # Helper map for matching canonical leaf references by basename when unique.
    $nameToId = @{}
    $nameAmbiguous = @{}
    foreach ($n0 in $catalog.nodes) {
        $baseName = ($n0.id -split '/')[($n0.id -split '/').Length - 1]
        if ($nameToId.ContainsKey($baseName)) {
            $nameAmbiguous[$baseName] = $true
        }
        else {
            $nameToId[$baseName] = $n0.id
        }
    }

    $missingCanon = @()

    foreach ($n in $catalog.nodes) {
        if ($n.kind -ne 'index') { continue }
        if (-not $n.meta) { continue }

        $canon = $n.meta.canonicalLeaves
        if (-not $canon) { continue }

        foreach ($leafIdRaw in $canon) {
            $leafId = [string]$leafIdRaw
            $candidateId = $leafId
            $exists = $nodeMap.ContainsKey($candidateId)

            if (-not $exists) {
                if (-not ($leafId -match '/')) {
                    if ($nameToId.ContainsKey($leafId) -and -not $nameAmbiguous.ContainsKey($leafId)) {
                        $candidateId = $nameToId[$leafId]
                        $exists = $nodeMap.ContainsKey($candidateId)
                    }
                }
            }

            if (-not $exists) {
                $msg = "Index '$($n.id)' requires canonical leaf '$leafId' but it was not found under _core/"
                if ($mode -eq 'error') {
                    $catalog.errors += $msg
                }
                elseif ($mode -eq 'warn') {
                    $catalog.errors += "WARN: $msg"
                }

                $missingCanon += [pscustomobject]@{ index = $n.id; leaf = $leafId }
            }
        }
    }

    if ($missingCanon.Count -gt 0 -and $mode -ne 'off') {
        foreach ($m in $missingCanon) {
            $hint = "To add: git submodule add <url> _core/$($m.leaf)"
            if ($mode -eq 'error') {
                $catalog.errors += $hint
            }
            else {
                $catalog.errors += "HINT: $hint"
            }
        }
    }

    if ($DryRun) {
        Write-AdtInfo "[dry-run] Would write core catalog: $catalogPath"
    }
    else {
        Write-AdtJson -Path $catalogPath -Object $catalog
    }

    return $catalog
}

function Get-AdtDependenciesState {
    param([Parameter(Mandatory = $true)][string]$ProjectDir)

    $path = Join-Path (Join-Path $ProjectDir 'state') 'dependencies.json'
    $state = Read-AdtJson -Path $path

    if (-not $state) {
        $state = [pscustomobject]@{
            schemaVersion = '20260121T000000Z'
            dependencies  = @()
        }
    }

    return $state
}

function Invoke-AdtDependencyEnforcement {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [Parameter(Mandatory = $true)]$Capabilities
    )

    $mode = 'warn'
    try {
        if ($Capabilities -and $Capabilities.capabilities -and $Capabilities.capabilities.dependencyEnforcement) {
            $mode = [string]$Capabilities.capabilities.dependencyEnforcement
        }
    }
    catch { }

    if ($mode -eq 'off') {
        return
    }

    $deps = Get-AdtDependenciesState -ProjectDir $ProjectDir
    $missing = @()

    foreach ($d in $deps.dependencies) {
        $leaf = [string]$d.leaf
        $path = $null
        try { $path = [string]$d.path } catch { $path = $null }

        $target = $null
        if ($path -and $path.Trim().Length -gt 0) {
            $target = Join-Path $RepoRoot $path
        }
        else {
            $target = Join-Path (Join-Path $RepoRoot '_core') $leaf
        }

        if (-not (Test-Path -LiteralPath $target)) {
            $missing += [pscustomobject]@{ leaf = $leaf; path = $target }
        }
    }

    if ($missing.Count -gt 0) {
        foreach ($m in $missing) {
            $msg = "Missing dependency leaf '$($m.leaf)' at '$($m.path)'"
            if ($mode -eq 'warn') {
                Write-AdtInfo "WARN: $msg"
            }
        }

        if ($mode -eq 'error') {
            throw "Dependency enforcement failed with $($missing.Count) missing dependency(ies)."
        }
    }
}

function Assert-AdtCommandAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$Hint
    )

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "$Hint (missing command: $CommandName)"
    }
}

function Invoke-AdtShellCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Shell,
        [Parameter(Mandatory = $true)][string]$Command,
        [string]$WorkingDirectory
    )

    $out = ''
    $exit = 0

    if ($WorkingDirectory -and $WorkingDirectory.Trim().Length -gt 0) {
        Push-Location -LiteralPath $WorkingDirectory
    }

    try {
        if ($Shell -eq 'powershell' -or $Shell -eq 'pwsh') {
            # Run in-process to avoid brittle quoting issues.
            $out = (Invoke-Expression $Command 2>&1 | Out-String)
            if ($LASTEXITCODE -ne $null) { $exit = $LASTEXITCODE } else { $exit = 0 }
        }
        elseif ($Shell -eq 'cmd') {
            $out = (& cmd /c $Command 2>&1 | Out-String)
            if ($LASTEXITCODE -ne $null) { $exit = $LASTEXITCODE } else { $exit = 0 }
        }
        elseif ($Shell -eq 'bash') {
            Assert-AdtCommandAvailable -CommandName 'bash' -Hint 'Shell "bash" requested but bash was not found on PATH.'
            $out = (& bash -lc $Command 2>&1 | Out-String)
            if ($LASTEXITCODE -ne $null) { $exit = $LASTEXITCODE } else { $exit = 0 }
        }
        else {
            throw "Unsupported shell: $Shell"
        }
    }
    finally {
        if ($WorkingDirectory -and $WorkingDirectory.Trim().Length -gt 0) {
            Pop-Location
        }
    }

    return [pscustomobject]@{ exitCode = $exit; output = $out }
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

    Assert-AdtCommandAvailable -CommandName 'git' -Hint 'git is required for ADT upgrade.'

    $projectDir = Ensure-AdtProjectScaffold -RepoRoot $RepoRoot
    $caps = Get-AdtCapabilities -ProjectDir $projectDir
    Invoke-AdtDriftRepair -RepoRoot $RepoRoot -ProjectDir $projectDir -Capabilities $caps -DryRun:$DryRun
    Invoke-AdtSchemaValidation -RepoRoot $RepoRoot -ProjectDir $projectDir -Capabilities $caps

    $intentDir = Join-Path (Join-Path $projectDir 'record') 'upgrade-intents'

    $leafPath = $Leaf
    if ($leafPath -notmatch '[/\\]') {
        $leafPath = Join-Path (Join-Path $RepoRoot '_core') $Leaf
    }
    else {
        $leafPath = Join-Path $RepoRoot $Leaf
    }

    $leafRel = $leafPath.Replace($RepoRoot, '').TrimStart('\\').TrimStart('/')
    $leafRelGit = ($leafRel -replace '\\', '/')

    if ($Capabilities.capabilities.requireUpgradeIntent -eq $true) {
        $hasIntent = $false
        if ($IntentFile) {
            $intentAbs = Join-Path $RepoRoot $IntentFile
            $hasIntent = Test-Path -LiteralPath $intentAbs
        }
        elseif (Test-Path -LiteralPath $intentDir) {
            $matches = Get-ChildItem -LiteralPath $intentDir -Filter "*${Leaf}*.md" -ErrorAction SilentlyContinue
            $hasIntent = ($matches -and $matches.Count -gt 0)
        }

        if (-not $hasIntent) {
            throw "Upgrade intent required but not found. Create an intent in .project/record/upgrade-intents/ (or pass -IntentFile)."
        }
    }

    if ($DryRun) {
        Write-AdtInfo "[dry-run] Would update submodule: $leafRelGit"
        return
    }

    $before = Invoke-AdtGit -RepoRoot $RepoRoot -Arguments @('submodule', 'status', $leafRelGit)
    if ($before.ExitCode -ne 0) {
        throw "git submodule status failed for ${leafRel}: $($before.Stderr)"
    }

    Write-AdtInfo "Updating submodule: $leafRelGit"
    $update = Invoke-AdtGit -RepoRoot $RepoRoot -Arguments @('submodule', 'update', '--remote', '--merge', $leafRelGit)
    if ($update.ExitCode -ne 0) {
        throw "git submodule update failed for ${leafRel}: $($update.Stderr)"
    }

    $after = Invoke-AdtGit -RepoRoot $RepoRoot -Arguments @('submodule', 'status', $leafRelGit)

    $success = $true
    $verifyOutput = ''

    if (-not $NoVerify) {
        $leafMeta = Get-AdtLeafMetadata -LeafDir $leafPath
        if ($leafMeta -and $leafMeta.upgradeVerification -and $leafMeta.upgradeVerification.commands) {
            foreach ($cmd in $leafMeta.upgradeVerification.commands) {
                $shell = [string]$cmd.shell
                $command = [string]$cmd.command
                $cwd = $null
                try { $cwd = [string]$cmd.cwd } catch { $cwd = $null }
                $workDir = $null
                if ($cwd -and $cwd.Trim().Length -gt 0) {
                    $workDir = (Join-Path $RepoRoot $cwd)
                }

                $command = $command.Replace('<repoRoot>', $RepoRoot)
                $command = $command.Replace('<leafPath>', $leafRelGit)

                Write-AdtInfo "Verifying ($($cmd.name))"

                try {
                    if ($shell -eq 'pwsh') {
                        Assert-AdtCommandAvailable -CommandName 'pwsh' -Hint 'Shell "pwsh" requested but pwsh was not found on PATH.'
                    }

                    $res = Invoke-AdtShellCommand -Shell $shell -Command $command -WorkingDirectory $workDir
                    $verifyOutput += $res.output

                    if ($res.exitCode -ne 0) {
                        $success = $false
                        $verifyOutput += ("`nExitCode: {0}`n" -f $res.exitCode)
                        break
                    }
                }
                catch {
                    $success = $false
                    $verifyOutput += ($_.Exception.Message + "`n")
                    break
                }
            }
        }
    }

    if (-not $success) {
        Write-AdtInfo 'Verification failed; rolling back submodule pointer.'
        $null = Invoke-AdtGit -RepoRoot $RepoRoot -Arguments @('checkout', '--', $leafRelGit)
        $null = Invoke-AdtGit -RepoRoot $RepoRoot -Arguments @('submodule', 'update', '--init', '--recursive', $leafRelGit)
    }

    # Post-upgrade reconcile steps (schema + migrations + catalog + dependencies)
    $reconcileNotes = ''
    try {
        $caps2 = Get-AdtCapabilities -ProjectDir $projectDir
        Invoke-AdtDriftRepair -RepoRoot $RepoRoot -ProjectDir $projectDir -Capabilities $caps2 -DryRun:$false
        Invoke-AdtSchemaValidation -RepoRoot $RepoRoot -ProjectDir $projectDir -Capabilities $caps2

        if ($caps2.capabilities.autoMigrateSchema -eq $true) {
            Invoke-AdtMigrations -RepoRoot $RepoRoot -ProjectDir $projectDir -DryRun:$false
        }

        if ($caps2.capabilities.coreModelEnabled -eq $true) {
            $null = Invoke-AdtCoreCatalog -RepoRoot $RepoRoot -ProjectDir $projectDir -Capabilities $caps2 -DryRun:$false
        }

        Invoke-AdtDependencyEnforcement -RepoRoot $RepoRoot -ProjectDir $projectDir -Capabilities $caps2
        $reconcileNotes = 'Post-upgrade reconcile: ok'
    }
    catch {
        $success = $false
        $reconcileNotes = ("Post-upgrade reconcile failed: {0}" -f $_.Exception.Message)
    }

    # Record result
    $resultsDir = Join-Path (Join-Path $projectDir 'record') 'upgrade-results'
    New-AdtDirectory -Path $resultsDir

    $date = (Get-Date).ToString('yyyy-MM-dd')
    $resultPath = Join-Path $resultsDir ("{0}-{1}.md" -f $date, $Leaf)

    $body = @(
        "# Upgrade Result: $Leaf",
        '',
        "- Leaf path: $leafRelGit",
        "- At (UTC): $(Get-AdtUtcNow)",
        "- Before: $($before.Stdout.Trim())",
        "- After: $($after.Stdout.Trim())",
        "- Success: $($success)",
        ("- Reconcile: {0}" -f $reconcileNotes),
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
