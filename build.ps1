<#
.SYNOPSIS
Pack, sign, verify, and install an Arma 3 mod under P:\mods.
.EXAMPLE
.\build.ps1 -ModName CL_Antistasi_Tweaks -ModFolderName '@CL_Tweaks'
.EXAMPLE
.\build.ps1 -SourcePath 'P:\My Mod' -AddonPrefix My_Mod

Source can be an addon with config.cpp in its root, a mod with addon source
directories under addons, or a mod with existing PBOs under addons. A source
addon's $PBOPREFIX$.txt overrides its default prefix.
#>
[CmdletBinding()]
param(
    [string]$ModName,
    [string]$SourcePath,
    [string]$SourceRoot = 'P:\',
    [string]$OutputRoot = 'P:\mods',
    [string]$ModFolderName,
    [string]$AddonPrefix,
    [string]$ToolRoot = 'D:\SteamLibrary\steamapps\common\Arma 3 Tools',
    [string]$KeyName = 'CL_Mods'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file is missing: $Path" }
}
function Invoke-Tool([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$([IO.Path]::GetFileName($Executable)) failed with exit code $LASTEXITCODE" }
}
function Get-Prefix([string]$AddonSource, [string]$DefaultPrefix) {
    foreach ($name in @('$PBOPREFIX$.txt', '$PBOPREFIX$')) {
        $path = Join-Path $AddonSource $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $prefix = (Get-Content -LiteralPath $path -TotalCount 1).Trim()
            if ($prefix) { return $prefix }
        }
    }
    return $DefaultPrefix
}

if (-not $SourcePath) {
    if (-not $ModName) { throw 'Provide -ModName or -SourcePath.' }
    $SourcePath = Join-Path $SourceRoot $ModName
}
if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) { throw "Mod source folder is missing: $SourcePath" }
$source = (Resolve-Path -LiteralPath $SourcePath).Path
if (-not $ModName) { $ModName = Split-Path -Leaf $source }
$bareName = $ModName.TrimStart('@')
if (-not $ModFolderName) { $ModFolderName = '@' + $bareName }
if ($ModFolderName -match '[\\/]') { throw '-ModFolderName must be one folder name.' }

$builder = Join-Path $ToolRoot 'AddonBuilder\AddonBuilder.exe'
$signer = Join-Path $ToolRoot 'DSSignFile\DSSignFile.exe'
$checker = Join-Path $ToolRoot 'DSSignFile\DSCheckSignatures.exe'
$privateKey = Join-Path $ToolRoot ("DSSignFile\$KeyName.biprivatekey")
$publicKey = Join-Path $ToolRoot ("DSSignFile\$KeyName.bikey")
foreach ($file in @($builder, $signer, $checker, $privateKey, $publicKey)) { Assert-File $file }

