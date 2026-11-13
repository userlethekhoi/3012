# 3012 Theos Builder image — runs ONE untrusted build per container.
# Toolchain: Theos (master) + L1ghtmann iOS toolchain for Linux + ldid + latest iOS SDKs.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    THEOS=/opt/theos \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential fakeroot rsync curl perl zip unzip git libxml2 libtinfo5 \
      xz-utils zstd ca-certificates dpkg file \
 && rm -rf /var/lib/apt/lists/*

# Theos framework
RUN git clone --recursive --depth 1 --shallow-submodules https://github.com/theos/theos.git "$THEOS" \
 && git -C "$THEOS" rev-parse --short HEAD > /opt/theos-version.txt \
 && rm -rf "$THEOS/.git"

# iOS cross toolchain for Linux (clang/ld64 for arm64 + arm64e) and ldid
RUN mkdir -p "$THEOS/toolchain" \
 && curl -fsSL "https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-$(uname -m).tar.xz" \
    | tar -xJ -C "$THEOS/toolchain" \
 && curl -fsSL "https://github.com/ProcursusTeam/ldid/releases/latest/download/ldid_linux_$(uname -m)" \
    -o "$THEOS/toolchain/linux/iphone/bin/ldid" \
 && chmod +x "$THEOS/toolchain/linux/iphone/bin/ldid"

# iOS SDKs (keep the two newest to save space)
RUN mkdir -p "$THEOS/sdks" /tmp/sdks \
 && curl -fsSL https://github.com/theos/sdks/archive/refs/heads/master.tar.gz \
    | tar -xz --strip-components=1 -C /tmp/sdks \
 && for sdk in $(ls -d /tmp/sdks/iPhoneOS*.sdk | sort -V | tail -n 2); do mv "$sdk" "$THEOS/sdks/"; done \
 && rm -rf /tmp/sdks \
 && ls "$THEOS/sdks"

RUN useradd --uid 1000 --create-home --shell /bin/bash builder \
 && chmod -R a+rX "$THEOS"

COPY entrypoint.sh /usr/local/bin/3012-build
RUN chmod 755 /usr/local/bin/3012-build

USER 1000:1000
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/3012-build"]
