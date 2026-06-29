param(
    [ValidateSet('x86_64','i686','aarch64')]
    [string]$Architecture = 'x86_64',

    [string]$OutDir = '',

    [switch]$KeepWorkDir
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Assert-File {
    param([string]$Path, [string]$Message)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw $Message
    }
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptRoot '..')
$RepoRoot = $RepoRoot.Path
$AppDir = Join-Path $RepoRoot 'app'
$RuntimeAppDir = Join-Path $AppDir 'lwtt_app'
$DocsDir = Join-Path $RepoRoot 'docs'

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $RepoRoot 'dist'
}

if (-not (Test-Path -LiteralPath $AppDir -PathType Container)) {
    throw "Folder not found: $AppDir. Run this script from the repository that contains the app folder."
}

$VersionFile = Join-Path $RepoRoot 'VERSION'
$LWTTVersion = 'unknown'
if (Test-Path -LiteralPath $VersionFile -PathType Leaf) {
    $LWTTVersion = (Get-Content -LiteralPath $VersionFile -Encoding UTF8 | Select-Object -First 1).Trim()
}
if ([string]::IsNullOrWhiteSpace($LWTTVersion)) { $LWTTVersion = 'unknown' }

Assert-File (Join-Path $AppDir 'lwtt_tray_start.bat') 'LWTT app file is missing: app\lwtt_tray_start.bat'
Assert-File (Join-Path $RuntimeAppDir 'lwtt_tray.ps1') 'LWTT app file is missing: app\lwtt_app\lwtt_tray.ps1'
Assert-File (Join-Path $RuntimeAppDir 'lwtt_common.ps1') 'LWTT app file is missing: app\lwtt_app\lwtt_common.ps1'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$WorkRoot = Join-Path ([IO.Path]::GetTempPath()) ("lwtt_bundle_" + [Guid]::NewGuid().ToString('N'))
$DownloadDir = Join-Path $WorkRoot 'download'
$ExtractDir = Join-Path $WorkRoot 'trusttunnel_extract'
$BundleRoot = Join-Path $WorkRoot 'bundle'
$BundleRuntimeDir = Join-Path $BundleRoot 'lwtt_app'
New-Item -ItemType Directory -Force -Path $DownloadDir, $ExtractDir, $BundleRoot, $BundleRuntimeDir | Out-Null

try {
    Write-Step 'Reading latest TrustTunnelClient release from GitHub'
    $ReleaseApi = 'https://api.github.com/repos/TrustTunnel/TrustTunnelClient/releases/latest'
    $Headers = @{ 'User-Agent' = 'LWTT-Client-Bundle-Builder' }
    $Release = Invoke-RestMethod -Uri $ReleaseApi -Headers $Headers
    $TrustTunnelTag = [string]$Release.tag_name
    if ([string]::IsNullOrWhiteSpace($TrustTunnelTag)) { throw 'Could not determine latest TrustTunnelClient version from GitHub.' }

    $Pattern = "windows-$Architecture\.zip$"
    $Asset = $Release.assets | Where-Object { $_.name -match $Pattern -and $_.name -match '^trusttunnel_client-' } | Select-Object -First 1
    if (-not $Asset) {
        $Names = ($Release.assets | ForEach-Object { $_.name }) -join "`n"
        throw "Could not find TrustTunnelClient Windows asset for architecture '$Architecture'. Available assets:`n$Names"
    }

    $TrustTunnelZip = Join-Path $DownloadDir $Asset.name
    Write-Host "TrustTunnelClient release: $TrustTunnelTag"
    Write-Host "Selected asset: $($Asset.name)"
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $TrustTunnelZip -Headers $Headers
    Expand-Archive -LiteralPath $TrustTunnelZip -DestinationPath $ExtractDir -Force

    $TrustTunnelExe = Get-ChildItem -LiteralPath $ExtractDir -Recurse -File -Filter 'trusttunnel_client.exe' | Select-Object -First 1
    if (-not $TrustTunnelExe) { throw 'Downloaded TrustTunnelClient archive does not contain trusttunnel_client.exe.' }
    $TrustTunnelRoot = $TrustTunnelExe.Directory.FullName
    $WintunDll = Get-ChildItem -LiteralPath $TrustTunnelRoot -Recurse -File -Filter 'wintun.dll' | Select-Object -First 1
    if (-not $WintunDll) { throw 'Downloaded TrustTunnelClient archive does not contain wintun.dll.' }

    Copy-Item -LiteralPath (Join-Path $AppDir '*') -Destination $BundleRoot -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $TrustTunnelRoot '*') -Destination $BundleRuntimeDir -Recurse -Force

    $QuickStart = Join-Path $DocsDir 'QUICK_START_BUNDLE_RU.txt'
    if (Test-Path -LiteralPath $QuickStart -PathType Leaf) {
        Copy-Item -LiteralPath $QuickStart -Destination (Join-Path $BundleRuntimeDir 'README_QUICK_START_RU.txt') -Force
    }

    Set-Content -LiteralPath (Join-Path $BundleRuntimeDir 'BUILD_INFO.txt') -Value @"
