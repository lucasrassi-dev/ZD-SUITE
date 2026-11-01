#!/usr/bin/env bash

echo -e "\n========================================================"
echo -e "     LR's NexusRepositories"
echo -e "========================================================\n"
apt_pkg=()
deb_pkg=()
npm_pkg=()
pake_pkg=()
src_code=()
app_img=()
user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

repo="/home/${user}/Documents/nexus-linux"
store="$repo/debian-repo"
bkp=(
"$repo/"
"$repo/applications"
"$store/src"
"$store/deb"
"$store/app-image"
"$store/git"
"$store/pake"
)

for path in "${bkp[@]}"; do
    mkdir -p "$path"
done

desk="/home/${user}/Desktop"
mkdir -p "$desk/~Desktop"
shopt -s nullglob
for f in "$desk"/*; do
    [[ -f "$f" ]] || continue
    cp -r "$f" "$desk/~Desktop/"
    sudo chmod +x "$desk/~Desktop/$(basename "$f")"
done
shopt -u nullglob

# ---------------- FUNCTIONS ----------------

# Strip query string / fragment and return the last path component
url_filename() {
    local clean="${1%%[\?#]*}"
    echo "${clean##*/}"
}

apt_prepare() {
    local sources="$SCRIPT_DIR/~resources/sources-list.sh"
    if [[ -f "$sources" ]]; then
        bash "$sources"
    else
        echo "[APT] sources-list.sh not found at $sources, skipping"
    fi

    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none
    sudo dpkg --configure -a
    sudo apt-get update -y
    sudo -E apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade
}

# A package file may run twice in one dispatch; install each entry once
already_done() {
    local name="$1"; shift
    [[ " $* " == *" $name "* ]]
}

install_apt() {
    local pkg="$1"
    if already_done "$pkg" "${apt_pkg[@]}"; then
        echo -e "\n>>> [APT] $pkg already installed in this run, skipping"
        return 0
    fi
    echo -e "\n>>> [APT] Installing package: $pkg"
    if sudo -E apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install "$pkg"; then
        apt_pkg+=("$pkg")
    else
        echo "!!! Failed to install: $pkg"
    fi
}

install_npm() {
    local pkg="$1"
    if already_done "$pkg" "${npm_pkg[@]}"; then
        echo -e "\n>>> [NPM] $pkg already installed in this run, skipping"
        return 0
    fi
    echo -e "\n>>> [NPM] Installing package: $pkg"
    if sudo npm install -g "$pkg"; then
        npm_pkg+=("$pkg")
    else
        echo "!!! Failed to install: $pkg"
    fi
}

# A package file holds every installer: an --apt, --npm or --pake line
# switches the installer used for the entries that follow it
run_packages() {
    local pkgfile="$1"
    [[ -f "$pkgfile" ]] || { echo "!!! Package file not found: $pkgfile"; return 1; }

    sed -i 's/\r$//' "$pkgfile"

    echo -e "\n[PACKAGES] Installing packages from $pkgfile..."

    # Read the file up front so installers can't consume it from stdin
    local lines line item mode="" apt_ready=0
    mapfile -t lines < "$pkgfile"

    for line in "${lines[@]}"; do
        line="${line%%#*}"
        read -ra items <<< "$line"

        for item in "${items[@]}"; do
            case "$item" in
                --apt)
                    mode="apt"
                    # once per file, so repos added by earlier --deb lines are picked up
                    (( apt_ready )) || { apt_prepare; apt_ready=1; }
                    ;;
                --npm)  mode="npm" ;;
                --pake) mode="pake" ;;
                *)
                    case "$mode" in
                        apt)  install_apt "$item" ;;
                        npm)  install_npm "$item" ;;
                        pake) install_pake "$item" ;;
                        *)    echo "!!! No --apt, --npm or --pake line before: $item" ;;
                    esac
                    ;;
            esac
        done
    done
}


