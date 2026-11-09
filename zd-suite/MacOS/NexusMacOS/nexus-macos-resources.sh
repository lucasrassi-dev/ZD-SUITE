#!/usr/bin/env bash
# macOS port of OSS/Debian/NexusRepo/nexus-resources.sh
# Written for the stock /bin/bash 3.2: no mapfile, no ${var,,}, no GNU getopt

echo -e "\n========================================================"
echo -e "     LR's Nexus macOS Resources"
echo -e "========================================================\n"

if [[ $EUID -eq 0 ]]; then
    echo "Run as your own user, not with sudo: Homebrew refuses to run as root"
    exit 
fi
brew_pkg=()
cask_pkg=()
mas_pkg=()
npm_pkg=()
pake_pkg=()
dmg_pkg=()
pkg_pkg=()
src_code=()
manual_url=()
appstore_url=()
user="$USER"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

repo="$HOME/Documents/nexus-macos"
store="$repo/macos-repo"
bkp=(
"$repo/"
"$repo/applications"
"$store/src"
"$store/dmg"
"$store/zip"
"$store/pkg"
"$store/git"
"$store/pake"
)

for path in "${bkp[@]}"; do
    mkdir -p "$path"
done

# ---------------- FUNCTIONS ----------------

lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Read a file into the global LINES array, dropping CRLF endings
read_lines() {
    LINES=()
    local l
    while IFS= read -r l || [[ -n "$l" ]]; do
        LINES+=("${l%$'\r'}")
    done < "$1"
}

resource_site_domain() {
    local host prev last_two third last_three
    host="${1#*://}"
    host="${host%%/*}"
    host="${host%%\?*}"
    host="${host%%\#*}"
    host="${host%%:*}"
    host="${host#www.}"
    prev="${host%.*}"
    [[ "$prev" != "$host" ]] || { printf '%s' "$host"; return; }
    last_two="${prev##*.}.${host##*.}"
    case "$last_two" in
        co.uk|org.uk|ac.uk|com.au|net.au|org.au|com.br|net.br|com.mx|co.nz|co.jp|co.in|com.sg|com.hk|com.tr)
            third="${prev%.*}"
            last_three="${third##*.}.$last_two"
            printf '%s' "$last_three"
            ;;
        *) printf '%s' "$last_two" ;;
    esac
}

resource_clean_label() {
    local label="$1"
    label="${label#\#}"
    label="${label#"${label%%[![:space:]]*}"}"
    case "$label" in
        ""|=*|App\ Store\ URLs*|DMG\ or\ ZIP\ archive*) printf ''; return ;;
    esac
    label="${label%% <ISA>*}"
    label="${label%% ARM64*}"
    label="${label%% (*}"
    label="${label% }"
    printf '%s' "$label"
}

write_resource_record() {
    printf '# %s\n#============================\n%s\n# %s\n\n' "$2" "$1" "$3" >> "$4"
}

