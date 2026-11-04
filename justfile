version := `cat VERSION`
app := ".build/Manicule.app"
installed := "/Applications/Manicule.app"
lsregister := "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
info_plist := "Resources/Info.plist"
icns := "Resources/AppIcon.icns"

# `default` pipes `just --list` through a small stock-perl filter that clips long recipe
# docs to your terminal width (…) instead of wrapping. Self-contained — no external files;
# falls back to plain `just --list` where perl is absent. Edit the recipes below, not this.
# List available recipes
default:
    @if command -v perl >/dev/null 2>&1; then just --color always --list | perl -CS -Mutf8 -lpe 'BEGIN{($w)=`stty size 2>/dev/null </dev/tty`=~/ (\d+)/; $w||=100; $col=(-t STDOUT && !exists $ENV{NO_COLOR})} s/\e\[[0-9;]*m//g unless $col; (my $v=$_)=~s/\e\[[0-9;]*m//g; if(length($v)>$w){my($o,$n)=("",0); while(length && $n<$w-1){ if($col && s/^(\e\[[0-9;]*m)//){$o.=$1}else{s/^(.)//;$o.=$1;$n++} } $_=$o."…".($col?"\e[0m":"")}'; else just --list; fi

# Non-mutating pre-merge gate: lint the installer, then the unit tests
[group("check")]
gate: test
    shellcheck install.sh

# Run the unit tests
[group("check")]
test:
    swift test

# Build the release binary
[group("build")]
build:
    swift build -c release

# Assemble .build/Manicule.app (version from VERSION, Sparkle embedded; signed with APPLE_SIGNING_IDENTITY, else the keychain's Developer ID, else ad-hoc)
[group("build")]
bundle: build
    #!/usr/bin/env bash
    set -euo pipefail
    bin=$(swift build -c release --show-bin-path)
    rm -rf "{{app}}"
    mkdir -p "{{app}}/Contents/MacOS" "{{app}}/Contents/Resources" "{{app}}/Contents/Frameworks"
    cp "$bin/manicule" "{{app}}/Contents/MacOS/manicule"
    install_name_tool -add_rpath @executable_path/../Frameworks "{{app}}/Contents/MacOS/manicule"
    ditto "$bin/Sparkle.framework" "{{app}}/Contents/Frameworks/Sparkle.framework"
    cp "{{icns}}" "{{app}}/Contents/Resources/AppIcon.icns"
    plist="{{app}}/Contents/Info.plist"
    cp "{{info_plist}}" "$plist"
    plutil -replace CFBundleShortVersionString -string "{{version}}" "$plist"
    plutil -replace CFBundleVersion -string "{{version}}" "$plist"
    # Inside-out: each nested Sparkle helper before the framework, the framework before the app.
    # Unset APPLE_SIGNING_IDENTITY → this Mac's Developer ID when the keychain has one: its designated
    # requirement is bundle id + team, stable across builds, so privacy grants (folder access) survive
    # a rebuild. An ad-hoc signature's is the cdhash — every rebuild is a new app to TCC.
    identity=${APPLE_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Developer ID Application: /{print $2; exit}')}
    ts=--timestamp; [ -n "${APPLE_SIGNING_IDENTITY:-}" ] || ts=--timestamp=none
    if [ -n "$identity" ]; then
        sign=(codesign --force --options runtime "$ts" --sign "$identity")
    else
        sign=(codesign --force --sign -)
    fi
    sparkle="{{app}}/Contents/Frameworks/Sparkle.framework"
    "${sign[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
    "${sign[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
    "${sign[@]}" "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"
    "${sign[@]}" "{{app}}"

# Print the directory holding Sparkle's sign_update and generate_keys (resolving packages first)
[group("build")]
sparkle-bin:
    @swift package resolve >/dev/null
    @echo "{{justfile_directory()}}/.build/artifacts/sparkle/Sparkle/bin"

# Regenerate Resources/AppIcon.icns from Resources/AppIcon.svg (needs plate: github.com/lockyc/plate)
[group("build")]
icon:
    plate icon --icns "{{icns}}" Resources/AppIcon.svg

# Build and launch manicule
[group("app")]
run: bundle
    open -a "$PWD/{{app}}"

# Quit any running Manicule, install to /Applications/Manicule.app, register with Launch Services, and relaunch
[group("app")]
install: bundle quit
    #!/usr/bin/env bash
    set -euo pipefail
    # An install under the lowercase bundle name is unregistered and replaced, whatever the volume's case rules.
    for old in /Applications/manicule.app "{{installed}}"; do
        if [ -e "$old" ]; then
            "{{lsregister}}" -u "$old" 2>/dev/null || true
            rm -rf "$old"
        fi
    done
    cp -R "{{app}}" "{{installed}}"
    # the commit this build came from: lets a later release (lockstep.sh) tell whether it is newer before replacing it
    xattr -w com.lockyc.build-commit "$(git rev-parse HEAD)$(git status --porcelain | grep -q . && echo -dirty)" "{{installed}}"
    "{{lsregister}}" -f "{{installed}}"
    # `env -i`: a bare `open` hands the app this terminal's environment, which no Dock/Spotlight launch has.
    /usr/bin/env -i /usr/bin/open "{{installed}}"

# Quits any running Manicule (its process is `manicule`), force-killing one still alive after 3s.
[private]
quit:
    #!/usr/bin/env bash
    killall manicule 2>/dev/null || exit 0
    for _ in {1..30}; do pgrep -x manicule >/dev/null || exit 0; sleep 0.1; done
    killall -9 manicule 2>/dev/null
    while pgrep -x manicule >/dev/null; do sleep 0.1; done
