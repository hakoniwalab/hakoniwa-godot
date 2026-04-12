param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("stage", "archive", "paths")]
    [string]$Command,

    [Parameter(Mandatory = $true)]
    [ValidateSet("macos", "linux", "windows")]
    [string]$Platform,

    [Parameter(Mandatory = $true)]
    [string]$Arch,

    [string]$DistDir = "",
    [string]$RuntimeDir = "",
    [string]$MsgsDir = "",
    [string]$Packages = "all",
    [string]$ArtifactName = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

if ([string]::IsNullOrWhiteSpace($DistDir)) {
    $DistDir = Join-Path $RepoRoot "dist"
}
if ([string]::IsNullOrWhiteSpace($RuntimeDir)) {
    $RuntimeDir = Join-Path $RepoRoot "addons/hakoniwa"
}
if ([string]::IsNullOrWhiteSpace($MsgsDir)) {
    $MsgsDir = Join-Path $RepoRoot "addons/hakoniwa_msgs"
}

function Normalize-Packages {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw) -or $Raw -eq "all") {
        return "all"
    }
    return ($Raw -replace ",", ";")
}

function Resolve-LibraryExtension {
    param([string]$TargetPlatform)
    switch ($TargetPlatform) {
        "macos" { return ".dylib" }
        "linux" { return ".so" }
        "windows" { return ".dll" }
        default { throw "unsupported platform: $TargetPlatform" }
    }
}

function Resolve-RuntimeLibraryName {
    param([string]$TargetPlatform)
    switch ($TargetPlatform) {
        "macos" { return "libhakoniwa_godot_native.dylib" }
        "linux" { return "libhakoniwa_godot_native.so" }
        "windows" { return "hakoniwa_godot_native.dll" }
        default { throw "unsupported platform: $TargetPlatform" }
    }
}

function Resolve-ArchiveSuffix {
    param([string]$TargetPlatform)
    switch ($TargetPlatform) {
        "windows" { return ".zip" }
        "macos" { return ".tar.gz" }
        "linux" { return ".tar.gz" }
        default { throw "unsupported platform: $TargetPlatform" }
    }
}

function Resolve-ArtifactName {
    param(
        [string]$TargetPlatform,
        [string]$TargetArch,
        [string]$OverrideName
    )
    if (-not [string]::IsNullOrWhiteSpace($OverrideName)) {
        return $OverrideName
    }
    return "hakoniwa-godot-$TargetPlatform-$TargetArch"
}

function Copy-DirectoryContents {
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        throw "directory not found: $SourceDir"
    }
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceDir "*") -Destination $TargetDir -Recurse -Force
}

function Patch-RuntimeGdextension {
    param(
        [string]$GdextensionPath,
        [string]$TargetPlatform,
        [string]$TargetArch,
        [string]$RuntimeLibraryName
    )

    $PlatformKey = switch ($TargetPlatform) {
        "macos" { "macos" }
        "linux" { "linux.$TargetArch" }
        "windows" { "windows.$TargetArch" }
        default { throw "unsupported platform: $TargetPlatform" }
    }

    $Content = @"
[configuration]

entry_symbol = "hakoniwa_library_init"
compatibility_minimum = "4.5"

[libraries]

$PlatformKey.debug = "res://addons/hakoniwa/bin/$RuntimeLibraryName"
$PlatformKey.release = "res://addons/hakoniwa/bin/$RuntimeLibraryName"
"@

    Set-Content -LiteralPath $GdextensionPath -Value $Content -NoNewline
}

function Copy-RuntimeAddon {
    param(
        [string]$SourceRuntimeDir,
        [string]$TargetRoot,
        [string]$Extension,
        [string]$SelectedPackages,
        [string]$TargetPlatform,
        [string]$TargetArch
    )

    if (-not (Test-Path -LiteralPath $SourceRuntimeDir -PathType Container)) {
        throw "runtime addon directory not found: $SourceRuntimeDir"
    }

    $AddonRoot = Join-Path $TargetRoot "addons/hakoniwa"
    $BinDir = Join-Path $AddonRoot "bin"
    $CodecDir = Join-Path $AddonRoot "codecs"
    $ScriptDir = Join-Path $AddonRoot "scripts"

    New-Item -ItemType Directory -Force -Path $BinDir, $CodecDir, $ScriptDir | Out-Null

    Copy-Item -LiteralPath (Join-Path $SourceRuntimeDir "plugin.cfg") -Destination $AddonRoot -Force
    Copy-Item -LiteralPath (Join-Path $SourceRuntimeDir "hakoniwa.gdextension") -Destination $AddonRoot -Force
    Copy-DirectoryContents -SourceDir (Join-Path $SourceRuntimeDir "scripts") -TargetDir $ScriptDir

    $RuntimeBinaries = Get-ChildItem -LiteralPath (Join-Path $SourceRuntimeDir "bin") -File -Filter "*$Extension"
    if (-not $RuntimeBinaries) {
        throw "no runtime binary found for extension $Extension in $SourceRuntimeDir/bin"
    }
    foreach ($File in $RuntimeBinaries) {
        Copy-Item -LiteralPath $File.FullName -Destination $BinDir -Force
    }

    if ($SelectedPackages -eq "all") {
        $CodecFiles = Get-ChildItem -LiteralPath (Join-Path $SourceRuntimeDir "codecs") -File |
            Where-Object { $_.Name.EndsWith($Extension) -or $_.Name.EndsWith(".gdextension") }
        foreach ($File in $CodecFiles) {
            Copy-Item -LiteralPath $File.FullName -Destination $CodecDir -Force
        }
    }
    else {
        foreach ($Pkg in ($SelectedPackages -split ";")) {
            if ([string]::IsNullOrWhiteSpace($Pkg)) {
                continue
            }
            $LibSrc = Join-Path $SourceRuntimeDir "codecs/$Pkg`_codec$Extension"
            $GdextSrc = Join-Path $SourceRuntimeDir "codecs/$Pkg`_codec.gdextension"
            if (-not (Test-Path -LiteralPath $LibSrc -PathType Leaf)) {
                throw "codec library not found: $LibSrc"
            }
            if (-not (Test-Path -LiteralPath $GdextSrc -PathType Leaf)) {
                throw "codec gdextension not found: $GdextSrc"
            }
            Copy-Item -LiteralPath $LibSrc -Destination $CodecDir -Force
            Copy-Item -LiteralPath $GdextSrc -Destination $CodecDir -Force
        }
    }

    Patch-RuntimeGdextension `
        -GdextensionPath (Join-Path $AddonRoot "hakoniwa.gdextension") `
        -TargetPlatform $TargetPlatform `
        -TargetArch $TargetArch `
        -RuntimeLibraryName (Resolve-RuntimeLibraryName -TargetPlatform $TargetPlatform)
}

