[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

$legacy = Join-Path $ProjectRoot '.adt-context'
$dest = Join-Path $ProjectRoot '.project'

if (-not (Test-Path -LiteralPath $legacy)) {
    return @{ id = '20260121T000000Z-legacy-adt-context'; changed = $false; notes = 'No legacy .adt-context present.' }
}

if (-not (Test-Path -LiteralPath $dest)) {
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
}

$changed = $false
Get-ChildItem -LiteralPath $legacy | ForEach-Object {
    $target = Join-Path $dest $_.Name
    if (-not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
        $changed = $true
    }
}

return @{ id = '20260121T000000Z-legacy-adt-context'; changed = $changed; notes = 'Copied missing files from .adt-context into .project.' }
