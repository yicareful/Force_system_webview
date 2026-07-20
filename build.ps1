$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleId = "force_system_webview"
$ModuleProp = Join-Path $Root "module.prop"
$DistDir = Join-Path $Root "dist"
$StageDir = Join-Path $DistDir $ModuleId

if (-not (Test-Path -LiteralPath $ModuleProp)) {
    throw "module.prop not found: $ModuleProp"
}

$VersionLine = Get-Content -LiteralPath $ModuleProp | Where-Object { $_ -like "version=*" } | Select-Object -First 1
$Version = if ($VersionLine) { $VersionLine.Substring("version=".Length).Trim() } else { "dev" }
$ZipPath = Join-Path $DistDir "$ModuleId-v$Version.zip"

function Assert-InWorkspace {
    param([Parameter(Mandatory = $true)][string]$Path)

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside the workspace: $pathFull"
    }
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

if (Test-Path -LiteralPath $StageDir) {
    Assert-InWorkspace $StageDir
    Remove-Item -LiteralPath $StageDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

$Files = @(
    "module.prop",
    "customize.sh",
    "action.sh",
    "README.md"
)

$Directories = @(
    "scripts",
    "webroot"
)

foreach ($file in $Files) {
    $source = Join-Path $Root $file
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required file missing: $file"
    }
    Copy-Item -LiteralPath $source -Destination $StageDir
}

foreach ($directory in $Directories) {
    $source = Join-Path $Root $directory
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required directory missing: $directory"
    }
    Copy-Item -LiteralPath $source -Destination $StageDir -Recurse
}

if (Test-Path -LiteralPath $ZipPath) {
    Assert-InWorkspace $ZipPath
    Remove-Item -LiteralPath $ZipPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $StageDir -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring($StageDir.Length).TrimStart("\", "/")
        $entryName = $relativePath -replace "\\", "/"
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip,
            $_.FullName,
            $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
}
finally {
    $zip.Dispose()
}

Assert-InWorkspace $StageDir
Remove-Item -LiteralPath $StageDir -Recurse -Force

Write-Host "Built $ZipPath"
