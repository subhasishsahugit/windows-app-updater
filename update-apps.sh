#!/usr/bin/env bash
# =============================================================================
#  update-apps.sh - interactive updater for winget + Chocolatey on Windows
#
#  Requirements:
#    - Git Bash (recommended) or MSYS2, bash 4+
#    - winget (App Installer) and/or Chocolatey
#
#  Quick start (from Git Bash):
#    bash ~/update-apps.sh
#
#  Options:
#    -y, --yes        update all packages without asking for confirmation
#    -n, --dry-run    list available updates and exit
#        --no-silent  do not pass --silent to winget (installers may show UI)
#        --install-choco  install Chocolatey (SHA-256 verified) and exit
#    -h, --help       show this help
#
#  Every run writes a transcript to ~/update-logs/.
#  Chocolatey upgrades need an Administrator terminal; winget runs normally.
# =============================================================================

set -uo pipefail

trap 'printf "\nInterrupted.\n"; exit 130' INT

SCRIPT_VERSION="1.1.0"
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"

ASSUME_YES=0
DRY_RUN=0
WINGET_SILENT=1
INSTALL_CHOCO=0

usage() {
  cat <<'EOF'
update-apps.sh - interactive updater for winget + Chocolatey

Usage:
  bash update-apps.sh [options]

Options:
  -y, --yes        Update all packages without asking for confirmation.
  -n, --dry-run    Only list available updates; change nothing.
      --no-silent  Do not pass --silent to winget (installers may show UI).
      --install-choco
                   Install Chocolatey from the official MSI with SHA-256
                   verification, then exit.
  -h, --help       Show this help.

The script lists every available update from the official winget and
Chocolatey sources in one merged list, then lets you:

  A  update everything
  E  exclude some packages and update the rest
  S  select only specific packages to update
  Q  quit without changing anything

Logs are written to ~/update-logs/.

Chocolatey upgrades require an Administrator terminal. winget upgrades run
with your normal user account (Windows asks for elevation when needed).
EOF
}

while (($# > 0)); do
  case "$1" in
    -y|--yes)      ASSUME_YES=1 ;;
    -n|--dry-run)  DRY_RUN=1 ;;
    --no-silent)   WINGET_SILENT=0 ;;
    --install-choco) INSTALL_CHOCO=1 ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; break ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# ------------------------------------------------------------------- colors --
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_CYAN=""
fi

