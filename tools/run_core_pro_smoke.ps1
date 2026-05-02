param(
    [Parameter(Mandatory = $true)]
    [string]$GodotBin,
    [string]$ProjectDir = "",
    [string]$BuildDir = "",
    [string]$Configuration = "Release",
    [int]$WaitSec = 1,
    [int]$ConductorDeltaUsec = 10000,
    [int]$ConductorMaxDelayUsec = 20000,
    [switch]$SyncAddons,
    [switch]$QuitAfterRun,
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

if ($SyncAddons) {
    if (-not (Test-Path -LiteralPath $RepoAddonsDir -PathType Container)) {
        throw "Repository addons directory not found: $RepoAddonsDir"
    }
    $SkipSyncBecauseSymlink = $false
    if (Test-Path -LiteralPath $ProjectAddonsDir) {
        $ProjectAddonsItem = Get-Item -LiteralPath $ProjectAddonsDir -Force
        if ($ProjectAddonsItem.LinkType -eq "SymbolicLink") {
            $SkipSyncBecauseSymlink = $true
        }
        else {
            Remove-Item -LiteralPath $ProjectAddonsDir -Recurse -Force
        }
    }
    if (-not $SkipSyncBecauseSymlink) {
        New-Item -ItemType Directory -Force -Path $ProjectAddonsDir | Out-Null
        Copy-Item -Path (Join-Path $RepoAddonsDir "*") -Destination $ProjectAddonsDir -Recurse -Force
    }
}

$ConductorArguments = @(
    "--delta-usec", $ConductorDeltaUsec,
    "--max-delay-usec", $ConductorMaxDelayUsec
)

Write-Host "[run-core-pro-smoke.ps1] starting conductor"
$ConductorProcess = Start-Process `
    -FilePath $ConductorExe `
    -ArgumentList $ConductorArguments `
    -PassThru `
    -WindowStyle Hidden

try {
    Start-Sleep -Seconds $WaitSec

    $GodotArguments = @("--headless", "--path", $ProjectDir)
    if ($QuitAfterRun) {
        $GodotArguments += "--quit"
    }

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
}
