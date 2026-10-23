# Windows App Updater

Interactive Windows updater that checks **winget** and **Chocolatey** for available updates, merges both results into one table, and lets you update all packages, exclude packages, or select specific ones.

## Install with PowerShell (one line)

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/subhasishsahugit/windows-app-updater/main/install.ps1 | iex
```

The installer will:

1. Ask for UAC elevation.
2. Install Git for Windows with winget if Git Bash is missing.
3. Install Chocolatey if missing, using the official MSI with SHA-256 and Authenticode verification.
4. Clone this repo to `%USERPROFILE%\windows-app-updater`.
5. Create `Update Apps.lnk` on the Desktop.
6. Start the updater.

The script is plain PowerShell. If you want to inspect it first:

```powershell
irm https://raw.githubusercontent.com/subhasishsahugit/windows-app-updater/main/install.ps1
```

## Install with Bash

```bash
git clone https://github.com/subhasishsahugit/windows-app-updater.git
cd windows-app-updater
bash update-apps.sh
```

If Chocolatey is not installed:

```bash
bash update-apps.sh --install-choco
```

`--install-choco` downloads the official Chocolatey MSI, verifies its SHA-256 against Microsoft's official winget manifest, checks the Chocolatey Authenticode signature, and installs it with UAC.

Direct links:

- [update-apps.sh](https://github.com/subhasishsahugit/windows-app-updater/blob/main/update-apps.sh)
- [install-choco.ps1](https://github.com/subhasishsahugit/windows-app-updater/blob/main/install-choco.ps1)

If you download only `update-apps.sh`, keep `install-choco.ps1` next to it to use `--install-choco`.

## What it does

- Queries `winget upgrade` and `choco outdated`.
- Merges both lists into one alphabetically sorted table. The `SOURCE` column shows whether winget or Chocolatey will perform each update.
- Keeps duplicate app names when the same program is managed by both managers, because each manager updates its own installation.
- Runs winget updates first, then Chocolatey updates (Chocolatey itself first).
- Writes a transcript to `%USERPROFILE%\update-logs`.

Menu:

| Key | Action |
| --- | --- |
| `A` | Update all packages |
| `E` | Exclude packages and update the rest |
| `S` | Select only specific packages |
| `Q` | Quit without changing anything |

Selections accept ranges, for example `2 5 7-9`.

## Options

```text
-y, --yes          Update all packages without asking for confirmation
-n, --dry-run      List available updates and exit
    --no-silent    Do not pass --silent to winget (installers may show UI)
    --install-choco
                   Install Chocolatey from the official MSI with SHA-256
                   verification, then exit
-h, --help         Show help
```

## Desktop shortcut

The PowerShell installer creates `Update Apps.lnk` on the Desktop. It opens Mintty/Git Bash and runs the updater.

Chocolatey upgrades require Administrator privileges. Right-click the shortcut and choose **Run as administrator** when Chocolatey updates are listed. winget updates work without elevation.

## Security

- Chocolatey is bootstrapped from the official MSI:
  `https://github.com/chocolatey/choco/releases/download/2.7.4/chocolatey-2.7.4.0.msi`
- The expected SHA-256 is pinned from Microsoft's official winget manifest for `Chocolatey.Chocolatey` 2.7.4.0:
  `F39EFEBDC012525A7057F573F136F63AF91A496EFDDD1DB4C7910D657A5AC407`
- The installer also requires a valid Authenticode signature from `Chocolatey Software, Inc`.
- Installation is refused if either check fails.
- winget and Chocolatey verify the hashes and checksums of the packages they install and upgrade as part of their normal operation.

## Requirements

- Windows 10 or Windows 11
- winget (App Installer)
- PowerShell 5.1 or newer for the one-line installer
- Git for Windows (the installer installs it via winget if missing)
- Chocolatey (the installer installs it if missing)

## Troubleshooting

- **`winget` not found**: install **App Installer** from the Microsoft Store, then run the installer again.
- **`choco` not found in an older terminal**: open a new terminal. The updater also falls back to `C:\ProgramData\chocolatey\bin\choco.exe`.
- **Chocolatey updates fail with access denied**: run the updater as Administrator.
- **Logs**: `%USERPROFILE%\update-logs`.
- **Shortcut does not open**: verify that `C:\Program Files\Git\usr\bin\mintty.exe` exists; reinstall Git for Windows if needed.

## Repository layout

| File | Purpose |
| --- | --- |
| `update-apps.sh` | Main interactive updater |
| `install-choco.ps1` | SHA-256 and signature verified Chocolatey bootstrap |
| `install.ps1` | One-line PowerShell installer: dependencies, clone, shortcut, launch |
| `README.md` | Documentation |
