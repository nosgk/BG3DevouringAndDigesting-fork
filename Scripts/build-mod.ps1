# Builds the DevouringAndDigesting mod into a BG3 .pak and packages it into a zip
# ready for import into BG3 Mod Manager.
#
# Pipeline (mirrors bg3-modders-multitool packing):
#   1. copy the mod source tree to a staging folder
#   2. convert *.loca.xml  -> *.loca      (divine convert-loca)
#   3. convert *.lsf.lsx   -> *.lsf       (divine convert-resources; divine requires
#                                         a directory as -s, so files are grouped per folder)
#   4. create the .pak                  (divine create-package, LZ4)
#   5. zip the .pak
#
# Usage:
#   ./Scripts/build-mod.ps1 [-DivinePath <divine.exe>] [-SourceDir <mod source>] [-OutputDir <dir>]

param(
    [Parameter(Mandatory = $true)]
    [string] $DivinePath,

    [string] $SourceDir,

    [string] $OutputDir
)

$ErrorActionPreference = "Stop"

if (-not $SourceDir) { $SourceDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\DevouringAndDigesting")) }
if (-not $OutputDir) { $OutputDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\build")) }

$DivinePath = (Resolve-Path $DivinePath).Path
$SourceDir = (Resolve-Path $SourceDir).Path
if (-not (Test-Path "$DivinePath")) {
    throw "divine.exe not found at: $DivinePath"
}
if (-not (Test-Path "$SourceDir\Mods\DevouringAndDigesting\meta.lsx")) {
    throw "Mod source tree not found at: $SourceDir"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path

$StagingDir = Join-Path $OutputDir "staging"
if (Test-Path $StagingDir) { Remove-Item -Recurse -Force $StagingDir }
New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null

Write-Host "== Staging mod tree: $SourceDir"
Copy-Item -Recurse -Path "$SourceDir\*" -Destination $StagingDir

function Invoke-Divine {
    & $DivinePath -g bg3 @Args
    if ($LASTEXITCODE -ne 0) {
        throw "divine.exe failed with exit code $LASTEXITCODE"
    }
}

# --- localization: Localization/**/*.loca.xml -> **/*.loca -------------------
Write-Host "== Converting localization files"
Get-ChildItem -Path $StagingDir -Recurse -Filter "*.loca.xml" | ForEach-Object {
    $dest = $_.FullName.Substring(0, $_.FullName.Length - 4)
    Invoke-Divine -a convert-loca -s $_.FullName -d $dest
    Remove-Item -Force $_.FullName
    Write-Host "   $($_.FullName.Substring($StagingDir.Length + 1)) -> $(Split-Path -Leaf $dest)"
}

# --- visual banks / root templates: **/*.lsf.lsx -> **/*.lsf -----------------
Write-Host "== Converting LSF resources"
$lsfSources = Get-ChildItem -Path $StagingDir -Recurse -Filter "*.lsf.lsx"
if ($lsfSources) {
    # divine's convert-resources requires a directory as -s, so group by folder
    $tmpDir = Join-Path $OutputDir "convert_tmp"
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    foreach ($group in ($lsfSources | Group-Object -Property DirectoryName)) {
        Invoke-Divine -a convert-resources -i lsx -o lsf -s $group.Name -d $tmpDir
        foreach ($file in $group.Group) {
            $produced = Join-Path $tmpDir ($file.Name.Substring(0, $file.Name.Length - 4) + ".lsf")
            $dest = $file.FullName.Substring(0, $file.FullName.Length - 4)
            Move-Item -Force $produced $dest
            Remove-Item -Force $file.FullName
            Write-Host "   $($file.FullName.Substring($StagingDir.Length + 1)) -> $(Split-Path -Leaf $dest)"
        }
    }
    Remove-Item -Recurse -Force $tmpDir
}

# --- flatten stats subdirectories ---------------------------------------------
# The game's stats scanner does not recurse into subdirectories under
# Stats/Generated/Data/ (the game itself and all working mods keep stats files
# flat in Data/), so files in Data/Items/, Data/Passive/, Data/Spells/, etc.
# would never load. Flatten them into Data/ at package time.
Write-Host "== Flattening stats files into Data/"
$statsDataDir = Join-Path $StagingDir "Public\DevouringAndDigesting\Stats\Generated\Data"
Get-ChildItem -Path $statsDataDir -Recurse -Filter "*.txt" | Where-Object { $_.DirectoryName -ne $statsDataDir } | ForEach-Object {
    if ($_.Length -eq 0) {
        Write-Host "   removing empty file: $($_.Name)"
        Remove-Item -Force $_.FullName
        return
    }
    $dest = Join-Path $statsDataDir $_.Name
    if (Test-Path $dest) {
        throw "Stats file name collision while flattening: $($_.Name)"
    }
    Move-Item -Force $_.FullName $dest
    Write-Host "   $($_.FullName.Substring($statsDataDir.Length + 1)) -> $($_.Name)"
}

# --- pack --------------------------------------------------------------------
Write-Host "== Creating pak"
$PakPath = Join-Path $OutputDir "DevouringAndDigesting.pak"
Invoke-Divine -a create-package -c lz4 -s $StagingDir -d $PakPath

# --- zip ---------------------------------------------------------------------
Write-Host "== Zipping pak"
Compress-Archive -Path $PakPath -DestinationPath (Join-Path $OutputDir "DevouringAndDigesting.zip") -Force

Remove-Item -Recurse -Force $StagingDir

Write-Host "== Build finished:"
Get-ChildItem $OutputDir -File | ForEach-Object { Write-Host ("   {0}  {1:N0} bytes" -f $_.Name, $_.Length) }
