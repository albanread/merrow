[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$studioExe = Join-Path $repoRoot 'zig-out\bin\merrow-studio.exe'
$studioDir = Split-Path -Parent $studioExe

if (-not (Test-Path -LiteralPath $studioExe -PathType Leaf)) {
    throw "Studio executable not found at $studioExe. Run .\scripts\build_windows_cli.ps1 first."
}

$s3GlueCandidates = @(
    (Join-Path $repoRoot 's3glue\build\Release\s3glue.dll'),
    (Join-Path $repoRoot 's3glue\build\RelWithDebInfo\s3glue.dll'),
    (Join-Path $repoRoot 's3glue\build\MinSizeRel\s3glue.dll'),
    (Join-Path $repoRoot 's3glue\build\Debug\s3glue.dll')
)

$s3GlueSource = $s3GlueCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ($s3GlueSource) {
    Copy-Item -LiteralPath $s3GlueSource -Destination (Join-Path $studioDir 's3glue.dll') -Force
}

$awsSdkBin = Join-Path (Split-Path -Parent $repoRoot) 'aws-sdk-cpp-install\bin'
$awsRuntimeDlls = @(
    'aws-c-auth.dll',
    'aws-c-cal.dll',
    'aws-c-common.dll',
    'aws-c-compression.dll',
    'aws-c-event-stream.dll',
    'aws-c-http.dll',
    'aws-c-io.dll',
    'aws-c-mqtt.dll',
    'aws-c-s3.dll',
    'aws-c-sdkutils.dll',
    'aws-checksums.dll',
    'aws-cpp-sdk-core.dll',
    'aws-cpp-sdk-s3.dll',
    'aws-crt-cpp.dll'
)

foreach ($dllName in $awsRuntimeDlls) {
    $sourcePath = Join-Path $awsSdkBin $dllName
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $studioDir $dllName) -Force
    }
}

Push-Location $studioDir
try {
    & $studioExe @AppArgs
} finally {
    Pop-Location
}