$sourceAddons = @()
$packedPbos = @()
if (Test-Path -LiteralPath (Join-Path $source 'config.cpp') -PathType Leaf) {
    $sourceAddons = @($source)
} else {
    $addonsSource = Join-Path $source 'addons'
    if (Test-Path -LiteralPath $addonsSource -PathType Container) {
        $sourceAddons = @(Get-ChildItem -LiteralPath $addonsSource -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'config.cpp') -PathType Leaf } |
            ForEach-Object FullName)
        if ($sourceAddons.Count -eq 0) {
            $packedPbos = @(Get-ChildItem -LiteralPath $addonsSource -File -Filter '*.pbo' | ForEach-Object FullName)
        }
    }
}
if ($sourceAddons.Count -eq 0 -and $packedPbos.Count -eq 0) {
    throw 'No config.cpp or addons\*.pbo found. Pass an addon source folder or a mod folder.'
}
if ($AddonPrefix -and $sourceAddons.Count -ne 1) {
    throw '-AddonPrefix applies to one addon. Use $PBOPREFIX$.txt for each source folder in a multi-addon mod.'
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$stage = Join-Path $tempBase ('ArmaModBuild-' + [guid]::NewGuid().ToString('N'))
$stageSource = Join-Path $stage 'source'
$stageAddons = Join-Path $stage 'addons'
$stageKeys = Join-Path $stage 'keys'
New-Item -ItemType Directory -Path $stageSource, $stageAddons, $stageKeys -Force | Out-Null

try {
    if ($sourceAddons.Count -gt 0) {
        $multiple = $sourceAddons.Count -gt 1
        foreach ($addon in $sourceAddons) {
            $addonName = Split-Path -Leaf $addon
            $stagedAddon = Join-Path $stageSource $addonName
            New-Item -ItemType Directory -Path $stagedAddon -Force | Out-Null
            # A clean copy keeps VCS files, old PBOs and build scripts out of the archive.
            & robocopy.exe $addon $stagedAddon /E /R:1 /W:1 /NFL /NDL /NJH /NJS /XD .git .agents .codex .inspection node_modules /XF '*.pbo' '*.bisign' '*.bikey' '*.biprivatekey' '*.ps1' '*.md' | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "Could not stage $addonName (robocopy exit $LASTEXITCODE)." }

            $defaultPrefix = if ($multiple) { "$bareName\$addonName" } else { $bareName }
            $prefix = if ($AddonPrefix) { $AddonPrefix } else { Get-Prefix $addon $defaultPrefix }
            if ($prefix -notmatch '^[A-Za-z0-9_]+(\\[A-Za-z0-9_]+)*$') {
                throw "Invalid addon prefix '$prefix'. Supply -AddonPrefix or a valid prefix file."
            }
            Write-Host "Packing $addonName with prefix $prefix"
            Invoke-Tool $builder @($stagedAddon, $stageAddons, '-packonly', "-prefix=$prefix", '-clear', "-toolsDirectory=$ToolRoot")
            Assert-File (Join-Path $stageAddons "$addonName.pbo")
        }
    } else {
        foreach ($pbo in $packedPbos) { Copy-Item -LiteralPath $pbo -Destination $stageAddons -Force }
    }

    $builtPbos = @(Get-ChildItem -LiteralPath $stageAddons -File -Filter '*.pbo')
    if ($builtPbos.Count -eq 0) { throw 'No PBO was produced.' }
    Copy-Item -LiteralPath $publicKey -Destination $stageKeys -Force
    foreach ($pbo in $builtPbos) {
        Write-Host "Signing $($pbo.Name)"
        Invoke-Tool $signer @($privateKey, $pbo.FullName)
        $signatures = @(Get-ChildItem -LiteralPath $stageAddons -File -Filter ($pbo.Name + '.*.bisign'))
        if ($signatures.Count -ne 1) { throw "Expected one signature for $($pbo.Name), found $($signatures.Count)." }
    }
    Invoke-Tool $checker @($stageAddons, $stageKeys)

    $destination = Join-Path $OutputRoot $ModFolderName
    $destAddons = Join-Path $destination 'addons'
    $destKeys = Join-Path $destination 'keys'
    New-Item -ItemType Directory -Path $destAddons, $destKeys -Force | Out-Null
    foreach ($pbo in $builtPbos) {
        Copy-Item -LiteralPath $pbo.FullName -Destination $destAddons -Force
        Get-ChildItem -LiteralPath $stageAddons -File -Filter ($pbo.Name + '.*.bisign') |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $destAddons -Force }
    }
    Copy-Item -LiteralPath $publicKey -Destination $destKeys -Force
    foreach ($metadata in @('mod.cpp', 'meta.cpp', 'mod.paa', 'logo.paa')) {
        $file = Join-Path $source $metadata
        if (Test-Path -LiteralPath $file -PathType Leaf) { Copy-Item -LiteralPath $file -Destination $destination -Force }
    }
    Write-Host "Built, signed and verified $($builtPbos.Count) PBO(s): $destination"
} finally {
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    if ($resolvedStage.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
        $resolvedStage -ne $tempBase -and (Test-Path -LiteralPath $resolvedStage)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
