#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

APP_USER="server-monitor"
APP_GROUP="server-monitor"
INSTALL_DIR="/opt/server-monitor-agent"
CONFIG_DIR="/etc/server-monitor-agent"
LOG_DIR="/var/log/server-monitor-agent"
BIN_PATH="/usr/local/bin/server-monitor"
SERVICE_PATH="/etc/systemd/system/server-monitor.service"

apt-get update
apt-get install -y ca-certificates curl tar

id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
getent group "$APP_GROUP" >/dev/null 2>&1 || groupadd --system "$APP_GROUP"
usermod -a -G "$APP_GROUP" "$APP_USER"

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"
cp -r cmd internal go.mod go.sum "$INSTALL_DIR" || true
if [[ -f ./server-monitor ]]; then
  install -m 0755 ./server-monitor "$BIN_PATH"
else
  echo "Building binary..."
  if ! command -v go >/dev/null 2>&1; then
    echo "Go compiler not found. Install Go 1.22+ first."
    exit 1
  fi
  go build -o "$BIN_PATH" ./cmd/monitor
fi

install -m 0640 configs/config.yaml "$CONFIG_DIR/config.yaml"
install -m 0644 systemd/server-monitor.service "$SERVICE_PATH"
chown -R "$APP_USER":"$APP_GROUP" "$LOG_DIR" "$CONFIG_DIR"

systemctl daemon-reload
systemctl enable server-monitor.service
systemctl restart server-monitor.service

echo "Installed successfully"