LW TrustTunnel Client version: $LWTTVersion
TrustTunnelClient release: $TrustTunnelTag
TrustTunnelClient asset: $($Asset.name)
Target: windows_$Architecture
Built at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Builder: tools\build_bundle.ps1
"@ -Encoding UTF8

    $SensitivePaths = @('lwtt_app\profiles','lwtt_app\log','lwtt_app\profiles\certificates','lwtt_app\profiles\backups')
    foreach ($Rel in $SensitivePaths) {
        $Path = Join-Path $BundleRoot $Rel
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
    }
    Get-ChildItem -LiteralPath $BundleRoot -Recurse -Force -File | Where-Object {
        $_.Name -ieq 'lwtt_client.toml' -or $_.Name -ieq 'trusttunnel_client.likeweb.toml' -or $_.Name -like '*.pem' -or $_.Name -like '*diagnostic*.txt' -or $_.Name -like '*.pid' -or $_.Name -like '*.log'
    } | Remove-Item -Force

    Assert-File (Join-Path $BundleRoot 'lwtt_tray_start.bat') 'Bundle validation failed: lwtt_tray_start.bat is missing.'
    Assert-File (Join-Path $BundleRuntimeDir 'trusttunnel_client.exe') 'Bundle validation failed: trusttunnel_client.exe is missing in lwtt_app.'
    Assert-File (Join-Path $BundleRuntimeDir 'wintun.dll') 'Bundle validation failed: wintun.dll is missing in lwtt_app.'
    Assert-File (Join-Path $BundleRuntimeDir 'lwtt_tray.ps1') 'Bundle validation failed: lwtt_tray.ps1 is missing in lwtt_app.'

    foreach ($Item in (Get-ChildItem -LiteralPath $BundleRoot -Force)) {
        if ($Item.Name -ne 'lwtt_tray_start.bat' -and $Item.Name -ne 'lwtt_app') { throw "Unexpected item in ZIP root: $($Item.Name)" }
    }

    $SafeTTVersion = $TrustTunnelTag.TrimStart('v')
    $BundleName = "LWTT_Client_Bundle_v$LWTTVersion`_trusttunnel_v$SafeTTVersion`_windows_$Architecture.zip"
    $LatestName = "LWTT_Client_Bundle_windows_$Architecture.zip"
    $BundleZip = Join-Path $OutDir $BundleName
    $LatestZip = Join-Path $OutDir $LatestName
    Remove-Item -LiteralPath $BundleZip, $LatestZip, "$BundleZip.sha256", "$LatestZip.sha256" -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $BundleRoot '*') -DestinationPath $BundleZip -Force
    Copy-Item -LiteralPath $BundleZip -Destination $LatestZip -Force
    $Hash1 = Get-FileHash -LiteralPath $BundleZip -Algorithm SHA256
    $Hash2 = Get-FileHash -LiteralPath $LatestZip -Algorithm SHA256
    Set-Content -LiteralPath "$BundleZip.sha256" -Value ($Hash1.Hash.ToLower() + '  ' + (Split-Path -Leaf $BundleZip)) -Encoding ASCII
    Set-Content -LiteralPath "$LatestZip.sha256" -Value ($Hash2.Hash.ToLower() + '  ' + (Split-Path -Leaf $LatestZip)) -Encoding ASCII
    Write-Host "Bundle created successfully:" -ForegroundColor Green
    Write-Host $LatestZip -ForegroundColor Green
}
finally {
    if ($KeepWorkDir) { Write-Host "Temporary build folder was kept: $WorkRoot" }
    elseif (Test-Path -LiteralPath $WorkRoot) { Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
