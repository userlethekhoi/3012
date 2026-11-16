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

args=("-j${jobs_n}" package FINALPACKAGE=1)
case "${PACKAGE_SCHEME:-rootless}" in
    rootless) args+=(THEOS_PACKAGE_SCHEME=rootless) ;;
    roothide) args+=(THEOS_PACKAGE_SCHEME=roothide) ;;
    *) ;;
esac

if [ "${BUILD_MODE:-zip}" = "incremental" ] && [ "${CLEAN_BUILD:-0}" != "1" ]; then
    rm -f /tmp/make.log
    make "${args[@]}" 2>&1 | tee /tmp/make.log >&2
    code=${PIPESTATUS[0]}
    if [ "$code" -ne 0 ] && grep -qE "No rule to make target|missing separator" /tmp/make.log 2>/dev/null && grep -q "\.theos/" /tmp/make.log 2>/dev/null; then
        say "Phát hiện cache .theos lệch đường dẫn header cũ — tự động làm mới cache và build lại..."
        rm -rf .theos packages
        make "${args[@]}"
        code=$?
    fi
    rm -f /tmp/make.log
else
    make "${args[@]}"
    code=$?
fi

if [ -d packages ]; then
    find packages -maxdepth 1 -type f -name '*.deb' -exec cp {} /work/out/ \;
fi
if [ -d .theos/obj ]; then
    for objdir in .theos/obj .theos/obj/rootless .theos/obj/roothide .theos/obj/arm64 .theos/obj/arm64e; do
        if [ -d "$objdir" ]; then
            find "$objdir" -maxdepth 1 -type f -name '*.dylib' -exec cp -f {} /work/out/ \;
        fi
    done
    for dbgdir in .theos/obj/debug .theos/obj/rootless/debug .theos/obj/roothide/debug; do
        if [ -d "$dbgdir" ]; then
            find "$dbgdir" -maxdepth 1 -type f -name '*.dylib' -exec cp -n {} /work/out/ \;
        fi
    done
fi

tar -C /work/out -cf - . >&3
exit "$code"
