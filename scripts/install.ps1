# ENSI one-command installer (Windows / PowerShell)
# Usage:
#   irm https://raw.githubusercontent.com/Hariprasad-UP/ENSI/main/scripts/install.ps1 | iex
#
# Auto-detects CPU architecture and installs the matching ENSI release.
# NOTE: requires published GitHub Releases assets to actually download a build.

$ErrorActionPreference = 'Stop'
$Repo       = 'Hariprasad-UP/ENSI'
$InstallDir = if ($env:ENSI_INSTALL_DIR) { $env:ENSI_INSTALL_DIR } else { "$env:LOCALAPPDATA\ENSI" }

function Info($m) { Write-Host "[ENSI] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[ENSI] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[ENSI] $m" -ForegroundColor Red; exit 1 }

# --- 1. Detect architecture -------------------------------------------------
$archRaw = $env:PROCESSOR_ARCHITECTURE
switch ($archRaw) {
  'AMD64' { $Arch = 'x64' }
  'ARM64' { $Arch = 'arm64' }
  'x86'   { Die 'ENSI requires 64-bit Windows (x86 not supported).' }
  default { Die "Unsupported architecture: $archRaw" }
}
Info "Detected platform: windows-$Arch"

# --- 2. Asset pattern -------------------------------------------------------
$AssetPattern = "ensi-windows-$Arch.exe"

# --- 3. Resolve latest release ----------------------------------------------
Info "Resolving latest release from $Repo..."
$headers = @{ 'User-Agent' = 'ENSI-Installer'; 'Accept' = 'application/vnd.github+json' }
try {
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
} catch {
  Die "Could not query GitHub releases: $($_.Exception.Message)"
}

$asset = $release.assets | Where-Object { $_.name -eq $AssetPattern } | Select-Object -First 1
if (-not $asset) {
  Warn "No published release asset named '$AssetPattern' was found."
  Warn "Publish a GitHub Release with platform assets, or build locally:"
  Warn "    flutter build windows --release"
  Die  "Aborting: nothing to download yet."
}

# --- 4. Download + install --------------------------------------------------
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$Out = Join-Path $InstallDir $AssetPattern
Info "Downloading $($asset.browser_download_url)"
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $Out -Headers $headers

# Optional checksum verification (if a .sha256 sibling asset exists)
$sumAsset = $release.assets | Where-Object { $_.name -eq "$AssetPattern.sha256" } | Select-Object -First 1
if ($sumAsset) {
  Info 'Verifying checksum...'
  $expected = (Invoke-WebRequest -Uri $sumAsset.browser_download_url -Headers $headers).Content.Split(' ')[0].Trim()
  $actual   = (Get-FileHash -Algorithm SHA256 -Path $Out).Hash.ToLower()
  if ($expected.ToLower() -ne $actual) { Die 'Checksum mismatch!' }
}

# --- 5. Add to PATH (user) --------------------------------------------------
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$InstallDir*") {
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$InstallDir", 'User')
  Info "Added $InstallDir to your user PATH (restart the terminal to use 'ensi')."
}

Info "Installed to $Out"
Info "Done. Launch ENSI and follow the pairing prompts."
