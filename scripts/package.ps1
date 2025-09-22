param(
  [string]$SrcDir = "src",
  [string]$TempDirName = "[CP] More Shed Upgrades",
  [string]$ZipName = "",
  [string]$SevenZipPath = $null,
  [switch]$SetTimestamp,
  [DateTime]$TimestampValue = (Get-Date)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($msg) {
  Write-Host "[INFO] $msg"
}

function Write-ErrorAndExit($msg, $ExitCode = 1) {
  Write-Host "[ERROR] $msg" -ForegroundColor Red
  exit $ExitCode
}

function Set-AllTimestamps($Path, $DateTime) {
  Write-Info "Setting all timestamps to $DateTime..."
  try {
    # Set on the root path itself first
    if (Test-Path -LiteralPath $Path) {
      $root = Get-Item -LiteralPath $Path -ErrorAction Stop
      $root.CreationTime = $DateTime
      $root.LastWriteTime = $DateTime
      $root.LastAccessTime = $DateTime
    }
    Get-ChildItem -LiteralPath $Path -Recurse -ErrorAction Stop | ForEach-Object {
      $_.CreationTime = $DateTime
      $_.LastWriteTime = $DateTime
      $_.LastAccessTime = $DateTime
    }
  } catch {
    Write-ErrorAndExit "Failed to set timestamps: $_"
  }
}

# Helper function to check for null or whitespace strings
function Test-IsNullOrWhiteSpace([string]$value) {
  return [string]::IsNullOrWhiteSpace($value)
}

# Resolve 7-Zip executable path from parameter, environment variables, or PATH
function Resolve-SevenZip([string]$PathParam) {
  function Resolve-Candidate([string]$cand) {
    if (Test-IsNullOrWhiteSpace $cand) { return $null }

    # If a directory is provided, try common exe names inside it
    if (Test-Path -LiteralPath $cand -PathType Container) {
      foreach ($exe in '7z.exe','7zz.exe','7za.exe','7zG.exe') {
        $p = Join-Path $cand $exe
        if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).Path }
      }
    }

    # If a file path is provided, accept it when it exists
    if (Test-Path -LiteralPath $cand -PathType Leaf) { return (Resolve-Path -LiteralPath $cand).Path }

    # Otherwise, treat as a command name and search PATH (applications only)
    $cmd = Get-Command $cand -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd) {
      # Prefer first match's Path
      $first = @($cmd)[0]
      if ($first -and $first.Path) { return $first.Path }
    }
    return $null
  }

  # 1) Explicit parameter
  $p = Resolve-Candidate $PathParam
  if ($p) { return $p }

  # 2) Environment variables
  $envCandidates = @(
    $env:SEVEN_ZIP_PATH,
    $env:SEVENZIP_PATH,
    $env:SEVEN_ZIP,
    $env:SEVENZIP,
    $env:ZIP7_PATH,
    $env:SEVEN_ZIP_EXE,
    $env:SEVENZIP_EXE
  ) | Where-Object { -not (Test-IsNullOrWhiteSpace $_) }

  foreach ($cand in $envCandidates) {
    $p = Resolve-Candidate $cand
    if ($p) { return $p }
  }

  # 3) Common command names in PATH
  foreach ($name in '7z','7zz','7za','7zG') {
    $p = Resolve-Candidate $name
    if ($p) { return $p }
  }

  Write-ErrorAndExit "7-Zip executable not found. Provide -SevenZipPath or set environment variable (e.g., SEVEN_ZIP_PATH)."
}

# Function to get version from manifest.json
function Get-VersionFromManifest([string]$SrcPath) {
  $manifestPath = Join-Path $SrcPath 'manifest.json'
  if (-not (Test-Path $manifestPath)) {
    Write-Info "Warning: manifest.json not found at '$manifestPath' - proceeding without version."
    return ''
  }

  try {
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
    $manifest = ConvertFrom-Json $manifestText
    if ($manifest.Version) {
      return $manifest.Version
    } else {
      return ''
    }
  } catch {
    Write-Info "Warning: failed to read version from '$manifestPath' - proceeding without version."
    return ''
  }
}

# Function to generate ZIP filename
function Get-ZipFileName([string]$ZipName, [string]$Version) {
  if (-not (Test-IsNullOrWhiteSpace $ZipName)) {
    return $ZipName
  }

  if (-not (Test-IsNullOrWhiteSpace $Version)) {
    $safeVersion = ($Version -replace '[\\/:*?"<>|]', '_')
    return "MoreShedUpgrades_v${safeVersion}.zip"
  }

  return "MoreShedUpgrades.zip"
}

# Function to execute 7-Zip compression
function Invoke-SevenZipCompress([string]$SevenZipExe, [string]$ZipName, [string]$TempDirName) {
  $compressionArgs = @(
    'a',           # Add to archive
    '-tzip',       # Zip format
    '-mx=9',       # Maximum compression
    '-mm=Deflate', # Deflate method
    '-mcu=on',     # UTF-8 encoding
    '-y',          # Yes to all prompts
    $ZipName,
    $TempDirName
  )

  Write-Info "Creating zip archive '$ZipName' from folder '$TempDirName' via 7-Zip..."
  & $SevenZipExe @compressionArgs | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "7-Zip compression failed with exit code $LASTEXITCODE"
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

  $version = Get-VersionFromManifest $srcPath
  $ZipName = Get-ZipFileName $ZipName $version

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

  # Create zip via 7-Zip so that internal paths use forward slashes across OSes
  $sevenZipExe = Resolve-SevenZip -PathParam $SevenZipPath
  Write-Info "Using 7-Zip: $sevenZipExe"

  Push-Location $buildDir
  try {
    Invoke-SevenZipCompress $sevenZipExe $ZipName $TempDirName
  } finally {
    Pop-Location
  }

  Write-Info "Zip created successfully: $zipPath"

} catch {
  Write-ErrorAndExit "Package creation failed: $_"
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
