[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

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

function New-AdtJsonFileIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Json
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $parent = Split-Path -Parent $Path
        if ($parent) {
            New-AdtDirectory -Path $parent
        }
        $Json | Set-Content -LiteralPath $Path -Encoding UTF8
        return $true
    }

    return $false
}

function Add-AdtLineIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Line
    )

    New-AdtFile -Path $FilePath

    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { $content = '' }

    if ($content -notmatch "(?m)^\s*${([Regex]::Escape($Line))}\s*$") {
        if ($content.Length -gt 0 -and $content[-1] -ne "`n") {
            Add-Content -LiteralPath $FilePath -Value ""
        }
        Add-Content -LiteralPath $FilePath -Value $Line
    }
}

function Get-AdtCopilotSnippetBlocks {
    param([Parameter(Mandatory = $true)][string]$SnippetPath)

    if (-not (Test-Path -LiteralPath $SnippetPath)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $SnippetPath -Raw

    $optionA = $null
    $stop = $null

    $optionAMatch = [regex]::Match(
        $raw,
        '## Option A[^\n]*\n\s*```markdown\s*(?<body>[\s\S]*?)\s*```',
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )

    if ($optionAMatch.Success) {
        $optionA = $optionAMatch.Groups['body'].Value.Trim()
    }

    $stopMatch = [regex]::Match(
        $raw,
        'Optional[\s\S]*?\n\s*```markdown\s*(?<body>[\s\S]*?)\s*```',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    if ($stopMatch.Success) {
        $stop = $stopMatch.Groups['body'].Value.Trim()
    }

    return @{
        OptionA = $optionA
        StopCondition = $stop
    }
}

function Set-AdtCopilotInstructions {
    param(
        [Parameter(Mandatory = $true)][string]$CopilotInstructionsPath,
        [Parameter(Mandatory = $true)][string]$OptionABlock,
        [Parameter(Mandatory = $true)][string]$StopConditionBlock
    )

    New-AdtFile -Path $CopilotInstructionsPath

    $content = Get-Content -LiteralPath $CopilotInstructionsPath -Raw

    $startMarker = '<!-- ADT BOOTSTRAP START -->'
    $endMarker = '<!-- ADT BOOTSTRAP END -->'

    if ($content -match [Regex]::Escape($startMarker) -and $content -match [Regex]::Escape($endMarker)) {
        return
    }

    $alreadyHasAdt = ($content -match "(?i)ADT \(Required\)" -or $content -match "_core/adt/INSTRUCTIONS\.md")

    if (-not $alreadyHasAdt) {
        $block = @(
            $startMarker,
            '',
            $OptionABlock,
            '',
            $StopConditionBlock,
            '',
            $endMarker,
            ''
        ) -join "`n"

        Set-Content -LiteralPath $CopilotInstructionsPath -Value ($block + $content) -Encoding UTF8
        return
    }

    $hasStop = $content -match "(?i)Stop Condition"
    if (-not $hasStop) {
        $append = @(
            '',
            $startMarker,
            '',
            $StopConditionBlock,
            '',
            $endMarker,
            ''
        ) -join "`n"

        Add-Content -LiteralPath $CopilotInstructionsPath -Value $append
    }
}

$toolkitRoot = Split-Path -Parent $PSScriptRoot
$toolkitRoot = (Resolve-Path -LiteralPath $toolkitRoot).Path

if (-not $ProjectRoot) {
    # Default: assume toolkit is installed at <repoRoot>/_core/adt
    $ProjectRoot = Join-Path $toolkitRoot '..\..'
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

Write-Host "ADT init: project root = $ProjectRoot"
Write-Host "ADT init: toolkit root = $toolkitRoot"

$projectDir = Join-Path $ProjectRoot '.project'
$templateDir = Join-Path $toolkitRoot 'project-template'

New-AdtDirectory -Path $projectDir

# Legacy migration: copy from .adt-context into .project (non-destructive)
$legacyContextDir = Join-Path $ProjectRoot '.adt-context'
if (Test-Path -LiteralPath $legacyContextDir) {
    Write-Host 'Legacy .adt-context detected. Copying content into .project (non-destructive).'
    Get-ChildItem -LiteralPath $legacyContextDir | ForEach-Object {
        $dest = Join-Path $projectDir $_.Name
        if (-not (Test-Path -LiteralPath $dest)) {
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
        }
    }
}

# Fill missing template files
if (Test-Path -LiteralPath $templateDir) {
    Get-ChildItem -LiteralPath $templateDir | ForEach-Object {
        $dest = Join-Path $projectDir $_.Name
        if (-not (Test-Path -LiteralPath $dest)) {
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
        }
    }
}

# Capabilities (generated if missing)
$capabilitiesPath = Join-Path (Join-Path $projectDir '_schema') 'capabilities.json'
$defaultCapabilities = @{
    schemaVersion = '20260121T000000Z'
    capabilities = @{
        autoMigrateSchema = $true
        driftRepair = 'safe'
        requireUpgradeIntent = $true
        coreModelEnabled = $true
        enforceCanonicalLeaves = 'warn'
    }
} | ConvertTo-Json -Depth 6

$capCreated = New-AdtJsonFileIfMissing -Path $capabilitiesPath -Json $defaultCapabilities
if ($capCreated) {
    Write-Host 'Created .project/_schema/capabilities.json.'
}

New-AdtDirectory -Path (Join-Path $ProjectRoot '.scratchpad')
New-AdtDirectory -Path (Join-Path $ProjectRoot '.github')

$gitignorePath = Join-Path $ProjectRoot '.gitignore'
New-AdtFile -Path $gitignorePath
Add-AdtLineIfMissing -FilePath $gitignorePath -Line '.scratchpad/'

$snippetPath = Join-Path $toolkitRoot 'COPILOT-INSTRUCTIONS-SNIPPET.md'
$parsed = Get-AdtCopilotSnippetBlocks -SnippetPath $snippetPath

$optionA = $parsed.OptionA
$stopCondition = $parsed.StopCondition

if (-not $optionA) {
    $optionA = @(
        '> **ADT (Required)**:',
        '> 1) Before making changes, read `_core/adt/INSTRUCTIONS.md`.',
        '> 2) Treat `.project/` as the project''s committed memory and read it first.',
        '> 3) Check `.project/interrupt.md` at checkpoints; if it contains instructions, stop and ask.',
        '> 4) Log repeated command failures in `.project/attempts.md` and don''t repeat the same command without changing something.',
        '> 5) Put temporary scripts/debug helpers in `.scratchpad/` (gitignored).'
    ) -join "`n"
}

if (-not $stopCondition) {
    $stopCondition = '> **Stop Condition**: If you have not read `.project/now.md`, stop and read it before proceeding.'
}

$copilotInstructionsPath = Join-Path (Join-Path $ProjectRoot '.github') 'copilot-instructions.md'
Set-AdtCopilotInstructions -CopilotInstructionsPath $copilotInstructionsPath -OptionABlock $optionA -StopConditionBlock $stopCondition

$stateDir = Join-Path $projectDir 'state'
New-AdtDirectory -Path $stateDir

$statePath = Join-Path $stateDir 'adt-state.json'
$stateFileExisted = Test-Path -LiteralPath $statePath

$state = $null
if ($stateFileExisted) {
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    } catch {
        $state = $null
    }
}

if (-not $state) {
    $state = [pscustomobject]@{}
}

$now = (Get-Date).ToUniversalTime().ToString('o')

$state | Add-Member -Force -NotePropertyName 'toolkit' -NotePropertyValue 'adt'
$state | Add-Member -Force -NotePropertyName 'bootstrapCompleted' -NotePropertyValue $true
$state | Add-Member -Force -NotePropertyName 'lastBootstrapAt' -NotePropertyValue $now
$state | Add-Member -Force -NotePropertyName 'legacyAdtContextDetected' -NotePropertyValue (Test-Path -LiteralPath $legacyContextDir)

$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8

if (-not $stateFileExisted) {
    Write-Host 'Created .project/state/adt-state.json (initialization state).'
} else {
    Write-Host 'Updated .project/state/adt-state.json.'
}

Write-Host 'ADT init complete.'
