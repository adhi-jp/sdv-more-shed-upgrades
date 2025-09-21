param(
  [string]$SrcDir = "src",
  [string]$TempDirName = "[CP] More Shed Upgrades",
  [string]$ZipName = "",
  [switch]$SetTimestamp,
  [DateTime]$TimestampValue = (Get-Date)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($msg) {
  Write-Host "[INFO] $msg"
}

function Write-ErrorAndExit($msg) {
  Write-Host "[ERROR] $msg" -ForegroundColor Red
  exit 1
}

function Set-AllTimestamps($Path, $DateTime) {
  Write-Info "Setting all timestamps to $DateTime..."
  Get-ChildItem -LiteralPath $Path -Recurse | ForEach-Object {
    $_.CreationTime = $DateTime
    $_.LastWriteTime = $DateTime
    $_.LastAccessTime = $DateTime
  }
}

# Initialize variables outside try block to ensure they're available in finally
$tempPath = $null

try {
  # Get the repository root (parent of scripts directory)
  $scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
  $repoRoot = Split-Path -Path $scriptDir -Parent
  Push-Location $repoRoot

  $srcPath = Join-Path $repoRoot $SrcDir
  if (-not (Test-Path $srcPath)) {
    Write-ErrorAndExit "Source directory '$srcPath' does not exist."
  }

  # Try to read version from src\manifest.json
  $manifestPath = Join-Path $srcPath 'manifest.json'
  $version = ''
  if (Test-Path $manifestPath) {
    try {
      $manifestText = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
      $manifest = ConvertFrom-Json $manifestText
      if ($manifest.Version) { $version = $manifest.Version }
    } catch {
      Write-Info "Warning: failed to read version from '$manifestPath' - proceeding without version."
    }
  } else {
    Write-Info "Warning: manifest.json not found at '$manifestPath' - proceeding without version."
  }

  # Determine zip name; include version if available
  if ([string]::IsNullOrWhiteSpace($ZipName)) {
    if (-not [string]::IsNullOrWhiteSpace($version)) {
      # sanitize version for filename (remove invalid chars)
      $safeVersion = ($version -replace '[\\/:*?"<>|]', '_')
      $ZipName = "MoreShedUpgrades_v${safeVersion}.zip"
    } else {
      $ZipName = "MoreShedUpgrades.zip"
    }
  }

  # Ensure build directory exists
  $buildDir = Join-Path $repoRoot "build"
  if (-not (Test-Path $buildDir)) {
    Write-Info "Creating build directory '$buildDir'"
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
  }

  $tempPath = Join-Path $buildDir $TempDirName
  if (Test-Path $tempPath) {
    Write-Info "Removing existing temporary directory '$tempPath'"
    Remove-Item -LiteralPath $tempPath -Recurse -Force
  }

  Write-Info "Copying '$srcPath' to temporary directory '$tempPath'..."
  Copy-Item -LiteralPath $srcPath -Destination $tempPath -Recurse -Force

  if ($SetTimestamp) {
    Set-AllTimestamps $tempPath $TimestampValue
  }

  $zipPath = Join-Path $buildDir $ZipName
  if (Test-Path $zipPath) {
    Write-Info "Removing existing zip '$zipPath'"
    Remove-Item -LiteralPath $zipPath -Force
  }

  Write-Info "Creating zip archive '$zipPath' from directory '$tempPath'..."
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory($tempPath, $zipPath)

  Write-Info "Zip created successfully: $zipPath"

} catch {
  Write-Host "An error occurred: $_" -ForegroundColor Red
  exit 1
} finally {
  # Cleanup temp directory if it exists
  if ($tempPath -and (Test-Path -LiteralPath $tempPath)) {
    Write-Info "Removing temporary directory '$tempPath'"
    try {
      Remove-Item -LiteralPath $tempPath -Recurse -Force -ErrorAction Stop
      Write-Info "Temporary directory removed successfully"
    } catch {
      Write-Host "Warning: Failed to remove temporary directory '$tempPath': $_" -ForegroundColor Yellow
    }
  }
  Pop-Location
}

Write-Info "Packing complete."