generate_resource_env() {
    local input="$1" output="$2" tmp line mode="" label comment url host filename
    local pending_url="" pending_label="" pending_site="" post_label=""
    mkdir -p "$(dirname "$output")" || return 1
    tmp="${output}.tmp.$$"
    : > "$tmp" || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -z "$line" ]]; then
            if [[ -n "$pending_url" ]]; then
                [[ -n "$post_label" ]] && label="$post_label"
                write_resource_record "$pending_url" "$pending_label" "$pending_site" "$tmp"
                pending_url=""; pending_label=""; pending_site=""; post_label=""
            fi
            continue
        fi

        if [[ "$line" == --* ]]; then
            if [[ -n "$pending_url" ]]; then
                write_resource_record "$pending_url" "$pending_label" "$pending_site" "$tmp"
                pending_url=""; pending_label=""; pending_site=""
            fi
            case "$line" in
                --brew|--cask|--mas|--dmg|--pkg|--zip|--app|--appstore) mode="${line#--}" ;;
                *) mode="" ;;
            esac
            label=""
            continue
        fi

        if [[ "$line" == \#* ]]; then
            comment="$(resource_clean_label "$line")"
            if [[ -n "$pending_url" ]]; then
                [[ -n "$comment" ]] && post_label="$comment"
            else
                label="$comment"
            fi
            continue
        fi

        if [[ "$line" == open[[:space:]]* ]]; then
            line="${line#open }"
            line="${line#open$'\t'}"
        fi
        url="$line"
        if [[ "$url" != http://* && "$url" != https://* ]]; then
            if [[ -n "$pending_url" && -n "$post_label" ]]; then
                pending_label="$post_label"
                post_label=""
            fi
            continue
        fi
        case "$mode" in
            dmg|pkg|zip|app|appstore|"") ;;
            *) continue ;;
        esac

        if [[ -n "$pending_url" ]]; then
            write_resource_record "$pending_url" "$pending_label" "$pending_site" "$tmp"
            pending_url=""; pending_label=""; pending_site=""
            [[ -n "$post_label" ]] && label="$post_label"
            post_label=""
        fi
        pending_url="$url"
        pending_label="$label"
        label=""
        if [[ -z "$pending_label" ]]; then
            host="${url%%\?*}"
            host="${host%%\#*}"
            filename="${host##*/}"
            pending_label="${filename%.*}"
            [[ -n "$pending_label" ]] || pending_label="$host"
        fi
        pending_site="$(resource_site_domain "$url")"
    done < "$input"

    if [[ -n "$pending_url" ]]; then
        write_resource_record "$pending_url" "$pending_label" "$pending_site" "$tmp"
    fi
    mv "$tmp" "$output"
}

# A package file may run twice in one dispatch; install each entry once
already_done() {
    local name="$1"; shift
    [[ " $* " == *" $name "* ]]
}

# 0 = not set up yet, 1 = ready
brew_ready=0

brew_prepare() {
    (( brew_ready )) && return 0
    export HOMEBREW_NO_ANALYTICS=1
    export HOMEBREW_NO_ENV_HINTS=1

    if ! command -v brew >/dev/null; then
        echo "[BREW] Homebrew not found, installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
        grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null ||
            echo 'eval "$(/opt/homebrew/bin/brew shellenv zsh)"' >> "$HOME/.zprofile"
    fi

    # the apt full-upgrade equivalent
    brew update
    brew upgrade
    brew_ready=1
}

install_brew() {
    local pkg="$1"
    if already_done "$pkg" "${brew_pkg[@]}"; then
        echo -e "\n>>> [BREW] $pkg already installed in this run, skipping"
        return 0
    fi
    if brew list --formula "$pkg" >/dev/null 2>&1; then
        echo -e "\n>>> [BREW] $pkg already installed, skipping"
        brew_pkg+=("$pkg")
        return 0
    fi
    echo -e "\n>>> [BREW] Installing formula: $pkg"
    if brew install "$pkg"; then
        brew_pkg+=("$pkg")
    else
        echo "!!! Failed to install: $pkg"
    fi
}

install_cask() {
    local pkg="$1"
    if already_done "$pkg" "${cask_pkg[@]}"; then
        echo -e "\n>>> [CASK] $pkg already installed in this run, skipping"
        return 0
    fi
    if brew list --cask "$pkg" >/dev/null 2>&1; then
        echo -e "\n>>> [CASK] $pkg already installed, skipping"
        cask_pkg+=("$pkg")
        return 0
    fi
    echo -e "\n>>> [CASK] Installing app: $pkg"
    if brew install --cask "$pkg"; then
        cask_pkg+=("$pkg")
    else
        echo "!!! Failed to install: $pkg"
    fi
}

# Entries are either <id> or <name>=<id>; the name is only for the log
install_mas() {
    local entry="$1" id="${1#*=}"
    command -v mas >/dev/null || install_brew mas
    if already_done "$id" "${mas_pkg[@]}"; then
        echo -e "\n>>> [MAS] $entry already installed in this run, skipping"
        return 0
    fi
    if mas list 2>/dev/null | awk '{print $1}' | grep -qx "$id"; then
        echo -e "\n>>> [MAS] $entry already installed, skipping"
        mas_pkg+=("$id")
        return 0
    fi
    echo -e "\n>>> [MAS] Installing App Store app: $entry"
    if mas install "$id"; then
        mas_pkg+=("$id")
    else
        echo "!!! Failed to install: $entry (signed in to the App Store? iPhone-only app?)"
    fi
}

install_npm() {
    local pkg="$1"
    if already_done "$pkg" "${npm_pkg[@]}"; then
        echo -e "\n>>> [NPM] $pkg already installed in this run, skipping"
        return 0
    fi
    command -v npm >/dev/null || install_brew node
    echo -e "\n>>> [NPM] Installing package: $pkg"
    # Homebrew's node owns its global prefix, so no sudo
    if npm install -g "$pkg"; then
        npm_pkg+=("$pkg")
    else
        echo "!!! Failed to install: $pkg"
    fi
}

# Resource package lists support --brew , --cask, --mas,--dmg, --pkg, --zip, --app, and --appstore.
run_packages() {
    local pkgfile="$1"
    [[ -f "$pkgfile" ]] || { echo "!!! Package file not found: $pkgfile"; return 1; }
    generate_resource_env "$pkgfile" "$SCRIPT_DIR/~resources/macos-resources.env" || { echo "!!! Could not create site index"; return 1; }


    echo -e "\n[RESOURCES] Installing app resources from $pkgfile..."
    local line item mode="" lines items
    read_lines "$pkgfile"
    lines=("${LINES[@]}")

    for line in "${lines[@]}"; do
        line="${line%%#*}"
        read -ra items <<< "$line"
        for item in "${items[@]}"; do
            case "$item" in
                --brew|--cask|--mas|--dmg|--pkg|--zip|--app|--appstore) mode="${item#--}" ;;
                --*) echo "!!! Unsupported section in nexus-macos-resources.sh: $item"; mode="" ;;
                *)
                    case "$mode" in
			brew) install_brew "$item" ;;
			cask) install_cask "$item" ;;
			mas) install_mas "$item" ;;
                        dmg) run_dmg "$item" ;;
                        pkg) run_pkg "$item" ;;
                        zip) run_zip "$item" ;;
                        app) run_app "$item" ;;
                        appstore) appstore_url+=("$item") ;;
                        *)   echo "!!! No --brew, --cask, --mas, --dmg, --pkg, --zip, --app, or --appstore section before: $item" ;;
                    esac
                    ;;
            esac
        done
    done
}

