<#
.SYNOPSIS
    Configure and build the s3glue DLL and smoke test using CMake.
.DESCRIPTION
    Expects AWS SDK for C++ to be installed and discoverable through either
    CMAKE_PREFIX_PATH or the -AwsSdkPrefix parameter.
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    [string]$AwsSdkPrefix = '',

    [switch]$NoTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $projectRoot) { $projectRoot = (Get-Location).Path }
$s3gRoot = Join-Path $projectRoot 's3glue'
$buildDir = Join-Path $s3gRoot 'build'

$cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmakeCommand) {
    $portableCmakeRoot = Join-Path (Split-Path -Parent $projectRoot) 'cmake-portable'
    if (Test-Path $portableCmakeRoot) {
        $portableCmakeExe = Get-ChildItem $portableCmakeRoot -Recurse -Filter cmake.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($portableCmakeExe) {
            $cmakeCommand = @{ Source = $portableCmakeExe }
        }
    }
}

if (-not $cmakeCommand) {
    throw 'cmake was not found on PATH or in ..\cmake-portable. Install or extract CMake and try again.'
}

$prefixPath = $AwsSdkPrefix
if (-not $prefixPath -and $env:AWSSDK_ROOT) {
    $prefixPath = $env:AWSSDK_ROOT
}
if (-not $prefixPath) {
    $portableAwsSdkRoot = Join-Path (Split-Path -Parent $projectRoot) 'aws-sdk-cpp-install'
    if (Test-Path (Join-Path $portableAwsSdkRoot 'lib\cmake\AWSSDK\AWSSDKConfig.cmake')) {
        $prefixPath = $portableAwsSdkRoot
    }
}

$buildTests = if ($NoTests) { 'FALSE' } else { 'TRUE' }
$configOutputDir = Join-Path $buildDir $Configuration

$configureArgs = @(
    '-S', $s3gRoot,
    '-B', $buildDir,
    '-A', 'x64',
    "-DS3G_BUILD_TESTS=$buildTests"
)

if ($prefixPath) {
    $configureArgs += "-DCMAKE_PREFIX_PATH=$prefixPath"
}

Write-Host "Configuration : $Configuration"
Write-Host "Source        : $s3gRoot"
Write-Host "Build         : $buildDir"
if ($prefixPath) {
    Write-Host "AWS SDK       : $prefixPath"
}
Write-Host ''

& $cmakeCommand.Source @configureArgs
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed' }

& $cmakeCommand.Source --build $buildDir --config $Configuration
if ($LASTEXITCODE -ne 0) { throw 'CMake build failed' }

Write-Host ''
Write-Host 'Build complete.'
Write-Host "DLL output    : $(Join-Path $configOutputDir 's3glue.dll')"
if (-not $NoTests) {
    Write-Host "Smoke test    : $(Join-Path $configOutputDir 's3g_smoke_test.exe')"
}