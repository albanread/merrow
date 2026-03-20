[CmdletBinding()]
param(
    [ValidateSet('Debug', 'ReleaseSafe', 'ReleaseFast', 'ReleaseSmall')]
    [string]$Optimize = 'ReleaseSafe',

    [string]$Target = '',

    [string]$OutputRoot = '',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraZigArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$versionFile = Join-Path $repoRoot 'build.zig.zon'
$fontsDir = Join-Path $repoRoot 'fonts'
$zigOutDir = Join-Path $repoRoot 'zig-out'

if (-not (Get-Command zig -ErrorAction SilentlyContinue)) {
    throw 'zig was not found on PATH. Install Zig 0.15.2 or later and try again.'
}

if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
    throw "Missing version file: $versionFile"
}

if (-not (Test-Path -LiteralPath $fontsDir -PathType Container)) {
    throw "Missing fonts directory: $fontsDir"
}

if ($Target -and $Target -notmatch 'windows') {
    throw "Target must be a Windows target triple, got: $Target"
}

$versionMatch = Select-String -Path $versionFile -Pattern '\.version\s*=\s*"([^"]+)"'
if (-not $versionMatch) {
    throw "Unable to determine version from $versionFile"
}

$version = $versionMatch.Matches[0].Groups[1].Value
$packageSuffix = if ($Target) { $Target } else { 'windows-native' }
$releaseRoot = if ($OutputRoot) {
    if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
        $OutputRoot
    } else {
        Join-Path $repoRoot $OutputRoot
    }
} else {
    Join-Path $repoRoot 'release'
}

$packageDir = Join-Path $releaseRoot ("merrow-$version-$packageSuffix")
$archivePath = Join-Path $releaseRoot ("merrow-$version-$packageSuffix.zip")
$stagedBinary = Join-Path $packageDir 'merrow.exe'
$stagedFontsDir = Join-Path $packageDir 'fonts'

$buildArgs = @('build', "-Doptimize=$Optimize")
if ($Target) {
    $buildArgs += "-Dtarget=$Target"
}
if ($ExtraZigArgs.Count -gt 0) {
    $buildArgs += $ExtraZigArgs
}

Push-Location $repoRoot
try {
    & zig @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "zig build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$binaryCandidates = @(
    (Join-Path $zigOutDir 'bin\merrow.exe'),
    (Join-Path $zigOutDir 'bin\merrow')
)

$builtBinary = $binaryCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $builtBinary) {
    throw "Build completed, but no merrow binary was found under $zigOutDir\\bin"
}

New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
if (Test-Path -LiteralPath $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
}
if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
    Remove-Item -LiteralPath $archivePath -Force
}

New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
Copy-Item -LiteralPath $builtBinary -Destination $stagedBinary -Force
Copy-Item -LiteralPath $fontsDir -Destination $stagedFontsDir -Recurse -Force
Compress-Archive -LiteralPath $packageDir -DestinationPath $archivePath -CompressionLevel Optimal

Write-Host "Built merrow CLI with optimize=$Optimize"
if ($Target) {
    Write-Host "Target: $Target"
} else {
    Write-Host 'Target: native Windows'
}
Write-Host "Staged package: $packageDir"
Write-Host "Zip archive: $archivePath"