# Refuse apps that aren't signed and notarized; pake builds are ad-hoc
# signed on this machine, so their caller skips this check
verify_app() {
    local app="$1"
    if ! codesign --verify --deep --strict "$app" 2>/dev/null; then
        echo "!!! Bad code signature: $app"
        return 1
    fi
    if ! spctl --assess --type execute "$app" 2>/dev/null; then
        echo "!!! Gatekeeper rejected (not notarized): $app"
        return 1
    fi
    echo "[VERIFY] $(basename "$app"): signature and notarization OK"
}

app_version() {
    defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null
}

# Replace the Finder alias for an installed application in the Nexus applications folder.
refresh_app_alias() {
    local app_path="$1" alias_dir="$repo/applications" alias_name alias_path
    [[ -d "$app_path" ]] || return 1
    alias_name="$(basename "$app_path")"
    alias_path="$alias_dir/$alias_name"
    mkdir -p "$alias_dir" || { echo "!!! Could not create alias folder: $alias_dir"; return 1; }

    # Remove only the same-name previous alias, then recreate it against the
    # current app bundle so updates never leave duplicate aliases behind.
    rm -f "$alias_path"
    if ! osascript \
        -e 'on run argv' \
        -e 'set appFile to POSIX file (item 1 of argv)' \
        -e 'set targetFolder to POSIX file (item 2 of argv)' \
        -e 'set aliasName to item 3 of argv' \
        -e 'tell application "Finder" to make new alias file at targetFolder to appFile with properties {name:aliasName}' \
        -e 'end run' \
        "$app_path" "$alias_dir" "$alias_name"; then
        echo "!!! Could not refresh Finder alias for: $app_path"
        return 1
    fi
    echo "[ALIAS] Refreshed $alias_dir/$alias_name"
}

