#!/usr/bin/env bash
# 3012 Theos Build Server — one-command installer for Ubuntu 22.04 / 24.04 (x86_64).
#
#   curl -fsSL https://raw.githubusercontent.com/userlethekhoi/3012/main/BuildServer/install.sh | sudo bash
#
# What it does (and nothing else):
#   * installs git/python3 (and Docker only if missing) — existing containers/configs are untouched
#   * creates an unprivileged system user `b3012`
#   * builds the isolated Theos builder image
#   * runs the API on 127.0.0.1:8787 via systemd (no public port is opened)
#   * optionally installs cloudflared and connects your Cloudflare Tunnel (asks for the token)
set -euo pipefail

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

say "1/6 Cài gói cần thiết (git, python3, curl)..."
apt-get update -qq
apt-get install -y -qq git python3 curl ca-certificates >/dev/null

if ! command -v docker >/dev/null 2>&1; then
    say "Docker chưa có — đang cài Docker Engine..."
    curl -fsSL https://get.docker.com | sh
fi
systemctl is-active --quiet docker || systemctl start docker

say "2/6 Tải mã nguồn build server vào $INSTALL_DIR ..."
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

say "3/6 Tạo user hệ thống '$SVC_USER' (không có shell, không có quyền root)..."
if ! id "$SVC_USER" >/dev/null 2>&1; then
    useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin "$SVC_USER"
fi
usermod -aG docker "$SVC_USER"
mkdir -p "$DATA_DIR/artifacts" "$DATA_DIR/.docker"
chown -R "$SVC_USER:$SVC_USER" "$DATA_DIR"
chmod 700 "$DATA_DIR"

say "4/6 Build Docker image Theos (lần đầu khoảng 5-10 phút)..."
docker build --pull -q -t "$IMAGE" "$INSTALL_DIR/src/BuildServer/image" >/dev/null
docker image prune -f >/dev/null 2>&1 || true

say "5/6 Cấu hình dịch vụ systemd..."
if [ ! -f "$ENV_FILE" ]; then
    install -m 644 "$INSTALL_DIR/src/BuildServer/config/3012-build.env.example" "$ENV_FILE"
fi
install -m 644 "$INSTALL_DIR/src/BuildServer/systemd/3012-build.service" "/etc/systemd/system/$SERVICE.service"
systemctl daemon-reload
systemctl enable -q "$SERVICE"
systemctl restart "$SERVICE"

for _ in $(seq 1 15); do
    if curl -fsS http://127.0.0.1:8787/v1/health >/dev/null 2>&1; then break; fi
    sleep 1
done
curl -fsS http://127.0.0.1:8787/v1/health >/dev/null 2>&1 \
    || die "Build server chưa chạy. Xem log: journalctl -u $SERVICE -n 50"
say "Build server đang chạy tại 127.0.0.1:8787 (chỉ nội bộ, không mở port ra Internet)."

say "6/6 Cloudflare Tunnel..."
if ! command -v cloudflared >/dev/null 2>&1; then
    curl -fsSL -o /tmp/cloudflared.deb \
        https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i /tmp/cloudflared.deb >/dev/null
    rm -f /tmp/cloudflared.deb
fi

if systemctl is-active --quiet cloudflared 2>/dev/null; then
    say "cloudflared đã chạy sẵn — giữ nguyên cấu hình hiện tại."
else
    TOKEN="${CF_TUNNEL_TOKEN:-}"
    if [ -z "$TOKEN" ] && [ -r /dev/tty ]; then
        printf '\033[1;36m[3012]\033[0m Dán Cloudflare Tunnel Token (ký tự sẽ được ẩn, Enter để bỏ qua): ' > /dev/tty
        read -rs TOKEN < /dev/tty || true
        printf '\n' > /dev/tty
    fi
    if [ -n "$TOKEN" ]; then
        cloudflared service install "$TOKEN" >/dev/null 2>&1 || die "Không cài được tunnel — kiểm tra lại token."
        unset TOKEN
        say "Đã kết nối Cloudflare Tunnel."
    else
        warn "Bỏ qua tunnel. Chạy lại script này khi đã có token."
    fi
fi

cat <<EOF

────────────────────────────────────────────────────────────
 3012 Build Server đã cài xong.

 Việc cuối cùng trên Cloudflare (Zero Trust > Networks > Tunnels
 > 3012-build > Public Hostname > Add):
     Subdomain/Domain : build.<tên-miền-của-bạn>
     Service          : HTTP   localhost:8787

 Kiểm tra từ máy bất kỳ:
     curl https://build.<tên-miền-của-bạn>/v1/health

 Quản lý:
     Trạng thái : systemctl status $SERVICE
     Log        : journalctl -u $SERVICE -f
     Cấu hình   : $ENV_FILE  (sửa xong: systemctl restart $SERVICE)
     Cập nhật   : chạy lại lệnh cài đặt
────────────────────────────────────────────────────────────
EOF
