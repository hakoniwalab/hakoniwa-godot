param(
    [Parameter(Mandatory = $true)]
    [string]$GodotBin,
    [string]$ProjectDir = "",
    [string]$BuildDir = "",
    [string]$Configuration = "Release",
    [string]$HakoConfigPath = "",
    [int]$WaitSec = 1,
    [int]$ConductorDeltaUsec = 10000,
    [int]$ConductorMaxDelayUsec = 20000,
    [switch]$SyncAddons,
    [switch]$KeepConductor
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
    $ProjectDir = Join-Path $RepoRoot "tests/smoke/core_pro_smoke"
}

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $RepoRoot "build-win-all-codecs"
}

$RepoAddonsDir = Join-Path $RepoRoot "addons"
$ProjectAddonsDir = Join-Path $ProjectDir "addons"
$ConductorExe = Join-Path $BuildDir "tools/hako_conductor_runner.exe"

if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
    throw "Godot executable not found: $GodotBin"
}

if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) {
    throw "Smoke test project directory not found: $ProjectDir"
}

if (-not (Test-Path -LiteralPath $ConductorExe -PathType Leaf)) {
    throw "Windows conductor runner not found: $ConductorExe"
}

function Ensure-ProjectAddons {
    if (-not (Test-Path -LiteralPath $RepoAddonsDir -PathType Container)) {
        throw "Repository addons directory not found: $RepoAddonsDir"
    }

    if (Test-Path -LiteralPath $ProjectAddonsDir) {
        $ProjectAddonsItem = Get-Item -LiteralPath $ProjectAddonsDir -Force
        if ($ProjectAddonsItem.LinkType -eq "SymbolicLink") {
            Write-Host "[run-core-pro-smoke.ps1] addons uses repository symlink: $ProjectAddonsDir"
            return
        }

        Write-Warning "Project addons path is not a symbolic link. Replacing it with a copy of the repository addons directory: $ProjectAddonsDir"
        Remove-Item -LiteralPath $ProjectAddonsDir -Recurse -Force
    }
    else {
        Write-Warning "Project addons path is missing. Creating a copy of the repository addons directory: $ProjectAddonsDir"
    }

    New-Item -ItemType Directory -Force -Path $ProjectAddonsDir | Out-Null
    Copy-Item -Path (Join-Path $RepoAddonsDir "*") -Destination $ProjectAddonsDir -Recurse -Force
}

if ($SyncAddons) {
    Write-Warning "-SyncAddons is no longer required; addons are validated and normalized automatically on Windows."
}
Ensure-ProjectAddons

$HadOriginalHakoConfigPath = Test-Path Env:HAKO_CONFIG_PATH
$OriginalHakoConfigPath = $env:HAKO_CONFIG_PATH
$OverrideHakoConfigPath = $false

if (-not [string]::IsNullOrWhiteSpace($HakoConfigPath)) {
    if (-not (Test-Path -LiteralPath $HakoConfigPath -PathType Leaf)) {
        throw "Hakoniwa Core config not found: $HakoConfigPath"
    }
    $ResolvedHakoConfigPath = (Resolve-Path -LiteralPath $HakoConfigPath).Path
    $env:HAKO_CONFIG_PATH = $ResolvedHakoConfigPath
    $OverrideHakoConfigPath = $true
    Write-Host "[run-core-pro-smoke.ps1] using explicit HAKO_CONFIG_PATH=$ResolvedHakoConfigPath"
}
elseif (-not [string]::IsNullOrWhiteSpace($env:HAKO_CONFIG_PATH)) {
    Write-Warning "-HakoConfigPath was not specified. Inheriting HAKO_CONFIG_PATH=$($env:HAKO_CONFIG_PATH). Confirm that this config belongs to the Hakoniwa runtime used by this smoke test."
    if (-not (Test-Path -LiteralPath $env:HAKO_CONFIG_PATH -PathType Leaf)) {
        Write-Warning "The inherited HAKO_CONFIG_PATH does not point to an existing file: $($env:HAKO_CONFIG_PATH)"
    }
}
else {
    Write-Warning "-HakoConfigPath was not specified and HAKO_CONFIG_PATH is unset. Hakoniwa Core will use its default configuration path."
}

$ConductorArguments = @(
    "--delta-usec", $ConductorDeltaUsec,
    "--max-delay-usec", $ConductorMaxDelayUsec
)

$ConductorProcess = $null
try {
    Write-Host "[run-core-pro-smoke.ps1] starting conductor"
    $ConductorProcess = Start-Process `
        -FilePath $ConductorExe `
        -ArgumentList $ConductorArguments `
        -PassThru `
        -WindowStyle Hidden

    Start-Sleep -Seconds $WaitSec

    # core_pro_smoke drives an asynchronous multi-frame lifecycle and quits itself
    # after emitting HAKO_CORE_SMOKE_OK. Do not pass Godot's --quit flag here.
    $GodotArguments = @("--headless", "--path", $ProjectDir)

    Write-Host "[run-core-pro-smoke.ps1] launching Godot"
    $StdoutPath = [System.IO.Path]::GetTempFileName()
    $StderrPath = [System.IO.Path]::GetTempFileName()

    try {
        $Process = Start-Process `
            -FilePath $GodotBin `
            -ArgumentList $GodotArguments `
            -Wait `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput $StdoutPath `
            -RedirectStandardError $StderrPath

        $StdoutText = ""
        $StderrText = ""
        if (Test-Path -LiteralPath $StdoutPath) {
            $StdoutText = Get-Content -LiteralPath $StdoutPath -Raw
        }
        if (Test-Path -LiteralPath $StderrPath) {
            $StderrText = Get-Content -LiteralPath $StderrPath -Raw
        }
        $OutputText = ($StdoutText + $StderrText).TrimEnd()
        if (-not [string]::IsNullOrWhiteSpace($OutputText)) {
            $OutputText | Write-Host
        }
        $ExitCode = $Process.ExitCode
    }
    finally {
        Remove-Item -LiteralPath $StdoutPath, $StderrPath -Force -ErrorAction SilentlyContinue
    }

    if ($ExitCode -ne 0) {
        throw "Godot exited with code $ExitCode"
    }

    if ($OutputText -match "(?m)^(SCRIPT ERROR:|ERROR:)") {
        throw "Smoke test emitted runtime/script errors"
    }

    if ($OutputText -notmatch "HAKO_CORE_SMOKE_OK") {
        throw "Smoke test did not emit HAKO_CORE_SMOKE_OK"
    }

    Write-Host "[run-core-pro-smoke.ps1] passed"
}
finally {
    if (-not $KeepConductor -and $ConductorProcess -and -not $ConductorProcess.HasExited) {
        Stop-Process -Id $ConductorProcess.Id -Force -ErrorAction SilentlyContinue
    }

    if ($OverrideHakoConfigPath) {
        if ($HadOriginalHakoConfigPath) {
            $env:HAKO_CONFIG_PATH = $OriginalHakoConfigPath
        }
        else {
            Remove-Item Env:HAKO_CONFIG_PATH -ErrorAction SilentlyContinue
        }
    }
}
