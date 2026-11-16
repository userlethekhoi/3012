#!/bin/bash
# 3012 Theos build entrypoint.
# Supports two modes:
#   BUILD_MODE=zip         : reads .zip from stdin into ephemeral /work/src
#   BUILD_MODE=incremental : uses pre-synced /work/src & persistent .theos cache
# Outputs:
#   stderr : human-readable build log (streamed to the app)
#   stdout : tar archive containing only the resulting .deb / .dylib files
set -uo pipefail

exec 3>&1 1>&2

export HOME=/work/home
export USER="${USER:-builder}"
export LOGNAME="${LOGNAME:-$USER}"
export THEOS=/opt/theos
export THEOS_MAKE_PATH="$THEOS/makefiles"
export GO_EASY_ON_ME=1
export PATH="$THEOS/bin:$PATH"
mkdir -p "$HOME" /work/src /work/out

say() { printf '[3012] %s\n' "$*"; }

if [ "${BUILD_MODE:-zip}" = "incremental" ]; then
    rm -rf /work/out/* 2>/dev/null || true
else
    cat > /work/project.zip
    if ! unzip -qq -o /work/project.zip -d /work/src -x '__MACOSX/*' '*/.DS_Store' '.DS_Store' 2>/dev/null; then
        say "Không giải nén được project (.zip bị lỗi)."
        exit 2
    fi
    rm -f /work/project.zip
fi

project_dir=$(find /work/src -maxdepth 4 -type f \( -iname Makefile -o -iname GNUmakefile \) ! -path '*/.theos/*' -printf '%d\t%h\n' 2>/dev/null | sort -n | head -n 1 | cut -f2-)
if [ -z "$project_dir" ]; then
    say "Không tìm thấy Makefile của Theos trong project."
    exit 2
fi

cd "$project_dir" || exit 2
rm -rf packages

if [ "${BUILD_MODE:-zip}" != "incremental" ] || [ "${CLEAN_BUILD:-0}" = "1" ]; then
    rm -rf .theos
fi

# Locate active Makefile and normalize non-destructively (preserving mtime unless broken)
mf_file=""
if [ -f GNUmakefile ]; then
    mf_file="GNUmakefile"
elif [ -f Makefile ]; then
    mf_file="Makefile"
else
    mf_file=$(find . -maxdepth 1 -type f \( -iname Makefile -o -iname GNUmakefile \) | head -n 1)
fi

strip_cr_if_needed() {
    local f="$1"
    if [ -n "$f" ] && [ -f "$f" ] && grep -q $'\r' "$f" 2>/dev/null; then
        sed -i 's/\r$//' "$f"
    fi
}

normalize_makefile_if_needed() {
    local mkf="$1"
    [ -n "$mkf" ] && [ -f "$mkf" ] || return 0
    strip_cr_if_needed "$mkf"
    if grep -qE '^[[:space:]]*[-s]?include[[:space:]]+[^$#[:space:]][^#[:space:]]*/makefiles/|^[[:space:]]*override[[:space:]]+(export[[:space:]]+)?THEOS(_MAKE_PATH)?[[:space:]:+?]*=' "$mkf" 2>/dev/null; then
        sed -i -E \
            -e 's#^([[:space:]]*[-s]?include[[:space:]]+)[^$#[:space:]][^#[:space:]]*/makefiles/#\1$(THEOS)/makefiles/#' \
            -e 's#^([[:space:]]*)override[[:space:]]+((export[[:space:]]+)?THEOS(_MAKE_PATH)?[[:space:]:+?]*=)#\1\2#' \
            "$mkf"
    fi
}

normalize_makefile_if_needed "$mf_file"
while IFS= read -r -d '' mkf; do
    normalize_makefile_if_needed "$mkf"
done < <(find . -maxdepth 3 -type f \( -iname Makefile -o -iname GNUmakefile -o -name '*.mk' \) ! -path '*/.theos/*' -print0 2>/dev/null)
for cf in control layout/DEBIAN/control layout/DEBIAN/preinst layout/DEBIAN/postinst layout/DEBIAN/prerm layout/DEBIAN/postrm; do
    strip_cr_if_needed "$cf"
done
for cf in control layout/DEBIAN/control; do
    if [ -f "$cf" ] && [ -s "$cf" ] && [ "$(tail -c 1 "$cf" | wc -l)" -eq 0 ]; then
        printf '\n' >> "$cf"
    fi
done

scheme="${PACKAGE_SCHEME:-rootless}"
min_ios="15.0"
if [ "$scheme" = "rootful" ]; then
    min_ios="14.0"
fi

if [ -n "$mf_file" ] && [ -f "$mf_file" ]; then
    if ! grep -v '^[[:space:]]*#' "$mf_file" | grep -qE '^[[:space:]]*(export[[:space:]]+|override[[:space:]]+)?TARGET[[:space:]:+?]*='; then
        export TARGET="iphone:clang:latest:${min_ios}"
        say "Makefile chưa khai báo TARGET — tự động dùng TARGET=$TARGET"
    fi
fi

