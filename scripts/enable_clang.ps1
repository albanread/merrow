[CmdletBinding()]
param(
    [string[]]$CandidateBinPaths = @(
        'C:\Program Files\LLVM\bin',
        'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\Llvm\x64\bin',
        'C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Tools\Llvm\x64\bin',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\Llvm\x64\bin',
        'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Tools\Llvm\x64\bin'
    ),

    [switch]$SkipVerification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LlvmBinPath {
    param(
        [string[]]$Paths
    )

    $candidates = [System.Collections.Generic.List[string]]::new()

    foreach ($envVar in 'LLVM_HOME', 'LLVM_PATH') {
        $value = [Environment]::GetEnvironmentVariable($envVar)
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        $expanded = [Environment]::ExpandEnvironmentVariables($value)
        if (Test-Path -LiteralPath $expanded -PathType Container) {
            if ((Split-Path -Leaf $expanded) -ieq 'bin') {
                $candidates.Add($expanded)
            }
            else {
                $binPath = Join-Path $expanded 'bin'
                if (Test-Path -LiteralPath $binPath -PathType Container) {
                    $candidates.Add($binPath)
                }
            }
        }
    }

    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $expanded = [Environment]::ExpandEnvironmentVariables($path)
        if ((Test-Path -LiteralPath $expanded -PathType Container) -and -not $candidates.Contains($expanded)) {
            $candidates.Add($expanded)
        }
    }

    foreach ($candidate in $candidates) {
        $clangPath = Join-Path $candidate 'clang.exe'
        if (Test-Path -LiteralPath $clangPath -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

$llvmBin = Get-LlvmBinPath -Paths $CandidateBinPaths
if (-not $llvmBin) {
    throw 'Could not find an LLVM bin directory containing clang.exe.'
}

$currentPathEntries = @($env:Path -split ';' | Where-Object { $_ -ne '' })
if ($currentPathEntries -notcontains $llvmBin) {
    $env:Path = "$llvmBin;$env:Path"
}

Write-Host "Added LLVM tools to PATH from: $llvmBin"

if (-not $SkipVerification) {
    $requiredCommands = @('clang', 'clang++')
    $optionalCommands = @('clang-cl')

    foreach ($commandName in $requiredCommands) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if (-not $command) {
            throw "LLVM PATH was updated, but $commandName.exe is still not available."
        }

        Write-Host "$commandName.exe: $($command.Source)"
        & $command.Source --version | Select-Object -First 1
    }

    foreach ($commandName in $optionalCommands) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            Write-Host "$commandName.exe: $($command.Source)"
            & $command.Source --version | Select-Object -First 1
        }
    }
}