# ------------------------------------------------------- install chocolatey --
# Bootstraps Chocolatey from the official MSI with SHA-256 + Authenticode
# verification (install-choco.ps1, kept next to this script), then exits.
if [ "$INSTALL_CHOCO" -eq 1 ]; then
  printf '\n%sChocolatey installer%s (official MSI, SHA-256 verified)\n\n' "$C_BOLD" "$C_RESET"

  if command -v choco >/dev/null 2>&1 || [ -x /c/ProgramData/chocolatey/bin/choco.exe ]; then
    printf 'Chocolatey is already installed.\n'
    exit 0
  fi

  SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" && pwd)
  PS1="$SCRIPT_DIR/install-choco.ps1"
  if [ ! -f "$PS1" ]; then
    printf 'Cannot find install-choco.ps1 next to update-apps.sh (%s).\n' "$PS1" >&2
    exit 1
  fi
  if ! command -v powershell.exe >/dev/null 2>&1; then
    printf 'powershell.exe was not found.\n' >&2
    exit 1
  fi
  if ! command -v cygpath >/dev/null 2>&1; then
    printf 'cygpath was not found (run this from Git Bash).\n' >&2
    exit 1
  fi

  LOG_DIR="${HOME:-/tmp}/update-logs"
  if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    printf 'Cannot create log directory: %s\n' "$LOG_DIR" >&2
    exit 1
  fi
  CHOCO_LOG="$LOG_DIR/choco-install-$(date '+%Y%m%d-%H%M%S').log"

  WIN_PS1=$(cygpath -w "$PS1")
  WIN_LOG=$(cygpath -w "$CHOCO_LOG")
  # Escape single quotes for the PowerShell command string.
  WIN_PS1=${WIN_PS1//\'/\'\'}
  WIN_LOG=${WIN_LOG//\'/\'\'}

  printf 'A Windows UAC prompt will appear. Approve it to install Chocolatey.\n\n'
  if ! powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
    "Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','$WIN_PS1','-LogPath','$WIN_LOG')"; then
    printf '\nElevation was cancelled or failed. Chocolatey was not installed.\n' >&2
    exit 1
  fi

  printf '\n'
  if [ -f "$CHOCO_LOG" ]; then
    cat "$CHOCO_LOG"
  fi

  if [ -x /c/ProgramData/chocolatey/bin/choco.exe ]; then
    printf '\nChocolatey installed. Open a new terminal, then run this script normally.\n'
    exit 0
  fi

  printf '\nChocolatey installation did not complete. See %s\n' "$CHOCO_LOG" >&2
  exit 1
fi

# -------------------------------------------------------------- find tools --
find_tool() {
  local cmd=$1 exe=$2
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '%s' "$cmd"
    return 0
  fi
  if command -v "$exe" >/dev/null 2>&1; then
    printf '%s' "$exe"
    return 0
  fi
  return 1
}

WINGET="$(find_tool winget winget.exe || true)"
CHOCO="$(find_tool choco choco.exe || true)"

# A terminal opened before Chocolatey was installed may not have the updated
# machine PATH yet. Fall back to the default install location so winget and
# Chocolatey are both searched in every terminal.
if [ -z "$CHOCO" ] && [ -x /c/ProgramData/chocolatey/bin/choco.exe ]; then
  CHOCO=/c/ProgramData/chocolatey/bin/choco.exe
fi

# ------------------------------------------------------------------- banner --
printf '\n%s============================================================%s\n' "$C_BOLD" "$C_RESET"
printf '%s  Windows App Updater %s%s\n' "$C_BOLD" "$SCRIPT_VERSION" "$C_RESET"
printf '  winget + Chocolatey (official sources)\n'
printf '%s============================================================%s\n\n' "$C_BOLD" "$C_RESET"

if [ -z "$WINGET" ]; then
  printf '  winget : %snot found%s\n' "$C_RED" "$C_RESET"
else
  WINGET_VER=$("$WINGET" --version 2>/dev/null | tr -d '\r' | head -n 1)
  if [ -n "$WINGET_VER" ]; then
    printf '  winget : %s\n' "$WINGET_VER"
  else
    printf '  winget : %sfound but not working (%s)%s\n' "$C_RED" "$WINGET" "$C_RESET"
  fi
fi

if [ -z "$CHOCO" ]; then
  printf '  choco  : %snot installed%s (Chocolatey will be skipped)\n' "$C_DIM" "$C_RESET"
else
  CHOCO_VER=$("$CHOCO" --version 2>/dev/null | tr -d '\r' | head -n 1)
  printf '  choco  : %s\n' "${CHOCO_VER:-unknown version}"
fi

ADMIN=0
if command -v net >/dev/null 2>&1 && net session >/dev/null 2>&1; then
  ADMIN=1
fi
if [ "$ADMIN" -eq 1 ]; then
  printf '  shell  : Administrator\n\n'
else
  printf '  shell  : normal user (Chocolatey needs Administrator)\n\n'
fi

if [ -z "$WINGET" ] && [ -z "$CHOCO" ]; then
  printf '%sNo package manager found.%s Install winget (App Installer) or Chocolatey.\n' "$C_RED" "$C_RESET" >&2
  exit 1
fi

# --------------------------------------------------------------------- log --
LOG_DIR="${HOME:-/tmp}/update-logs"
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
  printf 'Cannot create log directory: %s\n' "$LOG_DIR" >&2
  exit 1
fi
LOG_FILE="$LOG_DIR/update-$(date '+%Y%m%d-%H%M%S').log"

# ------------------------------------------------------------ update lists --
COUNT=0
declare -a PKG_TOOL=()
declare -a PKG_NAME=()
declare -a PKG_ID=()
declare -a PKG_SRC=()
declare -a PKG_INST=()
declare -a PKG_AVAIL=()

WINGET_WARNING=""
CHOCO_WARNING=""

add_pkg() {
  # tool name id source installed available
  COUNT=$((COUNT + 1))
  PKG_TOOL[$COUNT]=$1
  PKG_NAME[$COUNT]=$2
  PKG_ID[$COUNT]=$3
  PKG_SRC[$COUNT]=$4
  PKG_INST[$COUNT]=$5
  PKG_AVAIL[$COUNT]=$6
}

collect_winget() {
  local raw errfile err rc n
  local name id ver avail src

  errfile=$(mktemp "${TMPDIR:-/tmp}/winget-err.XXXXXX") || return 1
  raw=$("$WINGET" upgrade --include-unknown --accept-source-agreements --disable-interactivity </dev/null 2>"$errfile")
  rc=$?
  err=$(tr -d '\r' <"$errfile" | sed '/^[[:space:]]*$/d')
  rm -f "$errfile"

  n=0
  while IFS=$'\x1f' read -r name id ver avail src; do
    [ -n "$id" ] || continue
    add_pkg "winget" "$name" "$id" "$src" "$ver" "$avail"
    n=$((n + 1))
  done < <(printf '%s\n' "$raw" | awk '
    BEGIN { FS = "[ \t]+"; started = 0 }
    {
      sub(/\r$/, "")
      if (!started) {
        if ($0 ~ /^-+[ \t]*$/) started = 1
        next
      }
      if ($0 ~ /^[ \t]*$/) exit
      sub(/^[ \t]+/, "")
      sub(/[ \t]+$/, "")
      if (NF < 5) next
      # footer lines end with a period; data rows end with a source name
      if ($0 ~ /[.][ \t]*$/) next
      src = $NF
      avail = $(NF - 1)
      # every available version contains a digit; footer words do not
      if (avail !~ /[0-9]/) next
      if ($(NF - 3) == "<" || $(NF - 3) == ">") {
        ver = $(NF - 3) " " $(NF - 2)
        id = $(NF - 4)
        idpos = NF - 4
      } else {
        ver = $(NF - 2)
        id = $(NF - 3)
        idpos = NF - 3
      }
      if (id == "" || idpos < 2) next
      name = ""
      for (i = 1; i < idpos; i++) name = name (i > 1 ? " " : "") $i
      printf "%s\037%s\037%s\037%s\037%s\n", name, id, ver, avail, src
    }
  ')

  if [ "$n" -eq 0 ] && [ "$rc" -ne 0 ]; then
    WINGET_WARNING="winget exited with code $rc."
    [ -n "$err" ] && WINGET_WARNING="$WINGET_WARNING $err"
  fi
}

collect_choco() {
  local raw errfile err rc n
  local name cur avail pinned

  errfile=$(mktemp "${TMPDIR:-/tmp}/choco-err.XXXXXX") || return 1
  raw=$("$CHOCO" outdated -r </dev/null 2>"$errfile")
  rc=$?
  err=$(tr -d '\r' <"$errfile" | sed '/^[[:space:]]*$/d')
  rm -f "$errfile"

  n=0
  while IFS='|' read -r name cur avail pinned; do
    name=${name%$'\r'}
    [ -n "$name" ] || continue
    # package ids never contain whitespace; this filters banners/warnings
    [[ $name == *[[:space:]]* ]] && continue
    [ "$name" = "Package" ] && continue
    [ -n "$avail" ] || continue
    add_pkg "choco" "$name" "$name" "choco" "$cur" "$avail"
    n=$((n + 1))
  done < <(printf '%s\n' "$raw" | tr -d '\r')

  if [ "$n" -eq 0 ] && [ "$rc" -ne 0 ]; then
    CHOCO_WARNING="choco exited with code $rc."
    [ -n "$err" ] && CHOCO_WARNING="$CHOCO_WARNING $err"
  fi
}

# Merge the two manager-specific lists into one alphabetical view. The order
# used to apply updates is still winget first, then Chocolatey (see ORDER).
sort_packages() {
  local i idx n
  local -a order=()
  local -a t_tool=() t_name=() t_id=() t_src=() t_inst=() t_avail=()

  while IFS=$'\t' read -r _ idx; do
    [ -n "$idx" ] && order+=("$idx")
  done < <(
    for ((i = 1; i <= COUNT; i++)); do
      printf '%s\t%d\n' "${PKG_NAME[$i]}" "$i"
    done | LC_ALL=C sort -f -t $'\t' -k1,1 -k2,2n
  )

  n=0
  for idx in "${order[@]}"; do
    t_tool[n]=${PKG_TOOL[$idx]}
    t_name[n]=${PKG_NAME[$idx]}
    t_id[n]=${PKG_ID[$idx]}
    t_src[n]=${PKG_SRC[$idx]}
    t_inst[n]=${PKG_INST[$idx]}
    t_avail[n]=${PKG_AVAIL[$idx]}
    n=$((n + 1))
  done

  # If sorting produced an unexpected result, keep the original order.
  if [ "$n" -ne "$COUNT" ]; then
    return 0
  fi

  # Rebuild the global arrays as 1-based, matching add_pkg().
  PKG_TOOL=()
  PKG_NAME=()
  PKG_ID=()
  PKG_SRC=()
  PKG_INST=()
  PKG_AVAIL=()
  for ((i = 0; i < n; i++)); do
    PKG_TOOL[$((i + 1))]=${t_tool[$i]}
    PKG_NAME[$((i + 1))]=${t_name[$i]}
    PKG_ID[$((i + 1))]=${t_id[$i]}
    PKG_SRC[$((i + 1))]=${t_src[$i]}
    PKG_INST[$((i + 1))]=${t_inst[$i]}
    PKG_AVAIL[$((i + 1))]=${t_avail[$i]}
  done
}

# ------------------------------------------------------------------- table --
truncate_str() {
  local s=$1 max=$2
  if (( ${#s} > max )); then
    printf '%s...' "${s:0:$((max - 3))}"
  else
    printf '%s' "$s"
  fi
}

show_table() {
  local i cols width wg nch name
  cols=$(tput cols 2>/dev/null || true)
  case "$cols" in
    ''|*[!0-9]*) cols=110 ;;
  esac
  width=$((cols - 50))
  (( width < 24 )) && width=24
  (( width > 55 )) && width=55

  wg=0
  nch=0
  for ((i = 1; i <= COUNT; i++)); do
    if [ "${PKG_TOOL[$i]}" = "winget" ]; then
      wg=$((wg + 1))
    else
      nch=$((nch + 1))
    fi
  done

  printf '\n%sAvailable updates: %d%s %s(winget %d, choco %d)%s\n' \
    "$C_BOLD" "$COUNT" "$C_RESET" "$C_DIM" "$wg" "$nch" "$C_RESET"
  printf '%s%3s  %-7s  %-*s  %-15s  %-15s%s\n' \
    "$C_BOLD" "#" "SOURCE" "$width" "PACKAGE" "INSTALLED" "AVAILABLE" "$C_RESET"
  printf '%s\n' "---  -------  $(printf '%*s' "$width" '' | tr ' ' '-')  ---------------  ---------------"
  for ((i = 1; i <= COUNT; i++)); do
    name=$(truncate_str "${PKG_NAME[$i]}" "$width")
    printf '%3d  %-7s  %-*s  %-15s  %-15s\n' \
      "$i" "${PKG_TOOL[$i]}" "$width" "$name" \
      "$(truncate_str "${PKG_INST[$i]}" 15)" \
      "$(truncate_str "${PKG_AVAIL[$i]}" 15)"
  done
  printf '%sMerged from winget and Chocolatey; SOURCE shows which updater is used.%s\n' \
    "$C_DIM" "$C_RESET"
}

# --------------------------------------------------------------- selection --
parse_selection() {
  # parse_selection "1 3-5,8" COUNT -> prints one index per line
  local input=$1 max=$2
  input=${input//,/ }
  local -a items=()
  local tok a b i
  local -A seen=()

  for tok in $input; do
    if [[ $tok =~ ^([0-9]+)-([0-9]+)$ ]]; then
      a=${BASH_REMATCH[1]}
      b=${BASH_REMATCH[2]}
      if (( a > b )); then
        local t=$a
        a=$b
        b=$t
      fi
    elif [[ $tok =~ ^[0-9]+$ ]]; then
      a=$tok
      b=$tok
    else
      printf 'Not a number or range: %s\n' "$tok" >&2
      return 1
    fi

    if (( a < 1 || b > max )); then
      printf 'Out of range: %s (choose 1-%d)\n' "$tok" "$max" >&2
      return 1
    fi

    for ((i = a; i <= b; i++)); do
      items+=("$i")
    done
  done

  for i in "${items[@]}"; do
    if [ -n "${seen[$i]:-}" ]; then
      continue
    fi
    seen[$i]=1
    printf '%s\n' "$i"
  done
}

declare -a PICK=()

reset_pick() {
  local i
  PICK=()
  for ((i = 1; i <= COUNT; i++)); do
    PICK[$i]=0
  done
}

prompt_exclude() {
  local input sel i
  printf 'Enter numbers to EXCLUDE (example: 2 5 7-9).\n'
  printf 'Press Enter to go back.\n'
  while :; do
    if ! read -r -p "exclude> " input; then
      printf '\n'
      return 1
    fi
    [ -z "$input" ] && return 1
    if ! sel=$(parse_selection "$input" "$COUNT"); then
      continue
    fi
    if [ -z "$sel" ]; then
      printf 'No numbers found. Try again.\n'
      continue
    fi
    reset_pick
    for ((i = 1; i <= COUNT; i++)); do
      PICK[$i]=1
    done
    for i in $sel; do
      PICK[$i]=0
    done
    return 0
  done
}

prompt_select() {
  local input sel i
  printf 'Enter numbers to UPDATE (example: 1 3 5-7).\n'
  printf 'Press Enter to go back.\n'
  while :; do
    if ! read -r -p "update> " input; then
      printf '\n'
      return 1
    fi
    [ -z "$input" ] && return 1
    if ! sel=$(parse_selection "$input" "$COUNT"); then
      continue
    fi
    if [ -z "$sel" ]; then
      printf 'No numbers found. Try again.\n'
      continue
    fi
    reset_pick
    for i in $sel; do
      PICK[$i]=1
    done
    return 0
  done
}

# ------------------------------------------------------------------- check --
if [ -n "$WINGET" ]; then
  printf 'Checking winget for updates... '
  before=$COUNT
  collect_winget
  printf 'done (%d)\n' "$((COUNT - before))"
  if [ -n "$WINGET_WARNING" ]; then
    printf '  %swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "${WINGET_WARNING%%$'\n'*}"
  fi
else
  printf 'Skipping winget (not found).\n'
fi

if [ -n "$CHOCO" ]; then
  printf 'Checking Chocolatey for updates... '
  before=$COUNT
  collect_choco
  printf 'done (%d)\n' "$((COUNT - before))"
  if [ -n "$CHOCO_WARNING" ]; then
    printf '  %swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "${CHOCO_WARNING%%$'\n'*}"
  fi
else
  printf 'Skipping Chocolatey (not installed).\n'
fi

if [ "$COUNT" -eq 0 ]; then
  if [ -n "$WINGET_WARNING" ] || [ -n "$CHOCO_WARNING" ]; then
    printf '\n%sNo updates found, but a check reported an error:%s\n' "$C_YELLOW" "$C_RESET"
    [ -n "$WINGET_WARNING" ] && printf '  winget: %s\n' "${WINGET_WARNING%%$'\n'*}"
    [ -n "$CHOCO_WARNING" ] && printf '  choco : %s\n' "${CHOCO_WARNING%%$'\n'*}"
    exit 1
  fi
  printf '\n%sNo updates available - everything is up to date.%s\n' "$C_GREEN" "$C_RESET"
  exit 0
fi

sort_packages
show_table

choco_n=0
for ((i = 1; i <= COUNT; i++)); do
  [ "${PKG_TOOL[$i]}" = "choco" ] && choco_n=$((choco_n + 1))
done
if [ "$ADMIN" -eq 0 ] && [ "$choco_n" -gt 0 ]; then
  printf '\n%sNote:%s %d Chocolatey update(s) need an Administrator terminal.\n' \
    "$C_YELLOW" "$C_RESET" "$choco_n"
  printf '      Run Git Bash as Administrator to install them (or exclude them).\n'
fi

if [ "$DRY_RUN" -eq 1 ]; then
  printf '\n%sDry run - no packages were changed.%s\n' "$C_DIM" "$C_RESET"
  exit 0
fi

# -------------------------------------------------------------------- menu --
if [ "$ASSUME_YES" -eq 1 ]; then
  reset_pick
  for ((i = 1; i <= COUNT; i++)); do
    PICK[$i]=1
  done
fi

while [ "$ASSUME_YES" -eq 0 ]; do
  printf '\n%sWhat do you want to do?%s\n' "$C_BOLD" "$C_RESET"
  printf '  %sA%s  Update all %d package(s)\n' "$C_GREEN" "$C_RESET" "$COUNT"
  printf '  %sE%s  Exclude some packages, update the rest\n' "$C_YELLOW" "$C_RESET"
  printf '  %sS%s  Select only specific packages\n' "$C_CYAN" "$C_RESET"
  printf '  %sQ%s  Quit without updating\n' "$C_DIM" "$C_RESET"
  if ! read -r -p "Choice [a/e/s/q]: " choice; then
    printf '\n'
    exit 130
  fi
  choice=${choice// /}
  case "${choice,,}" in
    a|all)
      reset_pick
      for ((i = 1; i <= COUNT; i++)); do
        PICK[$i]=1
      done
      break
      ;;
    e|exclude)
      if prompt_exclude; then break; else continue; fi
      ;;
    s|select|only)
      if prompt_select; then break; else continue; fi
      ;;
    q|quit)
      printf 'Nothing was updated.\n'
      exit 0
      ;;
    "")
      ;;
    *)
      printf 'Please type a, e, s or q.\n'
      ;;
  esac
done

SELECTED=0
for ((i = 1; i <= COUNT; i++)); do
  if [ "${PICK[$i]}" -eq 1 ]; then
    SELECTED=$((SELECTED + 1))
  fi
done

if [ "$SELECTED" -eq 0 ]; then
  printf 'No packages selected - nothing to do.\n'
  exit 0
fi

if [ "$ASSUME_YES" -eq 0 ]; then
  printf '\nAbout to update %d package(s). Proceed? [Y/n] ' "$SELECTED"
  if ! read -r answer; then
    printf '\n'
    exit 130
  fi
  case "${answer,,}" in
    n|no)
      printf 'Cancelled.\n'
      exit 0
      ;;
  esac
