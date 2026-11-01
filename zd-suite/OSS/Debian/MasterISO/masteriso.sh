#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
user="$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")"
ISO_DIR="/home/${user}/Documents/MasterISO"
partial=""
iso_img=()

echo -e "\n=============================="
echo -e "     LR-NEXUS MasterISO"
echo -e "==============================\n"


# a download that does not complete is deleted at once, including on Ctrl-C
cleanup() {
    if [[ -n "$partial" ]]; then rm -f -- "$partial"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

usage() {
    printf 'Usage: %s -F HTTPS_URL | -f DISPATCH_FILE\n' "$0" >&2
}

run_iso() {
    local url="$1" name
    case "$url" in
        https://*) ;;
        *) printf 'Error: an HTTPS URL is required.\n' >&2; return 1 ;;
    esac
    name="${url%%\?*}"
    name="${name##*/}"
    case "$name" in
        ''|.|..) printf 'Error: URL must name a file.\n' >&2; return 1 ;;
    esac

    mkdir -p -- "$ISO_DIR"
    partial="$ISO_DIR/$name.part"
    printf '\n\nDownloading: %s\n' "$name"
    echo -e "=============================================\n"
    if (cd -- "$ISO_DIR" && wget -nv --show-progress "$url" -O "$name.part") \
            && mv -- "$partial" "$ISO_DIR/$name"; then
        partial=""
        printf 'Downloaded: %s\n' "$name"
        iso_img+=("$name")
        return 0
    fi
    rm -f -- "$partial"
    partial=""
    printf 'Error: download failed.\n' >&2
    return 1
}

dispatch_file() {
    local file="$1" line option url extra failed=0
    # a relative dispatch file is looked up next to the script when not found here
    [[ -f "$file" || "$file" == /* ]] || file="$SCRIPT_DIR/$file"
    [[ -f "$file" ]] || { printf 'Error: dispatch file not found.\n' >&2; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        read -r option url extra <<< "$line"
        case "$option" in
            ''|\#*) continue ;;
            --iso)
                if [[ -z "$url" || -n "$extra" ]]; then
                    printf 'Error: expected --iso HTTPS_URL.\n' >&2
                    return 1
                fi
                run_iso "$url" || failed=$((failed + 1))
                ;;
            *) printf 'Error: unknown dispatch option.\n' >&2; return 1 ;;
        esac
    done < "$file"
    if (( failed )); then
        printf 'Error: %d download(s) failed.\n' "$failed" >&2
        return 1
    fi
}

print_summary() {
    echo -e "\n\n>>> ISO Images :"
    echo -e "==========================================="
    printf 'Directory: %s\n\n' "$ISO_DIR"
    printf '%s\n' "${iso_img[@]}"
    echo -e "\n\n"
}

[[ $# -eq 2 ]] || { usage; exit 1; }
# a failed download must not skip the summary of the ones that completed
status=0
case "$1" in
    -F|--URL) run_iso "$2" || status=$? ;;
    -f|--file) dispatch_file "$2" || status=$? ;;
    *) usage; exit 1 ;;
esac
print_summary
exit "$status"