# Copy every .app / run every .pkg found in a folder (a mounted .dmg or an
# unzipped archive). Sets INSTALLED to the bundle names it installed.
# $2 = "noverify" to skip the signature check
install_from_dir() {
    local dir="$1" check="${2:-verify}" item name ver cur
    INSTALLED=()

    while IFS= read -r item; do
        name="$(basename "$item")"
        if [[ "$check" == verify ]]; then
            verify_app "$item" || continue
        fi

        # Install only when missing or when the download is newer than what's installed
        ver="$(app_version "$item")"
        if [[ -d "/Applications/$name" ]]; then
            cur="$(app_version "/Applications/$name")"
            if [[ -n "$ver" && -n "$cur" ]] &&
               [[ "$(printf '%s\n%s\n' "$cur" "$ver" | sort -V | tail -1)" == "$cur" ]]; then
                echo "[APP] $name $cur Installed, download is $ver , current version is (UPDATED), skipping"
                refresh_app_alias "/Applications/$name" || true
                INSTALLED+=("$name")
                continue
            fi
            echo "[APP] Updating $name $cur -> $ver"
            rm -rf "/Applications/$name" 2>/dev/null || sudo rm -rf "/Applications/$name"
        fi

        echo "[APP] Copying $name to /Applications"
        ditto "$item" "/Applications/$name" 2>/dev/null || sudo ditto "$item" "/Applications/$name"
        [[ -d "/Applications/$name" ]] && refresh_app_alias "/Applications/$name" || true
        INSTALLED+=("$name")
    done < <(find "$dir" -maxdepth 2 -name '*.app' -type d -prune 2>/dev/null)

    while IFS= read -r item; do
        run_pkg_file "$item" && INSTALLED+=("$(basename "$item")")
    done < <(find "$dir" -maxdepth 2 -name '*.pkg' 2>/dev/null)
}

run_pkg_file() {
    local file="$1" item app_path
    if ! pkgutil --check-signature "$file" >/dev/null 2>&1; then
        echo "!!! Unsigned installer package, skipping: $file"
        return 1
    fi
    echo "[PKG] Installing $(basename "$file") (needs your password)"
    sudo installer -pkg "$file" -target / || return 1

    # Refresh aliases for app bundles installed by this package, if any.
    while IFS= read -r item; do
        app_path="/$item"
        [[ -d "$app_path" ]] && refresh_app_alias "$app_path" || true
    done < <(pkgutil --payload-files "$file" 2>/dev/null | sed -E -n 's#^(Applications/.*\.app)(/.*)?$#\1#p' | sort -u)
}

