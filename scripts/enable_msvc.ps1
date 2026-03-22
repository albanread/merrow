[CmdletBinding()]
param(
    [ValidateSet('x64', 'x86')]
    [string]$Architecture = 'x64',

    [ValidateSet('Community', 'Professional', 'Enterprise', 'BuildTools')]
    [string[]]$PreferredEditions = @('Community', 'BuildTools', 'Professional', 'Enterprise'),

    [switch]$SkipVerification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-VsWherePath {
    $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        return $vswhere
    }
    return $null
}

function Get-VcVarsCandidatePaths {
    param(
        [string]$Arch,
        [string[]]$Editions
    )

    $batName = if ($Arch -eq 'x86') { 'vcvars32.bat' } else { 'vcvars64.bat' }
    $candidates = [System.Collections.Generic.List[string]]::new()

    $vswhere = Get-VsWherePath
    if ($vswhere) {
        $json = & $vswhere -products * -format json | ConvertFrom-Json
        foreach ($edition in $Editions) {
            foreach ($install in $json) {
                if ($install.installationPath -match [regex]::Escape("\$edition")) {
                    $path = Join-Path $install.installationPath "VC\Auxiliary\Build\$batName"
                    if (Test-Path -LiteralPath $path -PathType Leaf) {
                        $candidates.Add($path)
                    }
                }
            }
        }
    }

    foreach ($edition in $Editions) {
        $fallback = Join-Path 'C:\Program Files\Microsoft Visual Studio\2022' "$edition\VC\Auxiliary\Build\$batName"
        if ((Test-Path -LiteralPath $fallback -PathType Leaf) -and -not $candidates.Contains($fallback)) {
            $candidates.Add($fallback)
        }
    }

    return $candidates
}

function Import-CmdEnvironment {
    param(
        [string]$BatchFile
    )

    $envDump = cmd /c "call `"$BatchFile`" >nul && set"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to initialize MSVC environment using $BatchFile"
    }

    foreach ($line in $envDump) {
        if ($line -match '^(.*?)=(.*)$') {
            Set-Item -Path "Env:$($matches[1])" -Value $matches[2]
        }
    }
}

$candidatePaths = @(Get-VcVarsCandidatePaths -Arch $Architecture -Editions $PreferredEditions)
if ($candidatePaths.Count -eq 0) {
    throw "Could not find a Visual Studio vcvars script for architecture '$Architecture'."
}

$selected = $candidatePaths[0]
Import-CmdEnvironment -BatchFile $selected

Write-Host "Loaded MSVC environment from: $selected"

if (-not $SkipVerification) {
    $cl = Get-Command cl -ErrorAction SilentlyContinue
    if (-not $cl) {
        throw 'MSVC environment loaded, but cl.exe is still not available on PATH.'
    }

    Write-Host "cl.exe: $($cl.Source)"
    $banner = cmd /c "`"$($cl.Source)`" 2>&1"
    $banner | Select-Object -First 5
}
