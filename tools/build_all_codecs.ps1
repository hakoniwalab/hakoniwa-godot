param(
    [string]$BuildDir = "",
    [string]$Generator = "Visual Studio 17 2022",
    [string]$Arch = "x64",
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",
    [string]$ToolchainFile = "",
    [string]$VcpkgTriplet = "",
    [string]$BoostDir = "",
    [string]$GodotBin = "",
    [ValidateSet("ON", "OFF")]
    [string]$Tests = "ON",
    [ValidateSet("minimal", "full")]
    [string]$DependencyBuild = "minimal",
    [string]$Packages = "all",
    [switch]$SkipMessageSync,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$MessageSourceRoot = Join-Path $RepoRoot "third_party/hakoniwa-core-pro/hakoniwa-pdu-registry/pdu/godot_gd"
$MessageTargetRoot = Join-Path $RepoRoot "addons/hakoniwa_msgs"

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $RepoRoot "build-win-all-codecs"
}

if ([string]::IsNullOrWhiteSpace($ToolchainFile) -and -not [string]::IsNullOrWhiteSpace($env:VCPKG_ROOT)) {
    $CandidateToolchain = Join-Path $env:VCPKG_ROOT "scripts/buildsystems/vcpkg.cmake"
    if (Test-Path -LiteralPath $CandidateToolchain -PathType Leaf) {
        $ToolchainFile = $CandidateToolchain
    }
}

if ([string]::IsNullOrWhiteSpace($VcpkgTriplet)) {
    $VcpkgTriplet = "x64-windows"
}

if ([string]::IsNullOrWhiteSpace($BoostDir) -and -not [string]::IsNullOrWhiteSpace($ToolchainFile)) {
    $ToolchainRoot = Split-Path -Parent (Split-Path -Parent $ToolchainFile)
    $CandidateBoostDir = Join-Path $ToolchainRoot "installed/$VcpkgTriplet/share/boost"
    if (Test-Path -LiteralPath $CandidateBoostDir -PathType Container) {
        $BoostDir = $CandidateBoostDir
    }
}

function Normalize-Packages {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw) -or $Raw -eq "all") {
        return "all"
    }
    return ($Raw -replace ",", ";")
}

function Resolve-PackageList {
    param([string]$SelectedPackages)
    if (-not (Test-Path -LiteralPath $MessageSourceRoot -PathType Container)) {
        throw "message source directory not found: $MessageSourceRoot"
    }

    if ($SelectedPackages -eq "all") {
        return Get-ChildItem -LiteralPath $MessageSourceRoot -Directory | Sort-Object Name | ForEach-Object { $_.Name }
    }

    return ($SelectedPackages -split ";") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Normalize-GdScriptFile {
    param([string]$FilePath)

    $RelativePath = $FilePath.Substring($RepoRoot.Length).TrimStart('\') -replace '\\', '/'
    $ResourcePath = "res://$RelativePath"
    $Content = Get-Content -LiteralPath $FilePath -Raw

    $Content = [regex]::Replace($Content, 'static func from_dict\(d: Dictionary\) -> [^:]+:', 'static func from_dict(d: Dictionary):')
    $Content = [regex]::Replace($Content, 'var obj := [A-Za-z0-9_]+\.new\(\)', "var obj = load(`"$ResourcePath`").new()")
    $Content = [regex]::Replace($Content, 'var ([A-Za-z0-9_]+): [A-Za-z0-9_]+ = ([A-Za-z0-9_]+)\.new\(\)', 'var $1 = $2.new()')
    $Content = [regex]::Replace($Content, 'var ([A-Za-z0-9_]+): HakoPdu_[A-Za-z0-9_]+ =', 'var $1 =')
    $Content = [regex]::Replace($Content, 'var ([A-Za-z0-9_]+) = HakoPdu_[A-Za-z0-9_]+\.new\(\)', 'var $1 = null')

    Set-Content -LiteralPath $FilePath -Value $Content -NoNewline
}

function Sync-MessageAddons {
    param([string]$SelectedPackages)

    $NormalizedPackages = Normalize-Packages -Raw $SelectedPackages
    $PackagesToSync = Resolve-PackageList -SelectedPackages $NormalizedPackages

    New-Item -ItemType Directory -Force -Path $MessageTargetRoot | Out-Null

    foreach ($Package in $PackagesToSync) {
        $SourceDir = Join-Path $MessageSourceRoot $Package
        $TargetDir = Join-Path $MessageTargetRoot $Package

        if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
            throw "message package not found: $SourceDir"
        }

        if (Test-Path -LiteralPath $TargetDir) {
            Remove-Item -LiteralPath $TargetDir -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
        Copy-Item -Path (Join-Path $SourceDir "*") -Destination $TargetDir -Recurse -Force

        Get-ChildItem -LiteralPath $TargetDir -Recurse -File -Filter "*.gd" | Sort-Object FullName | ForEach-Object {
            Normalize-GdScriptFile -FilePath $_.FullName
        }

        Write-Host "synced: $Package"
    }
}

$NormalizedPackages = Normalize-Packages -Raw $Packages

if ($Clean -and (Test-Path -LiteralPath $BuildDir)) {
    Remove-Item -LiteralPath $BuildDir -Recurse -Force
}

$ConfigureArgs = @(
    "-S", $RepoRoot,
    "-B", $BuildDir,
    "-G", $Generator,
    "-A", $Arch,
    "-DHAKONIWA_GODOT_CODEC_PACKAGES=$NormalizedPackages",
    "-DHAKONIWA_GODOT_BUILD_TESTS=$Tests"
)

if ($DependencyBuild -eq "minimal") {
    $ConfigureArgs += "-DHAKONIWA_GODOT_MINIMAL_DEP_BUILD=ON"
}
else {
    $ConfigureArgs += "-DHAKONIWA_GODOT_MINIMAL_DEP_BUILD=OFF"
}

if (-not [string]::IsNullOrWhiteSpace($GodotBin)) {
    $ConfigureArgs += "-DHAKONIWA_GODOT_EXECUTABLE=$GodotBin"
}

if (-not [string]::IsNullOrWhiteSpace($ToolchainFile)) {
    $ConfigureArgs += "-DCMAKE_TOOLCHAIN_FILE=$ToolchainFile"
}

if (-not [string]::IsNullOrWhiteSpace($VcpkgTriplet)) {
    $ConfigureArgs += "-DVCPKG_TARGET_TRIPLET=$VcpkgTriplet"
}

if (-not [string]::IsNullOrWhiteSpace($BoostDir)) {
    $ConfigureArgs += "-DBoost_DIR=$BoostDir"
}

Write-Host "[build-all-codecs.ps1] configure"
& cmake @ConfigureArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "[build-all-codecs.ps1] build"
& cmake --build $BuildDir --config $Configuration --parallel 4
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if (-not $SkipMessageSync) {
    Write-Host "[build-all-codecs.ps1] sync message addons"
    Sync-MessageAddons -SelectedPackages $NormalizedPackages
}

Write-Host "[build-all-codecs.ps1] done"