run_deb() {
    local url="$1"
    local tmp="/tmp/$(url_filename "$url")"

    echo -e "\n[DEB] Downloading $url..."
    wget -q -L --show-progress "$url" -O "$tmp" || { echo "!!! Download failed: $url"; return 1; }

    # Install only when missing or when the download is newer than what's installed
    local pkg ver cur
    pkg="$(dpkg-deb -f "$tmp" Package 2>/dev/null)"
    ver="$(dpkg-deb -f "$tmp" Version 2>/dev/null)"
    [[ -n "$pkg" ]] || { echo "!!! Not a valid .deb: $url"; return 1; }
    cp "$tmp" "$store/deb/"
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed'; then
        cur="$(dpkg-query -W -f='${Version}' "$pkg")"
        if ! dpkg --compare-versions "$ver" gt "$cur"; then
            echo "[DEB] $pkg $cur Installed, download is $ver , current version is (UPDATED), skipping"
            deb_pkg+=("$(basename "$tmp")")
            return 0
        fi
        echo "[DEB] Updating $pkg $cur -> $ver"
    fi

    sudo apt-get install -y "$tmp"
    sudo apt-get install -f -y
    deb_pkg+=("$(basename "$tmp")")
}

run_appimage(){
    local url="$1"
    local dest="/usr/local/bin/$(url_filename "$url")"

    echo -e "\n[AppImage] Downloading $url..."
    sudo wget -q -L --show-progress "$url" -O "$dest" || { echo "!!! Download failed: $url"; return 1; }
    sudo chmod +x "$dest"
    cp "$dest" "$store/app-image/"
    sudo ln -sf "$dest" /usr/share/applications/
    app_img+=("$dest")
}

run_tar() {
    local url="$1"
    local dest="/usr/local/src"
    local filename
    filename="$(url_filename "$url")"
    local target_path="$dest/$filename"

    echo -e "\n[TAR] Downloading $url..."
    sudo mkdir -p "$dest"
    sudo wget -q -L --show-progress "$url" -O "$target_path" || { echo "!!! Download failed: $url"; return 1; }

    echo -e "[TAR] Extracting $filename..."
    sudo tar -xf "$target_path" -C "$dest"
    cp "$target_path" "$store/src/"

    # Link any launcher shipped inside the archive
    local member
    while IFS= read -r member; do
        [[ "$member" == *.desktop ]] || continue
        sudo ln -sf "$dest/$member" /usr/share/applications/
        echo "[TAR] Linked launcher: $(basename "$member")"
    done < <(sudo tar -tf "$target_path")

    src_code+=("$target_path")
}

run_clone() {
    local url="$1"
    local dest="/usr/local/src"
    local target_path="$dest/$(basename "$url" .git)"

    sudo mkdir -p "$dest"
    if [[ -d "$target_path/.git" ]]; then
        echo -e "\n[CLONE] $target_path exists, pulling..."
        sudo git -C "$target_path" pull --ff-only
    else
        echo -e "\n[CLONE] Cloning $url..."
        sudo git clone "$url" "$target_path" || { echo "!!! Clone failed: $url"; return 1; }
    fi
    rm -rf "$store/git/$(basename "$target_path")"
    cp -r "$target_path" "$store/git/"
    src_code+=("$target_path")
}