fi

# winget first, then Chocolatey with chocolatey itself before other packages
ORDER=()
for ((i = 1; i <= COUNT; i++)); do
  if [ "${PICK[$i]}" -eq 1 ] && [ "${PKG_TOOL[$i]}" = "winget" ]; then
    ORDER+=("$i")
  fi
done
for ((i = 1; i <= COUNT; i++)); do
  if [ "${PICK[$i]}" -eq 1 ] && [ "${PKG_TOOL[$i]}" = "choco" ] && [ "${PKG_ID[$i]}" = "chocolatey" ]; then
    ORDER+=("$i")
  fi
done
for ((i = 1; i <= COUNT; i++)); do
  if [ "${PICK[$i]}" -eq 1 ] && [ "${PKG_TOOL[$i]}" = "choco" ] && [ "${PKG_ID[$i]}" != "chocolatey" ]; then
    ORDER+=("$i")
  fi
done

{
  printf '=== Windows App Updater %s ===\n' "$SCRIPT_VERSION"
  printf 'Started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'Script: %s\n' "$SCRIPT_PATH"
  printf 'Administrator: %s\n' "$ADMIN"
  printf 'winget: %s | choco: %s\n' "${WINGET:-none}" "${CHOCO:-none}"
  printf 'Selected: %d\n' "$SELECTED"
  for i in "${ORDER[@]}"; do
    printf '  [%s] %s (%s -> %s)\n' "${PKG_TOOL[$i]}" "${PKG_NAME[$i]}" "${PKG_INST[$i]}" "${PKG_AVAIL[$i]}"
  done
  printf '\n'
} >> "$LOG_FILE"