# Download into a fresh temp folder and set DOWNLOADED to the file's path.
# Stable "latest" links (.../mac/dmg/arm64, .../mac/download) don't end in
# the file name: -J takes it from the server, else from the final redirect
download() {
    local url="$1" dir final name
    dir="$(mktemp -d)"
    echo -e "\n[DOWNLOAD] $url"
    if ! final="$(cd "$dir" && curl -fL --progress-bar -O -J -w '%{url_effective}' "$url")"; then
        echo "!!! Download failed: $url"
        rm -rf "$dir"
        return 1
    fi
    DOWNLOADED="$(find "$dir" -type f -print -quit)"

    if [[ "$(basename "$DOWNLOADED")" != *.* ]]; then
        name="${final%%[\?#]*}"
        name="${name##*/}"
        name="$(printf '%b' "${name//%/\\x}")"
        if [[ "$name" == *.* ]]; then
            mv "$DOWNLOADED" "$dir/$name"
            DOWNLOADED="$dir/$name"
        fi
    fi
}

run_dmg() {
    local url="$1"
    download "$url" || return 1
    cp "$DOWNLOADED" "$store/dmg/"
    install_dmg_file "$DOWNLOADED" verify && dmg_pkg+=("$(basename "$DOWNLOADED")")
}

install_dmg_file() {
    local file="$1" check="$2" mnt
    mnt="$(mktemp -d)"
    if ! hdiutil attach "$file" -nobrowse -readonly -noautoopen -mountpoint "$mnt" >/dev/null; then
        echo "!!! Could not mount: $file"
        rmdir "$mnt"
        return 1
    fi
    install_from_dir "$mnt" "$check"
    hdiutil detach "$mnt" -quiet || hdiutil detach "$mnt" -force -quiet
    rmdir "$mnt" 2>/dev/null
    (( ${#INSTALLED[@]} > 0 )) || { echo "!!! Nothing installed from: $file"; return 1; }
}

run_pkg() {
    local url="$1" name
    # a .pkg has no version check, so a kept copy of a versioned file
    # (container-1.6.1-...pkg) means this release is already installed
    name="${url%%[\?#]*}"
    name="${name##*/}"
    if [[ "$name" == *.pkg && -f "$store/pkg/$name" ]]; then
        echo -e "\n[PKG] $name already installed, skipping"
        pkg_pkg+=("$name")
        return 0
    fi
    download "$url" || return 1
    cp "$DOWNLOADED" "$store/pkg/"
    run_pkg_file "$DOWNLOADED" && pkg_pkg+=("$(basename "$DOWNLOADED")")
}

run_zip() {
    local url="$1" dir
    download "$url" || return 1
    cp "$DOWNLOADED" "$store/zip/"
    dir="$(mktemp -d)"
    ditto -x -k "$DOWNLOADED" "$dir"
    install_from_dir "$dir" verify
    rm -rf "$dir"
    (( ${#INSTALLED[@]} > 0 )) && dmg_pkg+=("$(basename "$DOWNLOADED")")
}

run_app() {
    local url="$1" asset="${1%%[\?#]*}"
    case "$asset" in
        *.dmg) run_dmg "$url" ;;
        *.zip) run_zip "$url" ;;
        *)
            echo "!!! --app expects a .dmg or .zip URL containing a .app bundle: $url"
            return 1
            ;;
    esac
}

run_tar() {
    local url="$1"
    local dest="/usr/local/src"
    download "$url" || return 1
    local filename
    filename="$(basename "$DOWNLOADED")"
    local target_path="$dest/$filename"

    sudo mkdir -p "$dest"
    sudo mv "$DOWNLOADED" "$target_path"

    echo -e "[TAR] Extracting $filename..."
    sudo tar -xf "$target_path" -C "$dest"
    cp "$target_path" "$store/src/"
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

# Apps with no installer we can automate: open the download page.
# mas can't install iPhone/iPad apps, so App Store links (…/id<number>)
# open in the App Store app, unless that app is already installed
run_open() {
    local url="$1" id
    if [[ "$url" =~ /id([0-9]+) ]]; then
        id="${BASH_REMATCH[1]}"
        if [[ -n "$(mdfind "kMDItemAppStoreAdamID == $id" 2>/dev/null)" ]]; then
            echo -e "\n[OPEN] App Store app $id already installed, skipping"
            return 0
        fi
        url="macappstores://apps.apple.com/app/id$id"
    fi
    echo -e "\n[OPEN] Install by hand: $url"
    open "$url"
    manual_url+=("$url")
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
    lower "$name"
}

# 0 = not set up yet, 1 = ready, 2 = setup failed
pake_ready=0

pake_prepare() {
    (( pake_ready == 1 )) && return 0
    (( pake_ready == 2 )) && return 1

    # rustup installs per user; make it visible in a non-login shell
    [[ -x "$HOME/.cargo/bin/cargo" ]] && export PATH="$HOME/.cargo/bin:$PATH"

    # Install only when missing: a pake-cli upgrade changes every app's
    # fingerprint and rebuilds them all, so upgrade it by hand
    command -v pake >/dev/null || install_npm pake-cli

    command -v pake >/dev/null || { echo "pake is not installed (npm install -g pake-cli)"; pake_ready=2; return 1; }
    command -v cargo >/dev/null || { echo "pake needs Rust (brew install rustup && rustup-init)"; pake_ready=2; return 1; }
    xcode-select -p >/dev/null 2>&1 || { echo "pake needs the Xcode tools (xcode-select --install)"; pake_ready=2; return 1; }
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

    if already_done "$name" "${pake_pkg[@]}"; then
        echo -e "\n>>> [PAKE] $name already built in this run, skipping"
        return 0
    fi

    # Pake apps are always 1.0.0, so compare the build inputs instead:
    # skip when they match the last install and the app is still there
    local flags=(--name "$name")
    local stamp="$store/pake/.stamps/$name" fp old_fp bundle
    fp="$(printf '%s\n' "$(pake --version 2>/dev/null)" "$url" "${flags[@]}" | shasum -a 256 | cut -d' ' -f1)"
    if [[ -f "$stamp" ]]; then
        read -r old_fp bundle < "$stamp"
        if [[ "$old_fp" == "$fp" && -d "/Applications/$bundle" ]]; then
            echo -e "\n>>> [PAKE] $name unchanged since last install, skipping"
            pake_pkg+=("$name")
            return 0
        fi
    fi

    echo -e "\n>>> [PAKE] Building Desktop App : $name ($url)"
    local build dmg
    build="$(mktemp -d)"
    if ! ( cd "$build" && pake "$url" "${flags[@]}" ); then
        echo "!!! Pake build failed: $url"
        rm -rf "$build"
        return 1
    fi

    dmg="$(find "$build" -maxdepth 3 -name '*.dmg' -print -quit)"
    if [[ -z "$dmg" ]]; then
        echo "!!! No .dmg produced for: $url"
        rm -rf "$build"
        return 1
    fi

    cp "$dmg" "$store/pake/"
    # a pake build is a fresh 1.0.0 every time, so replace the old copy first
    [[ -n "$bundle" ]] && rm -rf "/Applications/$bundle"
    if install_dmg_file "$dmg" noverify; then
        pake_pkg+=("$name")
        mkdir -p "${stamp%/*}"
        echo "$fp ${INSTALLED[0]}" > "$stamp"
    fi
    rm -rf "$build"
}

print_section() {
    echo -e "\n\n>>> $1 :"
    echo -e "==========================================="
    shift
    (( $# )) && printf '%s\n' "$@"
}

print_summary() {
    print_section "Brew Formulae" "${brew_pkg[@]}"
    print_section "Brew Casks" "${cask_pkg[@]}"
    print_section "App Store Apps" "${mas_pkg[@]}"
    print_section "NPM Packages" "${npm_pkg[@]}"
    print_section "DMG / ZIP Apps" "${dmg_pkg[@]}"
    print_section "PKG Installers" "${pkg_pkg[@]}"
    print_section "Source-Code" "${src_code[@]}"
    print_section "Pake Apps" "${pake_pkg[@]}"
    print_section "Install By Hand" "${manual_url[@]}"
    print_section "App Store URLs" "${appstore_url[@]}"
    echo -e "\n\n"
}

# ---------------- USAGE ----------------
usage() {
    echo -e "\nUsage: $0 -f <envfile> (or --file <envfile>)"
    echo "Sections supported: --brew, --cask, --mas,--dmg, --pkg, --zip, --app, --appstore"
    exit 1
}

[[ $# -gt 0 ]] || usage
MODE=""
VALUE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)
            [[ -n "${2:-}" ]] || { echo "Missing value for $1"; exit 1; }
            MODE="$1"; VALUE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unsupported option for nexus-macos-resources.sh: $1"; usage ;;
    esac
done

[[ "$MODE" == -f || "$MODE" == --file ]] && [[ ! -f "$VALUE" ]] && VALUE="$SCRIPT_DIR/$VALUE"
run_packages "$VALUE"

echo -e "\n============================================\n"

print_summary
