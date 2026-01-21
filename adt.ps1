[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'scripts\adt.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $script @Args