# ------------------------------------------------------------------- apply --
run_updates() {
  local total=${#ORDER[@]}
  local pos=0 idx tool name id src inst avail rc status tmp
  local ok=0 skipped=0 failed=0 i
  local -a RES_TOOL=()
  local -a RES_NAME=()
  local -a RES_STATUS=()
  local -a cmd

  for idx in "${ORDER[@]}"; do
    pos=$((pos + 1))
    tool=${PKG_TOOL[$idx]}
    name=${PKG_NAME[$idx]}
    id=${PKG_ID[$idx]}
    src=${PKG_SRC[$idx]}
    inst=${PKG_INST[$idx]}
    avail=${PKG_AVAIL[$idx]}

    printf '\n%s[%d/%d]%s %s: %s\n' "$C_BOLD" "$pos" "$total" "$C_RESET" "$tool" "$name"
    printf '        %s -> %s\n' "$inst" "$avail"
    printf '[%s] %s: %s (%s -> %s)\n' "$(date '+%H:%M:%S')" "$tool" "$name" "$inst" "$avail" >> "$LOG_FILE"

    cmd=()
    if [ "$tool" = "winget" ]; then
      cmd=("$WINGET" upgrade --id "$id" --exact --include-unknown \
        --accept-package-agreements --accept-source-agreements)
      if [ -n "$src" ]; then
        cmd+=(--source "$src")
      fi
      if [ "$WINGET_SILENT" -eq 1 ]; then
        cmd+=(--silent)
      fi
    else
      cmd=("$CHOCO" upgrade "$id" -y --no-progress)
    fi

    tmp=$(mktemp "${TMPDIR:-/tmp}/upd-out.XXXXXX")
    "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE" "$tmp"
    rc=${PIPESTATUS[0]}

    if [ "$tool" = "winget" ] && [ "$rc" -eq 43 ]; then
      # winget's "no applicable upgrade" code, masked to 8 bits by bash
      status="UP-TO-DATE"
    elif [ "$tool" = "winget" ] && grep -Eqi 'no available upgrade found|no newer package versions' "$tmp"; then
      status="UP-TO-DATE"
    elif [ "$rc" -eq 0 ]; then
      status="OK"
    else
      status="FAILED"
    fi
    rm -f "$tmp"

    case "$status" in
      OK)
        ok=$((ok + 1))
        printf '%s  [ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$name"
        ;;
      UP-TO-DATE)
        skipped=$((skipped + 1))
        printf '%s  [SKIP]%s %s (already up to date)\n' "$C_YELLOW" "$C_RESET" "$name"
        ;;
      *)
        failed=$((failed + 1))
        printf '%s  [FAIL]%s %s (exit code %d)\n' "$C_RED" "$C_RESET" "$name" "$rc"
        ;;
    esac
    printf '[%s] result: %s (rc=%d)\n\n' "$(date '+%H:%M:%S')" "$status" "$rc" >> "$LOG_FILE"

    RES_TOOL+=("$tool")
    RES_NAME+=("$name")
    RES_STATUS+=("$status")
  done

  printf '\n%s================ Summary ================%s\n' "$C_BOLD" "$C_RESET"
  for ((i = 0; i < ${#RES_NAME[@]}; i++)); do
    case "${RES_STATUS[$i]}" in
      OK)
        printf '  %s[ OK ]%s %-6s %s\n' "$C_GREEN" "$C_RESET" "${RES_TOOL[$i]}" "${RES_NAME[$i]}"
        ;;
      UP-TO-DATE)
        printf '  %s[SKIP]%s %-6s %s\n' "$C_YELLOW" "$C_RESET" "${RES_TOOL[$i]}" "${RES_NAME[$i]}"
        ;;
      *)
        printf '  %s[FAIL]%s %-6s %s\n' "$C_RED" "$C_RESET" "${RES_TOOL[$i]}" "${RES_NAME[$i]}"
        ;;
    esac
  done
  printf '\n  %d updated, %d already up to date, %d failed.\n' "$ok" "$skipped" "$failed"

  if command -v cygpath >/dev/null 2>&1; then
    printf '  Log: %s\n' "$(cygpath -w "$LOG_FILE")"
  else
    printf '  Log: %s\n' "$LOG_FILE"
  fi

  [ "$failed" -eq 0 ]
}

if run_updates; then
  exit 0
else
  exit 1
fi



