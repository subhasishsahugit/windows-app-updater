#Requires -Version 5.1
<#
.SYNOPSIS
    Installs Chocolatey CLI from the official MSI with SHA-256 verification.

.DESCRIPTION
    Downloads the official Chocolatey MSI and verifies it before running it:

      1. SHA-256 must match the hash published in the official Microsoft
         winget manifest for Chocolatey.Chocolatey.
      2. The MSI must have a valid Authenticode signature from
         "Chocolatey Software, Inc".

    Only then is msiexec allowed to install it.

    Must be run as Administrator for the actual install. Use -VerifyOnly to
    download and check without installing (works without Administrator).

.PARAMETER LogPath
    Transcript path. Defaults to %TEMP%\install-choco-<timestamp>.log.

.PARAMETER InstallerUrl
    Official MSI URL. Defaults to the pinned Chocolatey 2.7.4.0 release.

.PARAMETER ExpectedSha256
    Expected MSI hash. Defaults to the hash published in the winget manifest.

.PARAMETER VerifyOnly
    Download and verify only; do not install.

.NOTES
    Pinned version: 2.7.4.0
    Winget manifest:
      https://github.com/microsoft/winget-pkgs/blob/master/manifests/c/Chocolatey/Chocolatey/2.7.4.0/Chocolatey.Chocolatey.installer.yaml
    Official MSI:
      https://github.com/chocolatey/choco/releases/download/2.7.4/chocolatey-2.7.4.0.msi
#>
[CmdletBinding()]
param(
    [string]$LogPath = (Join-Path $env:TEMP ("install-choco-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [string]$InstallerUrl = 'https://github.com/chocolatey/choco/releases/download/2.7.4/chocolatey-2.7.4.0.msi',
    [string]$ExpectedSha256 = 'F39EFEBDC012525A7057F573F136F63AF91A496EFDDD1DB4C7910D657A5AC407',
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'

$logDir = Split-Path -Parent $LogPath
if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Log "Chocolatey bootstrap installer"
Write-Log "Expected SHA256: $ExpectedSha256"

if (-not $VerifyOnly -and -not (Test-IsAdmin)) {
    throw "Administrator privileges are required. Run 'bash update-apps.sh --install-choco' so it can elevate, or run PowerShell as Administrator."
}

# Already installed? Do not touch it.
$existing = Get-Command choco -CommandType Application -ErrorAction SilentlyContinue
$defaultChoco = Join-Path $env:ProgramData 'chocolatey\bin\choco.exe'
if ($existing) {
    Write-Log "Chocolatey is already installed: $($existing.Source)"
    exit 0
}
if (Test-Path -LiteralPath $defaultChoco) {
    Write-Log "Chocolatey is already installed: $defaultChoco"
    exit 0
}

# Download the official MSI.
$msiName = [IO.Path]::GetFileName(([Uri]$InstallerUrl).AbsolutePath)
$msiPath = Join-Path $env:TEMP $msiName
if (Test-Path -LiteralPath $msiPath) {
    Remove-Item -LiteralPath $msiPath -Force
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
} catch {
    Write-Log "Warning: could not force TLS 1.2: $($_.Exception.Message)"
}

Write-Log "Downloading $InstallerUrl"
Invoke-WebRequest -Uri $InstallerUrl -OutFile $msiPath -UseBasicParsing
Write-Log "Downloaded to $msiPath ($((Get-Item -LiteralPath $msiPath).Length) bytes)"

# 1. SHA-256 verification.
$actualSha256 = (Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash.ToUpperInvariant()
Write-Log "Actual SHA256:   $actualSha256"

if ($actualSha256 -ne $ExpectedSha256.ToUpperInvariant()) {
    Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
    throw "SHA256 verification FAILED. Expected $ExpectedSha256 but got $actualSha256. The installer was not run."
}
Write-Log "SHA256 verification passed."

# 2. Authenticode signature verification.
$signature = Get-AuthenticodeSignature -FilePath $msiPath
if ($signature.Status -ne 'Valid') {
    throw "Authenticode signature check FAILED with status '$($signature.Status)'. The installer was not run."
}
if ($signature.SignerCertificate.Subject -notlike '*Chocolatey Software, Inc*') {
    throw "Unexpected signer '$($signature.SignerCertificate.Subject)'. The installer was not run."
}
Write-Log "Authenticode signature valid: $($signature.SignerCertificate.Subject)"

if ($VerifyOnly) {
    Write-Log "Verify-only requested; not installing."
    exit 0
}

# 3. Install.
$msiLog = "$LogPath.msi.log"
Write-Log "Installing Chocolatey with msiexec (MSI log: $msiLog)"
$msiArguments = @('/i', "`"$msiPath`"", '/qn', '/norestart', '/l*v', "`"$msiLog`"")
$process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArguments -Wait -PassThru -NoNewWindow
Write-Log "msiexec exit code: $($process.ExitCode)"

# 0 = success, 3010 = reboot required, 1603 = already installed
if ($process.ExitCode -notin @(0, 1603, 3010)) {
    throw "msiexec failed with exit code $($process.ExitCode). See $msiLog for details."
}

# 4. Verify the result.
if (-not (Test-Path -LiteralPath $defaultChoco)) {
    throw "Installation finished but $defaultChoco was not found."
}
$chocoVersion = & $defaultChoco --version
Write-Log "Chocolatey installed: $chocoVersion"
Write-Log "Location: $defaultChoco"
Write-Log "Done. Open a new terminal so 'choco' is available on PATH."
