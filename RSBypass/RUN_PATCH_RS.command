#!/bin/bash
# Install or remove the Rocksmith 2014 CDLC patch.
# The game is x86_64, including under Rosetta 2 on Apple Silicon.
# uname -m prints arm64 on those Macs; that does not change the dylib.

LEGACY_LINK="https://github.com/aik002/RSBypass/blob/main/LEGACY.md"

rs_hash() {
    if command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
    else
        printf '%s' "$1" | sha256sum | awk '{print $1}'
    fi
}

# Print "1<TAB>binary" when this Steam library contains Rocksmith and its
# appmanifest, or "0<TAB>binary" when the app is present without the manifest.
rs_consider_root() {
    local root="$1"
    local bin=""
    local manifest=""

    if [ -f "$root/steamapps/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS/Rocksmith2014" ]; then
        bin="$root/steamapps/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS/Rocksmith2014"
        manifest="$root/steamapps/appmanifest_221680.acf"
    elif [ -f "$root/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS/Rocksmith2014" ]; then
        bin="$root/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS/Rocksmith2014"
        manifest="$root/appmanifest_221680.acf"
    else
        return 1
    fi

    if [ -f "$manifest" ]; then
        printf '1\t%s\n' "$bin"
    else
        printf '0\t%s\n' "$bin"
    fi
}