auto_control=0
if [ ! -f control ] && [ ! -f layout/DEBIAN/control ]; then
    tweak_name=""
    if [ -n "$mf_file" ] && [ -f "$mf_file" ]; then
        tweak_name=$(grep -E '^[[:space:]]*(TWEAK_NAME|LIBRARY_NAME|APPLICATION_NAME|TOOL_NAME)[[:space:]:+?]*=' "$mf_file" 2>/dev/null | head -n 1 | cut -d= -f2- | sed 's/#.*//' | awk '{print $1}' || true)
    fi
    tweak_name="${tweak_name:-Tweak3012}"
    safe_display=$(printf '%s' "$tweak_name" | tr -cd 'A-Za-z0-9._+-')
    safe_display="${safe_display:-Tweak3012}"
    pkg_slug=$(printf '%s' "$safe_display" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-' | sed 's/^[^a-z0-9]*//; s/[^a-z0-9]*$//')
    pkg_slug="${pkg_slug:-tweak3012}"
    cat > control <<EOF
Package: com.app3012.auto.${pkg_slug}
Name: ${safe_display}
Version: 1.0.0
Architecture: iphoneos-arm
Description: Built with 3012 Build Server
Maintainer: 3012
Author: 3012
Section: Tweaks
Depends: mobilesubstrate
EOF
    auto_control=1
    say "Dự án chưa có file control — tự động tạo cấu hình đóng gói mặc định (${safe_display})."
fi

auto_plist=0
if [ -n "$mf_file" ] && [ -f "$mf_file" ] && grep -q 'tweak\.mk' "$mf_file" 2>/dev/null; then
    inst_name=$(grep -E '^[[:space:]]*TWEAK_NAME[[:space:]:+?]*=' "$mf_file" 2>/dev/null | head -n 1 | cut -d= -f2- | sed 's/#.*//' | awk '{print $1}' || true)
    if [ ! -f Filter.plist ] && { [ -z "$inst_name" ] || [ ! -f "${inst_name}.plist" ]; }; then
        cat > Filter.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Filter</key>
	<dict>
		<key>Bundles</key>
		<array>
			<string>com.apple.UIKit</string>
		</array>
	</dict>
</dict>
</plist>
EOF
        auto_plist=1
        say "Dự án chưa có file .plist bộ lọc — tự động tạo Filter.plist mặc định."
    fi
fi

proj_rel="${project_dir#/work/src}"
proj_rel="${proj_rel#/}"
[ -z "$proj_rel" ] && proj_rel="."

say "Theos $(cat /opt/theos-version.txt 2>/dev/null) • SDK: $(ls "$THEOS/sdks" | tr '\n' ' ')"
say "Project: $proj_rel"

jobs_n="${MAKE_JOBS:-2}"
case "$jobs_n" in
    1|2|3|4) ;;
    *) jobs_n=2 ;;
esac

args=("-j${jobs_n}" package FINALPACKAGE=1 "THEOS=$THEOS" "THEOS_MAKE_PATH=$THEOS/makefiles" COLOR=0)
case "$scheme" in
    rootless) args+=(THEOS_PACKAGE_SCHEME=rootless) ;;
    roothide) args+=(THEOS_PACKAGE_SCHEME=roothide) ;;
    *) ;;
esac

run_make_clean_log() {
    rm -f /tmp/make.log
    make "$@" 2>&1 | sed -u -E 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tee /tmp/make.log >&2
    code=${PIPESTATUS[0]}
}

run_make_clean_log "${args[@]}"

if [ "$code" -ne 0 ] && [ "${BUILD_MODE:-zip}" = "incremental" ] && [ "${CLEAN_BUILD:-0}" != "1" ]; then
    if grep -qE "No rule to make target|missing separator" /tmp/make.log 2>/dev/null && grep -q "\.theos/" /tmp/make.log 2>/dev/null; then
        say "Phát hiện cache .theos lệch đường dẫn header cũ — tự động làm mới cache và build lại..."
        rm -rf .theos packages
        run_make_clean_log "${args[@]}"
    fi
fi

if [ "$code" -ne 0 ] && grep -qiE "You do not have an SDK|SDK .* does not exist|Could not find .*SDK|no .*\.sdk found" /tmp/make.log 2>/dev/null; then
    say "SDK khai báo trong Makefile không có trên máy chủ — tự động chuyển sang iOS SDK mới nhất..."
    rm -rf .theos packages
    run_make_clean_log "${args[@]}" "TARGET=iphone:clang:latest:${min_ios}" SDKVERSION=latest
fi

rm -f /tmp/make.log
if [ "$auto_control" = "1" ]; then
    rm -f control
fi
if [ "$auto_plist" = "1" ]; then
    rm -f Filter.plist
fi

if [ -d packages ]; then
    find packages -maxdepth 1 -type f -name '*.deb' -exec cp {} /work/out/ \;
fi
if [ -d .theos/obj ]; then
    for objdir in .theos/obj .theos/obj/rootless .theos/obj/roothide; do
        if [ -d "$objdir" ]; then
            find "$objdir" -maxdepth 1 -type f -name '*.dylib' -exec cp -f {} /work/out/ \;
        fi
    done
    for fallbackdir in .theos/obj/debug .theos/obj/rootless/debug .theos/obj/roothide/debug \
                       .theos/obj/arm64 .theos/obj/arm64e .theos/obj/rootless/arm64 \
                       .theos/obj/rootless/arm64e .theos/obj/roothide/arm64 .theos/obj/roothide/arm64e; do
        if [ -d "$fallbackdir" ]; then
            find "$fallbackdir" -maxdepth 1 -type f -name '*.dylib' -exec cp -n {} /work/out/ \;
        fi
    done
fi

tar -C /work/out -cf - . >&3
exit "$code"
