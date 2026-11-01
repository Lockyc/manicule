#!/usr/bin/env bash
# install.sh — install Manicule from its latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/lockyc/manicule/main/install.sh | bash
# Installs /Applications/Manicule.app, registers it with Launch Services and launches it;
# Manicule updates itself from then on.
# MANICULE_ZIP_URL and MANICULE_APP_DIR override the download and the install folder.
set -euo pipefail

main() {
    zip_url=${MANICULE_ZIP_URL:-https://github.com/lockyc/manicule/releases/latest/download/Manicule.zip}
    app_dir=${MANICULE_APP_DIR:-/Applications}
    team=G9V8U6ZU5E
    lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

    fail() { echo "manicule: $*" >&2; exit 1; }

    [ "$(uname)" = Darwin ] || fail "Manicule runs on macOS only."
    major=$(sw_vers -productVersion | cut -d. -f1)
    [ "$major" -ge 14 ] || fail "Manicule needs macOS 14 or later; this Mac runs $(sw_vers -productVersion)."

    # Runs a command as the user, or with sudo when $1 (a directory) isn't writable.
    in_dir() {
        local dir=$1
        shift
        if [ -w "$dir" ]; then "$@"; else sudo "$@"; fi
    }

    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    echo "→ downloading Manicule"
    curl -fsSL "$zip_url" -o "$work/Manicule.zip" || fail "couldn't download $zip_url"
    ditto -x -k "$work/Manicule.zip" "$work/unzipped" || fail "the download isn't a zip."
    new="$work/unzipped/Manicule.app"
    [ -d "$new" ] || fail "the download holds no Manicule.app."
    [ -z "$(find "$work/unzipped" -maxdepth 1 -type l)" ] && [ ! -L "$new" ] \
        || fail "the download's Manicule.app is a link."
    codesign --verify --strict --deep "$new" 2>/dev/null || fail "the download's signature doesn't verify."
    info=$(codesign -dv "$new" 2>&1) || fail "the download's signature can't be read."
    printf '%s\n' "$info" | grep -qx "TeamIdentifier=$team" \
        || fail "the download isn't signed by Manicule's developer."
    spctl --assess --type execute "$new" 2>/dev/null || fail "macOS won't open the download: it isn't notarized."
    version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$new/Contents/Info.plist")

    if pgrep -U "$(id -u)" -x manicule >/dev/null; then
        echo "→ quitting the running Manicule"
        pkill -U "$(id -u)" -x manicule || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -U "$(id -u)" -x manicule >/dev/null || break; sleep 0.5; done
        ! pgrep -U "$(id -u)" -x manicule >/dev/null || fail "Manicule didn't quit; quit it from its menu and re-run."
    fi

    target="$app_dir/Manicule.app"
    echo "→ installing Manicule $version to $target"
    [ -d "$app_dir" ] || in_dir "$(dirname "$app_dir")" mkdir -p "$app_dir"
    staged="$app_dir/.Manicule.app.new"
    in_dir "$app_dir" rm -rf "$staged"
    in_dir "$app_dir" ditto "$new" "$staged" || fail "couldn't copy Manicule into $app_dir."
    old="$app_dir/.Manicule.app.old"
    in_dir "$app_dir" rm -rf "$old"
    if [ -e "$target" ]; then
        "$lsregister" -u "$target" 2>/dev/null || true
        in_dir "$app_dir" mv "$target" "$old" \
            || fail "couldn't move the old $target aside. Allow your terminal in System Settings > Privacy & Security > App Management, or drag the old app to the Trash, then re-run."
    fi
    if ! in_dir "$app_dir" mv "$staged" "$target"; then
        [ ! -e "$old" ] || in_dir "$app_dir" mv "$old" "$target" || true
        fail "couldn't move Manicule into place at $target."
    fi
    in_dir "$app_dir" rm -rf "$old"
    # Registered so it is offered as a default browser; Manicule's Settings sets it as the default.
    "$lsregister" -f "$target" || fail "Launch Services couldn't register $target."

    open "$target" || fail "$target didn't launch."
    echo "✓ Manicule $version is in $target and running in the menu bar."
}

main "$@"