# $1 libraryfolders.vdf (may be missing), $2 default Steam root.
# Prefer a library whose appmanifest lists appid 221680.
rs_pick_game() {
    local vdf="$1"
    local default_root="$2"
    local roots="$default_root"
    local best=""
    local best_has=0
    local root result has bin

    if [ -n "$vdf" ] && [ -f "$vdf" ]; then
        roots="$roots
$(sed -n 's/.*"\(\/[^"]*\)".*/\1/p' "$vdf")"
    fi

    while IFS= read -r root; do
        [ -n "$root" ] || continue
        result=$(rs_consider_root "$root") || continue
        has=${result%%$'\t'*}
        bin=${result#*$'\t'}
        if [ -z "$best" ] || { [ "$has" = 1 ] && [ "$best_has" = 0 ]; }; then
            best="$bin"
            best_has=$has
        fi
    done <<EOF
$roots
EOF

    if [ -z "$best" ]; then
        return 1
    fi
    printf '%s\n' "$best"
}

rs_find_dylib() {
    local dir="$1"
    local candidate
    for candidate in \
        "$dir/libRSBypass.dylib" \
        "$dir/RSBypass.dylib" \
        "$dir/Sonoma/libRSBypass.dylib" \
        "$dir/x64/libRSBypass.dylib" \
        "$dir/x64.Legacy/libRSBypass.dylib" \
        "$dir/ARM/libRSBypass.dylib"
    do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if [ -f "$dir/../libRSBypass.dylib" ]; then
        local parent
        parent=$(cd "$dir/.." && pwd)
        printf '%s\n' "$parent/libRSBypass.dylib"
        return 0
    fi
    return 1
}

rs_find_insert() {
    local dir="$1"
    local parent
    if [ -x "$dir/insert_dylib" ] || [ -f "$dir/insert_dylib" ]; then
        printf '%s\n' "$dir/insert_dylib"
        return 0
    fi
    if [ -f "$dir/../insert_dylib" ]; then
        parent=$(cd "$dir/.." && pwd)
        printf '%s\n' "$parent/insert_dylib"
        return 0
    fi
    return 1
}

rs_has_x86_64() {
    local target="$1"
    if command -v lipo >/dev/null 2>&1; then
        if lipo -info "$target" 2>/dev/null | grep -q x86_64; then
            return 0
        fi
    fi
    file "$target" 2>/dev/null | grep -q x86_64
}

rs_capture_ents() {
    local target="$1"
    local dest="$2"
    rm -f "$dest"
    codesign -d --entitlements :- "$target" >"$dest" 2>/dev/null || true
    if [ ! -s "$dest" ] || ! grep -q '<key>' "$dest"; then
        rm -f "$dest"
        return 1
    fi
    return 0
}

rs_sign() {
    local target="$1"
    local ents="${2:-}"
    if [ -n "$ents" ] && [ -f "$ents" ]; then
        codesign --force --sign - --entitlements "$ents" "$target"
    else
        codesign --force --sign - "$target"
    fi
}

die() {
    printf 'Error: %s\n' "$1" >&2
    if [ -t 0 ]; then
        printf 'Press Return to close... '
        read -r _
    fi
    exit 1
}

pause_at_end() {
    if [ -t 0 ]; then
        printf 'Press Return to close... '
        read -r _
    fi
}

rs_resolve_game() {
    local explicit="${RS_PATH:-}"
    local vdf="$HOME/Library/Application Support/Steam/steamapps/libraryfolders.vdf"
    local default_root="$HOME/Library/Application Support/Steam"

    if [ -n "$explicit" ]; then
        if [ -f "$explicit" ]; then
            printf '%s\n' "$explicit"
            return 0
        fi
        if [ -f "$explicit/Rocksmith2014" ]; then
            printf '%s\n' "$explicit/Rocksmith2014"
            return 0
        fi
        if [ -f "$explicit/Contents/MacOS/Rocksmith2014" ]; then
            printf '%s\n' "$explicit/Contents/MacOS/Rocksmith2014"
            return 0
        fi
        printf 'RS_PATH is set but Rocksmith2014 was not found at: %s\n' "$explicit" >&2
        return 1
    fi

    rs_pick_game "$vdf" "$default_root"
}

main() {
    local mode="install"
    local script_dir
    local bin app macos backup key dylib insert already ents product major

    set -o pipefail
    set -e

    if [ "${1:-}" = "uninstall" ] || [ "${1:-}" = "--uninstall" ]; then
        mode="uninstall"
    elif [ -n "${1:-}" ]; then
        die "Unknown argument: $1 (use: uninstall)"
    fi

    if ! command -v sw_vers >/dev/null 2>&1; then
        die "This installer is for macOS."
    fi

    script_dir=$(cd "$(dirname "$0")" && pwd)
    product=$(sw_vers -productVersion)
    major=${product%%.*}
    case "$major" in
        ''|*[!0-9]*) major=0 ;;
    esac

    printf 'macOS %s (%s), uname -m %s\n' "$product" "$(sw_vers -buildVersion)" "$(uname -m)"
    printf 'Rocksmith 2014 runs as x86_64. On Apple Silicon that is Rosetta, even when uname prints arm64.\n'

    if [ "$major" -lt 12 ]; then
        printf 'insert_dylib in this package needs macOS 12 or newer. See %s\n' "$LEGACY_LINK"
    fi

    if ! bin=$(rs_resolve_game); then
        die "Could not find Rocksmith2014. Install it in Steam, or set RS_PATH to the .app, the Contents/MacOS folder, or the executable."
    fi
    app=$(cd "$(dirname "$bin")/../.." && pwd)
    macos=$(dirname "$bin")
    case "$app" in
        *.app) ;;
        *) die "Resolved path is not inside a .app bundle: $bin" ;;
    esac

    printf 'Game: %s\n' "$bin"

    if ! rs_has_x86_64 "$bin"; then
        die "This Rocksmith binary has no x86_64 slice. The patch is built for the x86_64 game."
    fi

    if command -v pgrep >/dev/null 2>&1 && pgrep -x Rocksmith2014 >/dev/null 2>&1; then
        die "Quit Rocksmith 2014 completely, then run this again."
    fi

    if [ ! -w "$macos" ]; then
        die "Cannot write to $macos. The Steam library should be in your account. Do not re-run this with sudo."
    fi

    key=$(rs_hash "$bin")
    backup="$HOME/Library/Application Support/RSBypass/$key"

    if [ "$mode" = "uninstall" ]; then
        if [ ! -f "$backup/Rocksmith2014" ]; then
            die "No backup for this install. In Steam use Properties, Installed Files, Verify integrity of game files."
        fi
        rm -f "$macos/libRSBypass.dylib"
        cp -p "$backup/Rocksmith2014" "$bin" || die "Could not restore the executable."
        if [ -d "$backup/CodeSignature" ]; then
            rm -rf "$app/Contents/_CodeSignature"
            cp -R "$backup/CodeSignature" "$app/Contents/_CodeSignature"
        else
            rm -rf "$app/Contents/_CodeSignature"
        fi
        xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
        printf 'Restored the original executable.\n'
        printf 'Backup left at: %s\n' "$backup"
        pause_at_end
        return 0
    fi

    dylib=$(rs_find_dylib "$script_dir") || die "libRSBypass.dylib was not found next to this script. Download the CI artifact or copy a built dylib here."
    insert=$(rs_find_insert "$script_dir") || die "insert_dylib was not found next to this script or in the repo root."

    if ! rs_has_x86_64 "$dylib"; then
        die "The dylib at $dylib has no x86_64 slice. An arm64-only dylib cannot load into Rocksmith."
    fi

    printf 'Dylib: %s\n' "$dylib"
    printf 'insert_dylib: %s\n' "$insert"

    xattr -dr com.apple.quarantine "$script_dir" 2>/dev/null || true
    xattr -d com.apple.quarantine "$insert" 2>/dev/null || true
    xattr -d com.apple.quarantine "$dylib" 2>/dev/null || true
    chmod +x "$insert" "$dylib" 2>/dev/null || true

    # Ad-hoc sign the tool before executing it. A downloaded copy is often
    # rejected by Gatekeeper / AMFI until it has a local signature.
    rs_sign "$insert" || die "Could not ad-hoc sign insert_dylib."

    already=0
    if otool -L "$bin" 2>/dev/null | grep -q libRSBypass; then
        already=1
        printf 'Load command already present. Updating the dylib in place.\n'
    fi

    ents="$backup/entitlements.plist"
    if [ "$already" -eq 0 ]; then
        mkdir -p "$backup" || die "Could not create $backup"
        if codesign -d --verbose=4 "$bin" 2>&1 | grep -q 'flags=.*runtime'; then
            printf 'The game binary uses the hardened runtime. Re-signing without it so this dylib can load.\n'
        fi
        cp -p "$bin" "$backup/Rocksmith2014" || die "Could not back up the executable. Nothing was modified."
        rm -rf "$backup/CodeSignature"
        if [ -d "$app/Contents/_CodeSignature" ]; then
            cp -R "$app/Contents/_CodeSignature" "$backup/CodeSignature"
        fi
        rs_capture_ents "$bin" "$ents" || rs_capture_ents "$app" "$ents" || true
        printf '%s\n' "$bin" >"$backup/source_path.txt"
        printf 'Backup: %s\n' "$backup"
    fi

    cp -f "$dylib" "$macos/libRSBypass.dylib" || die "Could not copy the dylib into the game."
    chmod 755 "$macos/libRSBypass.dylib"
    xattr -d com.apple.quarantine "$macos/libRSBypass.dylib" 2>/dev/null || true
    rs_sign "$macos/libRSBypass.dylib" || die "Could not ad-hoc sign libRSBypass.dylib."

    if [ "$already" -eq 0 ]; then
        # @executable_path keeps working if the Steam library is not in the default folder.
        # The dylib file itself is checked above; insert_dylib is told to continue
        # because this path is expanded by dyld, not by the tool.
        if ! "$insert" --inplace --strip-codesig --all-yes \
            "@executable_path/libRSBypass.dylib" "$bin"; then
            printf 'insert_dylib failed. Restoring the backup.\n' >&2
            cp -p "$backup/Rocksmith2014" "$bin" || true
            if [ -d "$backup/CodeSignature" ]; then
                rm -rf "$app/Contents/_CodeSignature"
                cp -R "$backup/CodeSignature" "$app/Contents/_CodeSignature"
            fi
            die "Could not insert the load command."
        fi
    fi

    if ! otool -L "$bin" | grep -q libRSBypass; then
        die "The game binary does not reference libRSBypass.dylib."
    fi

    if [ ! -f "$ents" ]; then
        mkdir -p "$backup"
        rs_capture_ents "$bin" "$ents" || rs_capture_ents "$app" "$ents" || true
    fi

    if [ -f "$ents" ]; then
        rs_sign "$bin" "$ents" || die "Could not ad-hoc sign Rocksmith2014."
    else
        rs_sign "$bin" || die "Could not ad-hoc sign Rocksmith2014."
    fi

    # Sign the bundle last so its seal covers the signed executable and dylib.
    # No hardened runtime: library validation would reject this ad-hoc dylib.
    if ! rs_sign "$app" "$ents"; then
        printf 'Warning: re-signing the app bundle failed.\n'
        printf 'The executable was signed. Launch Rocksmith from Steam.\n'
        printf 'If macOS blocks a double-clicked script, run this file from Terminal with bash.\n'
    fi

    xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

    printf '\nPatched. Launch Rocksmith from Steam and load a CDLC song.\n'
    printf 'Console.app should show "RSBypass: patched" during startup.\n'
    printf 'Undo with: bash "%s" uninstall\n' "$0"
    pause_at_end
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