# Derive a Pake app name from a URL: https://web.whatsapp.com/ -> whatsapp
url_appname() {
    local host="${1#*://}"
    host="${host%%[/:?#]*}"
    host="${host#www.}"
    local parts
    IFS=. read -ra parts <<< "$host"
    local n=${#parts[@]}
    local name="${parts[0]}"
    (( n >= 2 )) && name="${parts[n-2]}"
    echo "${name,,}"
}

# 0 = not set up yet, 1 = ready, 2 = setup failed
pake_ready=0

pake_prepare() {
    (( pake_ready == 1 )) && return 0
    (( pake_ready == 2 )) && return 1

    # rustup installs per user; make it visible under sudo or a non-login shell
    local user_home="/home/${user}"
    if [[ -x "$user_home/.cargo/bin/cargo" ]]; then
        export CARGO_HOME="${CARGO_HOME:-$user_home/.cargo}"
        export RUSTUP_HOME="${RUSTUP_HOME:-$user_home/.rustup}"
        export PATH="$CARGO_HOME/bin:$PATH"
    fi

    # Install only when missing: a pake-cli upgrade changes every app's
    # fingerprint and rebuilds them all, so upgrade it by hand
    if ! command -v pake >/dev/null; then
        sudo npm install -g pake-cli
    fi

    # sudo npm leaves pake-cli root-owned (also after a manual install or
    # upgrade), but pake builds inside its own src-tauri
    local pake_dir
    pake_dir="$(npm root -g)/pake-cli"
    if [[ -d "$pake_dir" && "$(stat -c %U "$pake_dir")" != "$user" ]]; then
        sudo chown -R "$user:$user" "$pake_dir"
    fi

    command -v pake >/dev/null || { echo "pake is not installed (npm install -g pake-cli)"; pake_ready=2; return 1; }
    command -v cargo >/dev/null || { echo "pake needs Rust (https://rustup.rs)"; pake_ready=2; return 1; }
    pake_ready=1
}

install_pake() {
    local app="$1"
    pake_prepare || { echo "!!! Skipping Pake app: $app"; return 1; }

    # Entries are either <url> or <name>=<url>
    local url="$app" name
    if [[ "$app" == *=* && "${app%%=*}" != *://* ]]; then
        name="${app%%=*}"
        url="${app#*=}"
    else
        name="$(url_appname "$url")"
    fi
    name="${name,,}"

    if already_done "$name" "${pake_pkg[@]}"; then
        echo -e "\n>>> [PAKE] $name already built in this run, skipping"
        return 0
    fi

    # Pake debs are always 1.0.0 and never byte-identical, so compare the build
    # inputs instead: skip when they match the last install and it's still there
    local flags=(--name "$name" --targets deb)
    local stamp="$store/pake/.stamps/$name" fp old_fp pkg
    fp="$(printf '%s\n' "$(pake --version 2>/dev/null)" "$url" "${flags[@]}" | sha256sum | cut -d' ' -f1)"
    if [[ -f "$stamp" ]]; then
        read -r old_fp pkg < "$stamp"
        if [[ "$old_fp" == "$fp" ]] && dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed'; then
            echo -e "\n>>> [PAKE] $name unchanged since last install, skipping"
            pake_pkg+=("$name")
            return 0
        fi
    fi

    echo -e "\n>>> [PAKE] Building Desktop App : $name ($url)"
    local build deb
    build="$(mktemp -d)"
    if ! ( cd "$build" && pake "$url" "${flags[@]}" ); then
        echo "!!! Pake build failed: $url"
        rm -rf "$build"
        return 1
    fi

    deb="$(find "$build" -maxdepth 3 -name '*.deb' -print -quit)"
    if [[ -z "$deb" ]]; then
        echo "!!! No .deb produced for: $url"
        rm -rf "$build"
        return 1
    fi

    cp "$deb" "$store/pake/"
    # _apt can't read inside a 700 home dir; install from a world-readable copy in /tmp
    local tmp_deb="/tmp/$(basename "$deb")"
    install -m 644 "$deb" "$tmp_deb"
    if sudo apt-get install -y "$tmp_deb"; then
        pake_pkg+=("$name")
        mkdir -p "${stamp%/*}"
        echo "$fp $(dpkg-deb -f "$tmp_deb" Package)" > "$stamp"
    fi
    rm -f "$tmp_deb"
    rm -rf "$build"
}

run_pake(){
    local pake_file="$1"
    [[ -f "$pake_file" ]] || { echo "!!! Pake app file not found: $pake_file"; return 1; }

    sed -i 's/\r$//' "$pake_file"

    echo -e "\n[pake] Building Desktop Apps from $pake_file..."

    local lines line app
    mapfile -t lines < "$pake_file"
    for line in "${lines[@]}"; do
        line="${line%%#*}"
        read -ra apps <<< "$line"
        for app in "${apps[@]}"; do
            install_pake "$app"
        done
    done
}

print_summary() {
    echo -e "\n\n>>> APT Packages :"
    echo -e "==========================================="
    printf '%s\n' "${apt_pkg[@]}"

    echo -e "\n\n>>> DEB Packages :"
    echo -e "==========================================="
    printf '%s\n' "${deb_pkg[@]}"

    echo -e "\n\n>>> NPM Packages :"
    echo -e "==========================================="
    printf '%s\n' "${npm_pkg[@]}"

    echo -e "\n\n>>> AppImages :"
    echo -e "==========================================="
    printf '%s\n' "${app_img[@]}"

    echo -e "\n\n>>> Source-Code :"
    echo -e "==========================================="
    printf '%s\n' "${src_code[@]}"

    echo -e "\n\n>>> Pake Apps :"
    echo -e "==========================================="
    printf '%s\n' "${pake_pkg[@]}"
    echo -e "\n\n"
}

# ---------------- FILE DISPATCH ----------------

dispatch_file() {
    local file="$1"

    [[ -f "$file" ]] || { echo "Dispatch file not found: $file"; exit 1; }

    # package and pake paths are relative to the script's folder, not the cwd
    sed -i 's/\r$//' "$file"
    mapfile -t LINES < <(grep -vE '^\s*($|#)' "$file")

    for line in "${LINES[@]}"; do
        read -r -a args <<< "$line"
        [[ ${#args[@]} -eq 0 ]] && continue

        echo -e "\n>>> Executing line from file: $line"

        local opt="${args[0]}"
        local val="${args[1]}"
        case "$opt" in
            -a|--packages|-p|--pake) [[ "$val" == /* ]] || val="$SCRIPT_DIR/$val" ;;
        esac

        case "$opt" in
            -a|--packages)   run_packages "$val" ;;
            -d|--deb)        run_deb "$val" ;;
            -app|--appimage) run_appimage "$val" ;;
            -t|--tar)        run_tar "$val" ;;
            -c|--clone)      run_clone "$val" ;;
            -p|--pake)       run_pake "$val" ;;
            *)               echo "Unknown option in file: $opt" ;;
        esac
    done
}

# ---------------- USAGE ----------------

usage() {
    echo -e "\nUsage: $0 [OPTIONS]\n"
    echo "Modes (choose one):"
    echo "  -a,   --packages <packagefile>   (sections: --apt, --npm, --pake)"
    echo "  -d,   --deb <url>"
    echo "  -app, --appimage <url>"
    echo "  -t,   --tar <url>"
    echo "  -c,   --clone <git-url>"
    echo "  -p,   --pake <appfile>"
    echo "  -f,   --file <dispatch-file>"
    exit 1
}

[[ $# -eq 0 ]] && usage

# ---------------- PARSE CLI ----------------

# getopt short options are single letters, so map -app to --appimage first
args=()
for a in "$@"; do
    [[ "$a" == "-app" ]] && a="--appimage"
    args+=("$a")
done

PARSED=$(getopt \
    --options a:d:t:c:p:f: \
    --longoptions packages:,deb:,appimage:,tar:,clone:,pake:,file: \
    --name "$0" -- "${args[@]}") || exit 1

eval set -- "$PARSED"

PACKAGES=""
DEB=""
TAR=""
CLONE=""
FILE=""
APPIMAGE=""
PAKE=""

while true; do
    case "$1" in
        -a|--packages)   PACKAGES="$2"; shift 2 ;;
        -d|--deb)        DEB="$2"; shift 2 ;;
        --appimage)      APPIMAGE="$2"; shift 2 ;;
        -t|--tar)        TAR="$2"; shift 2 ;;
        -c|--clone)      CLONE="$2"; shift 2 ;;
        -p|--pake)       PAKE="$2"; shift 2 ;;
        -f|--file)       FILE="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "Invalid option: $1"; exit 1 ;;
    esac
done

# ---------------- MODE VALIDATION ----------------

MODE_COUNT=0
for m in "$PACKAGES" "$DEB" "$APPIMAGE" "$TAR" "$CLONE" "$PAKE" "$FILE"; do
    [[ -n "$m" ]] && MODE_COUNT=$((MODE_COUNT + 1))
done

if [[ $MODE_COUNT -ne 1 ]]; then
    echo "Specify exactly one of: --packages, --deb, --appimage, --tar, --clone, --pake, --file"
    exit 1
fi

echo -e "\n============================================"

# ---------------- EXECUTION ----------------
[[ -n "$FILE"       ]] && dispatch_file "$FILE"
[[ -n "$PACKAGES"   ]] && run_packages "$PACKAGES"
[[ -n "$DEB"        ]] && run_deb "$DEB"
[[ -n "$APPIMAGE"   ]] && run_appimage "$APPIMAGE"
[[ -n "$TAR"        ]] && run_tar "$TAR"
[[ -n "$CLONE"      ]] && run_clone "$CLONE"
[[ -n "$PAKE"       ]] && run_pake "$PAKE"

echo -e "\n============================================\n"

# ---------------- APPLICATIONS BACKUP ----------------

echo -e "\n[APPLICATIONS] Rebuilding $repo/applications from /usr/share/applications..."
sudo rm -rf "$repo/applications"
mkdir -p "$repo/applications"
sudo cp -rP /usr/share/applications/. "$repo/applications/"
sudo chown -hR "$user:$user" "$repo/applications"
# full read/write for the user, and executable + trusted so the launchers
# run straight from this folder without the untrusted-launcher prompt
sudo chmod -R u+rwX "$repo/applications"
for f in "$repo/applications"/*.desktop; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    chmod u+x "$f"
    gio set "$f" metadata::trusted true 2>/dev/null
done

print_summary
