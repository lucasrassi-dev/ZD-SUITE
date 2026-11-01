#!/usr/bin/env bash

# Open resource URLs from a file. Installer URLs are opened unchanged; their
# final path extension is detected for reporting. App Store URLs stay intact.

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
                --dmg|--pkg|--zip|--app|--appstore) mode="${line#--}" ;;
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

SCRIPT_NAME="${0##*/}"

usage() {
    echo "Usage: $SCRIPT_NAME -f <resource-file> (or --file <resource-file>)"
    echo "Sections: --dmg, --pkg, --zip, --app, --appstore"
    exit 1
}

[[ $# -gt 0 ]] || usage

resource_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|-file|--file)
            [[ -n "${2:-}" ]] || { echo "Missing value for $1" >&2; exit 1; }
            resource_file="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unsupported option: $1" >&2
            usage
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$resource_file" ]] || resource_file="$SCRIPT_DIR/$resource_file"
[[ -f "$resource_file" ]] || { echo "Resource file not found: $resource_file" >&2; exit 1; }

SITE_ENV="$SCRIPT_DIR/~resources/macos-resources.env"
generate_resource_env "$resource_file" "$SITE_ENV" || { echo "Could not create: $SITE_ENV" >&2; exit 1; }

mode=""
opened=0

while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    if [[ "$line" == --* ]]; then
        case "$line" in
            --dmg|--pkg|--zip|--app|--appstore) mode="${line#--}" ;;
            *) echo "Unsupported section: $line" >&2; mode="" ;;
        esac
        continue
    fi

    # Accept either bare URLs or lines written as: open <url>
    if [[ "$line" == open[[:space:]]* ]]; then
        line="${line#open }"
        line="${line#open$'\t'}"
    fi
    url="$line"
    [[ "$url" == http://* || "$url" == https://* ]] || continue

    # Detect the extension only from the final URL path segment; query strings
    # and fragments do not affect it. Redirect URLs may have no extension.
    url_path="${url%%\?*}"
    url_path="${url_path%%\#*}"
    filename="${url_path##*/}"
    extension=""
    if [[ "$filename" == *.* ]]; then
        extension="${filename##*.}"
        extension="$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"
    fi

    if [[ "$mode" == appstore ]]; then
        echo "[OPEN] App Store URL: $url"
    else
        echo "[OPEN] ${mode:-resource}${extension:+ (.$extension)}: $url"
    fi
    open "$url" || echo "!!! Could not open: $url" >&2
    opened=$((opened + 1))
done < "$resource_file"

echo "Opened $opened URL(s) from $resource_file"
