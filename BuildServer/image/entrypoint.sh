#!/bin/bash
# 3012 Theos build entrypoint.
# Runs as uid 1000 inside a read-only, network-less container.
#   stdin  : zipped Theos project
#   stderr : human-readable build log (streamed to the app)
#   stdout : tar archive containing only the resulting .deb / .dylib files
set -uo pipefail

exec 3>&1 1>&2

export HOME=/work/home
export THEOS=/opt/theos
export PATH="$THEOS/bin:$PATH"
mkdir -p "$HOME" /work/src /work/out

say() { printf '[3012] %s\n' "$*"; }

cat > /work/project.zip
if ! unzip -qq -o /work/project.zip -d /work/src -x '__MACOSX/*' '*/.DS_Store' '.DS_Store' 2>/dev/null; then
    say "Không giải nén được project (.zip bị lỗi)."
    exit 2
fi
rm -f /work/project.zip

project_dir=$(find /work/src -maxdepth 4 -type f -name Makefile -printf '%d\t%h\n' 2>/dev/null | sort -n | head -n 1 | cut -f2-)
if [ -z "$project_dir" ]; then
    say "Không tìm thấy Makefile của Theos trong project."
    exit 2
fi

cd "$project_dir" || exit 2
rm -rf .theos packages

say "Theos $(cat /opt/theos-version.txt 2>/dev/null) • SDK: $(ls "$THEOS/sdks" | tr '\n' ' ')"
say "Project: ${project_dir#/work/src/}"

args=(-j2 package FINALPACKAGE=1)
case "${PACKAGE_SCHEME:-rootless}" in
    rootless) args+=(THEOS_PACKAGE_SCHEME=rootless) ;;
    roothide) args+=(THEOS_PACKAGE_SCHEME=roothide) ;;
    *) ;;
esac

make "${args[@]}"
code=$?

if [ -d packages ]; then
    find packages -maxdepth 1 -type f -name '*.deb' -exec cp {} /work/out/ \;
fi
if [ -d .theos/obj ]; then
    find .theos/obj -maxdepth 1 -type f -name '*.dylib' -exec cp {} /work/out/ \;
    if [ -d .theos/obj/debug ]; then
        find .theos/obj/debug -maxdepth 1 -type f -name '*.dylib' -exec cp -n {} /work/out/ \;
    fi
fi

tar -C /work/out -cf - . >&3
exit "$code"