function Copy-MessageAddonIfPresent {
    param(
        [string]$SourceMsgsDir,
        [string]$TargetRoot
    )

    if (Test-Path -LiteralPath $SourceMsgsDir -PathType Container) {
        Copy-DirectoryContents -SourceDir $SourceMsgsDir -TargetDir (Join-Path $TargetRoot "addons/hakoniwa_msgs")
    }
}

function Invoke-Stage {
    param(
        [string]$TargetPlatform,
        [string]$TargetArch,
        [string]$OutputDistDir,
        [string]$SourceRuntimeDir,
        [string]$SourceMsgsDir,
        [string]$SelectedPackages,
        [string]$OverrideName
    )

    $NormalizedPackages = Normalize-Packages -Raw $SelectedPackages
    $Extension = Resolve-LibraryExtension -TargetPlatform $TargetPlatform
    $BaseName = Resolve-ArtifactName -TargetPlatform $TargetPlatform -TargetArch $TargetArch -OverrideName $OverrideName
    $StageDir = Join-Path $OutputDistDir $BaseName

    if (Test-Path -LiteralPath $StageDir) {
        Remove-Item -LiteralPath $StageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

    Copy-RuntimeAddon `
        -SourceRuntimeDir $SourceRuntimeDir `
        -TargetRoot $StageDir `
        -Extension $Extension `
        -SelectedPackages $NormalizedPackages `
        -TargetPlatform $TargetPlatform `
        -TargetArch $TargetArch

    Copy-MessageAddonIfPresent -SourceMsgsDir $SourceMsgsDir -TargetRoot $StageDir
    return $StageDir
}

function Invoke-Archive {
    param(
        [string]$TargetPlatform,
        [string]$TargetArch,
        [string]$OutputDistDir,
        [string]$SourceRuntimeDir,
        [string]$SourceMsgsDir,
        [string]$SelectedPackages,
        [string]$OverrideName
    )

    $StageDir = Invoke-Stage `
        -TargetPlatform $TargetPlatform `
        -TargetArch $TargetArch `
        -OutputDistDir $OutputDistDir `
        -SourceRuntimeDir $SourceRuntimeDir `
        -SourceMsgsDir $SourceMsgsDir `
        -SelectedPackages $SelectedPackages `
        -OverrideName $OverrideName

    $ArchiveSuffix = Resolve-ArchiveSuffix -TargetPlatform $TargetPlatform
    $ArchivePath = "$StageDir$ArchiveSuffix"
    if (Test-Path -LiteralPath $ArchivePath) {
        Remove-Item -LiteralPath $ArchivePath -Force
    }

    if ($TargetPlatform -eq "windows") {
        Compress-Archive -Path $StageDir -DestinationPath $ArchivePath -Force
    }
    else {
        throw "archive is implemented in PowerShell only for windows; use tools/addon_artifact_tool.sh on macOS/Linux"
    }

    return $ArchivePath
}

function Show-Paths {
    param(
        [string]$TargetPlatform,
        [string]$TargetArch,
        [string]$OutputDistDir,
        [string]$OverrideName
    )

    $BaseName = Resolve-ArtifactName -TargetPlatform $TargetPlatform -TargetArch $TargetArch -OverrideName $OverrideName
    $ArchiveSuffix = Resolve-ArchiveSuffix -TargetPlatform $TargetPlatform
    Write-Output "stage: $(Join-Path $OutputDistDir $BaseName)"
    Write-Output "archive: $(Join-Path $OutputDistDir ($BaseName + $ArchiveSuffix))"
}

switch ($Command) {
    "stage" {
        Invoke-Stage `
            -TargetPlatform $Platform `
            -TargetArch $Arch `
            -OutputDistDir $DistDir `
            -SourceRuntimeDir $RuntimeDir `
            -SourceMsgsDir $MsgsDir `
            -SelectedPackages $Packages `
            -OverrideName $ArtifactName
    }
    "archive" {
        Invoke-Archive `
            -TargetPlatform $Platform `
            -TargetArch $Arch `
            -OutputDistDir $DistDir `
            -SourceRuntimeDir $RuntimeDir `
            -SourceMsgsDir $MsgsDir `
            -SelectedPackages $Packages `
            -OverrideName $ArtifactName
    }
    "paths" {
        Show-Paths `
            -TargetPlatform $Platform `
            -TargetArch $Arch `
            -OutputDistDir $DistDir `
            -OverrideName $ArtifactName
    }
}
