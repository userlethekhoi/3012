#!/usr/bin/env bash
# 3012 Theos Build & Sync Relay Server — one-command installer / fast updater for Ubuntu 22.04 / 24.04 (x86_64).
#
#   curl -fsSL https://raw.githubusercontent.com/userlethekhoi/3012/main/BuildServer/install.sh | sudo bash
#
# Flags / Env:
#   --rebuild-image / FORCE_REBUILD=1 : rebuild 3012-theos-builder Docker image from scratch
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

REBUILD_IMAGE="${FORCE_REBUILD:-0}"
for arg in "$@"; do
    case "$arg" in
        --rebuild-image) REBUILD_IMAGE=1 ;;
    esac
done

REPO_URL="${REPO_URL:-https://github.com/userlethekhoi/3012.git}"
BRANCH="${BRANCH:-main}"
INSTALL_DIR=/opt/3012-build
DATA_DIR=/var/lib/3012-build
ENV_FILE=/etc/3012-build.env
SERVICE=3012-build
SVC_USER=b3012
IMAGE=3012-theos-builder:latest

say()  { printf '\033[1;32m[3012]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[3012]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[3012] %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Hãy chạy bằng quyền root (sudo)."
[ "$(uname -m)" = "x86_64" ] || die "Hiện chỉ hỗ trợ VPS x86_64."
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || die "Hiện chỉ hỗ trợ Ubuntu 22.04 / 24.04."

say "1/6 Kiểm tra gói cần thiết (git, python3, curl)..."
if ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    apt-get update -qq
    NEEDRESTART_MODE=a DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::="--force-confold" git python3 curl ca-certificates </dev/null >/dev/null
fi

if ! command -v docker >/dev/null 2>&1; then
    say "Docker chưa có — đang cài Docker Engine..."
    curl -fsSL https://get.docker.com | sh
fi
systemctl is-active --quiet docker || systemctl start docker

say "2/6 Tải mã nguồn build & sync server vào $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
if [ -d "$INSTALL_DIR/src/.git" ]; then
    git -C "$INSTALL_DIR/src" fetch -q --depth 1 origin "$BRANCH"
    git -C "$INSTALL_DIR/src" reset -q --hard FETCH_HEAD
else
    rm -rf "$INSTALL_DIR/src"
    git clone -q --depth 1 --branch "$BRANCH" --filter=blob:none --sparse "$REPO_URL" "$INSTALL_DIR/src"
    git -C "$INSTALL_DIR/src" sparse-checkout set BuildServer
fi
chmod -R a+rX "$INSTALL_DIR"

say "3/6 Kiểm tra user hệ thống '$SVC_USER'..."
if ! id "$SVC_USER" >/dev/null 2>&1; then
    useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin "$SVC_USER"
fi
usermod -aG docker "$SVC_USER"
mkdir -p "$DATA_DIR/artifacts" "$DATA_DIR/queue" "$DATA_DIR/cas" "$DATA_DIR/cas/tmp" "$DATA_DIR/workspaces" "$DATA_DIR/stages" "$DATA_DIR/.docker"
chown -R "$SVC_USER:$SVC_USER" "$DATA_DIR"
chmod 700 "$DATA_DIR"

if [ "$REBUILD_IMAGE" = "1" ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    say "4/6 Build Docker image Theos (lần đầu khoảng 5-10 phút)..."
    docker build --pull -t "$IMAGE" "$INSTALL_DIR/src/BuildServer/image"
    docker image prune -f >/dev/null 2>&1 || true
else
    say "4/6 Docker image $IMAGE đã có sẵn — cập nhật nhanh entrypoint.sh (<2 giây)..."
    docker build -q -t "$IMAGE" -f - "$INSTALL_DIR/src/BuildServer/image" <<EOF >/dev/null
FROM $IMAGE
USER root
COPY entrypoint.sh /usr/local/bin/3012-build
RUN chmod 755 /usr/local/bin/3012-build
USER 1000:1000
EOF
fi

say "5/6 Cấu hình và khởi động lại dịch vụ systemd..."
if [ ! -f "$ENV_FILE" ]; then
    install -m 644 "$INSTALL_DIR/src/BuildServer/config/3012-build.env.example" "$ENV_FILE"
else
    sed -i -E \
        -e 's/^BUILD_RATE_PER_DEVICE_HOUR=(20|60)[[:space:]]*$/BUILD_RATE_PER_DEVICE_HOUR=0/' \
        -e 's/^BUILD_RATE_PER_IP_HOUR=(40|120)[[:space:]]*$/BUILD_RATE_PER_IP_HOUR=0/' \
        "$ENV_FILE"
    while IFS='=' read -r k v; do
        [[ "$k" =~ ^[A-Z0-9_]+$ ]] || continue
        if ! grep -qE "^${k}=" "$ENV_FILE" 2>/dev/null; then
            printf '%s=%s\n' "$k" "$v" >> "$ENV_FILE"
        fi
    done < "$INSTALL_DIR/src/BuildServer/config/3012-build.env.example"
fi
BUILD_PORT=$(grep -E '^BUILD_PORT=' "$ENV_FILE" | tail -n 1 | cut -d= -f2 | tr -dc '0-9' || true)
BUILD_PORT="${BUILD_PORT:-8787}"

install -m 644 "$INSTALL_DIR/src/BuildServer/systemd/3012-build.service" "/etc/systemd/system/$SERVICE.service"
systemctl daemon-reload
systemctl enable -q "$SERVICE"
systemctl restart "$SERVICE"

for _ in $(seq 1 15); do
    if curl -fsS "http://127.0.0.1:${BUILD_PORT}/v1/health" >/dev/null 2>&1; then break; fi
    sleep 1
done
curl -fsS "http://127.0.0.1:${BUILD_PORT}/v1/health" >/dev/null 2>&1 \
    || die "Build server chưa chạy trên cổng ${BUILD_PORT}. Xem log: journalctl -u $SERVICE -n 50"
say "Build & Sync Relay Server đang chạy tại 127.0.0.1:${BUILD_PORT} (chỉ nội bộ)."

say "6/6 Cloudflare Tunnel..."
if ! command -v cloudflared >/dev/null 2>&1; then
    TMP_DEB_DIR="$(mktemp -d)"
    chmod 700 "$TMP_DEB_DIR"
    curl -fsSL -o "$TMP_DEB_DIR/cloudflared.deb" \
        https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i "$TMP_DEB_DIR/cloudflared.deb" >/dev/null
    rm -rf "$TMP_DEB_DIR"
fi

if systemctl is-active --quiet cloudflared 2>/dev/null; then
    say "cloudflared đã chạy sẵn — giữ nguyên cấu hình hiện tại."
else
    TOKEN="${CF_TUNNEL_TOKEN:-}"
    if [ -z "$TOKEN" ] && [ -r /dev/tty ]; then
        printf '\033[1;36m[3012]\033[0m Dán Cloudflare Tunnel Token hoặc cả câu lệnh install (ký tự sẽ được ẩn, Enter để bỏ qua): ' > /dev/tty
        read -rs TOKEN < /dev/tty || true
        printf '\n' > /dev/tty
    fi
    if printf '%s' "$TOKEN" | grep -qE 'eyJ[A-Za-z0-9_.=-]+'; then
        TOKEN="$(printf '%s' "$TOKEN" | grep -oE 'eyJ[A-Za-z0-9_.=-]+' | head -n 1)"
    fi
    if [ -n "$TOKEN" ]; then
        cloudflared service uninstall >/dev/null 2>&1 || true
        cloudflared service install "$TOKEN" >/dev/null 2>&1 || die "Không cài được tunnel — kiểm tra lại token."
        unset TOKEN
        say "Đã kết nối Cloudflare Tunnel."
    else
        warn "Bỏ qua tunnel. Chạy lại script này khi đã có token."
    fi
fi

cat <<EOF

────────────────────────────────────────────────────────────
 3012 Build & Sync Relay Server đã sẵn sàng!

 Cloudflare Public Hostname -> Service: HTTP localhost:${BUILD_PORT}

 Các Endpoint đang hoạt động:
   - Health check   : https://build.<domain>/v1/health
   - Theos Compiler : POST https://build.<domain>/v1/builds
   - PC Sync Relay  : wss://build.<domain>/v1/sync  (Zero-Knowledge AES-256-GCM)
   - PC Script 1-line: https://build.<domain>/sync.mjs

 Quản lý nhanh:
   - Trạng thái : systemctl status $SERVICE
   - Log        : journalctl -u $SERVICE -f
   - Rebuild Docker (khi cần cập nhật SDK mới):
       curl -fsSL https://raw.githubusercontent.com/userlethekhoi/3012/main/BuildServer/install.sh | sudo bash -s -- --rebuild-image
────────────────────────────────────────────────────────────
EOF
