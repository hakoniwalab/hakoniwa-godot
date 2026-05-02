param(
    [Parameter(Mandatory = $true)]
    [string]$GodotBin,
    [string]$ProjectDir = "",
    [switch]$QuitAfterRun,
    [switch]$SyncAddons
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
    $ProjectDir = Join-Path $RepoRoot "tests/smoke/basic_subscriber"
}

$RepoAddonsDir = Join-Path $RepoRoot "addons"
$ProjectAddonsDir = Join-Path $ProjectDir "addons"

if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
    throw "Godot executable not found: $GodotBin"
}

if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) {
    throw "Smoke test project directory not found: $ProjectDir"
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

$Arguments = @("--headless", "--path", $ProjectDir)
if ($QuitAfterRun) {
    $Arguments += "--quit"
}

Write-Host "[run-codec-smoke.ps1] launching Godot"
$StdoutPath = [System.IO.Path]::GetTempFileName()
$StderrPath = [System.IO.Path]::GetTempFileName()

try {
    $Process = Start-Process `
        -FilePath $GodotBin `
        -ArgumentList $Arguments `
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

if ($OutputText -notmatch "HAKONIWA_CODEC_SMOKE_OK") {
    throw "Smoke test did not emit HAKONIWA_CODEC_SMOKE_OK"
}

Write-Host "[run-codec-smoke.ps1] passed"
