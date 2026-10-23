#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the Windows App Updater from GitHub and launches it.

.DESCRIPTION
    One-line installer:

        irm https://raw.githubusercontent.com/subhasishsahugit/windows-app-updater/main/install.ps1 | iex

    It self-elevates, installs Git for Windows via winget if needed, installs
    Chocolatey if needed (SHA-256 + Authenticode verified), clones the repo to
    %USERPROFILE%\windows-app-updater, creates a Desktop shortcut, and starts
    the updater.

.NOTES
    Repository: https://github.com/subhasishsahugit/windows-app-updater
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$GitHubOwner = 'subhasishsahugit'
$RepoName    = 'windows-app-updater'
$Branch      = 'main'
$RepoUrl     = "https://github.com/$GitHubOwner/$RepoName.git"
$RawBase     = "https://raw.githubusercontent.com/$GitHubOwner/$RepoName/$Branch"
$ScriptUrl   = "$RawBase/install.ps1"
$InstallDir  = Join-Path $env:USERPROFILE $RepoName

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Yellow
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

trap {
    Write-Host "`nInstallation failed: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}

# Self-elevate when started from a normal PowerShell window.
if (-not (Test-Admin)) {
    Write-Step 'Requesting Administrator privileges'
    $tempScript = Join-Path $env:TEMP 'install-windows-app-updater.ps1'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-WebRequest -Uri $ScriptUrl -OutFile $tempScript -UseBasicParsing
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', "`"$tempScript`""
        )
        if ($proc.ExitCode -ne 0) {
            Write-Warn "Elevated installer exited with code $($proc.ExitCode)."
            exit $proc.ExitCode
        }
    } catch {
        Write-Warn "Elevation was cancelled or failed: $($_.Exception.Message)"
        exit 1
    } finally {
        Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

Write-Step 'Windows App Updater installer'
Write-Host "    Install directory: $InstallDir"

# 1. Git for Windows / Git Bash.
Write-Step 'Checking Git for Windows'
$gitRoot = 'C:\Program Files\Git'
$bashExe = Join-Path $gitRoot 'bin\bash.exe'

if (-not (Test-Path -LiteralPath $bashExe)) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $candidate) {
            $winget = $candidate
        }
    }
    if (-not $winget) {
        throw "winget was not found. Install 'App Installer' from the Microsoft Store, then run this installer again."
    }

    Write-Host '    Installing Git for Windows with winget...'
    & $winget install --id Git.Git --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "winget returned exit code $LASTEXITCODE; checking for Git anyway."
    }
}

$candidates = @(
    'C:\Program Files\Git\bin\bash.exe',
    'C:\Program Files (x86)\Git\bin\bash.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
)
$bashExe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $bashExe) {
    throw 'Git Bash was not found after installation. Install Git for Windows and rerun.'
}

$gitRoot = Split-Path -Parent (Split-Path -Parent $bashExe)
$gitExe = Join-Path $gitRoot 'cmd\git.exe'
if (-not (Test-Path -LiteralPath $gitExe)) {
    $gitExe = Join-Path $gitRoot 'bin\git.exe'
}
$mintty = Join-Path $gitRoot 'usr\bin\mintty.exe'
if (-not (Test-Path -LiteralPath $mintty)) {
    throw "Mintty was not found at $mintty. Reinstall Git for Windows."
}
Write-Ok "Git Bash: $bashExe"
Write-Ok "Mintty:   $mintty"

# 2. Clone or update the repo.
Write-Step 'Installing updater files'
$gitDir = Join-Path $InstallDir '.git'
if (Test-Path -LiteralPath $gitDir) {
    Write-Host "    Updating existing clone in $InstallDir"
    & $gitExe -C $InstallDir pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'Could not update the existing clone; using the files already present.'
    }
} elseif (Test-Path -LiteralPath $InstallDir) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallDir 'update-apps.sh'))) {
        throw "The install directory already exists and is not a git clone: $InstallDir"
    }
    Write-Warn "Using existing files in $InstallDir (not a git clone)."
} else {
    & $gitExe clone --depth 1 --branch $Branch $RepoUrl $InstallDir
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE."
    }
}

$updater = Join-Path $InstallDir 'update-apps.sh'
if (-not (Test-Path -LiteralPath $updater)) {
    throw "update-apps.sh was not found in $InstallDir."
}
Write-Ok "Updater: $updater"

# 3. Chocolatey.
Write-Step 'Checking Chocolatey'
$chocoExe = Join-Path $env:ProgramData 'chocolatey\bin\choco.exe'
$chocoFound = (Get-Command choco.exe -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $chocoExe)
if ($chocoFound) {
    Write-Ok 'Chocolatey is already installed.'
} else {
    $chocoInstaller = Join-Path $InstallDir 'install-choco.ps1'
    if (-not (Test-Path -LiteralPath $chocoInstaller)) {
        throw "install-choco.ps1 was not found in $InstallDir."
    }
    Write-Host '    Installing Chocolatey (SHA-256 + signature verified)...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $chocoInstaller -LogPath (Join-Path $env:TEMP 'choco-install.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Chocolatey installation failed with exit code $LASTEXITCODE."
    }
    Write-Ok 'Chocolatey installed.'
}

# 4. Desktop shortcut.
Write-Step 'Creating Desktop shortcut'
$bashDir = '/' + $InstallDir.Substring(0, 1).ToLowerInvariant() + ($InstallDir.Substring(2) -replace '\\', '/')
$shortcutArgs = "-h always -t `"Windows App Updater`" -e `"$bashExe`" -lc `"cd '$bashDir' && bash ./update-apps.sh`""
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'Update Apps.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $mintty
$shortcut.Arguments = $shortcutArgs
$shortcut.WorkingDirectory = $InstallDir
$shortcut.IconLocation = "$gitRoot\git-bash.exe,0"
$shortcut.Description = 'Update installed apps with winget and Chocolatey'
$shortcut.WindowStyle = 1
$shortcut.Save()
Write-Ok "Shortcut: $shortcutPath"

# 5. Launch.
Write-Step 'Starting Windows App Updater'
Start-Process -FilePath $mintty -ArgumentList $shortcutArgs
Write-Ok 'Done.'
