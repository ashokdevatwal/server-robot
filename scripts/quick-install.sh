#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="ashokdevatwal"
REPO_NAME="server-robot"
RELEASE_TAG="${RELEASE_TAG:-latest}"

APP_USER="server-monitor"
APP_GROUP="server-monitor"
CONFIG_DIR="/etc/server-monitor-agent"
LOG_DIR="/var/log/server-monitor-agent"
BIN_PATH="/usr/local/bin/server-monitor"
SERVICE_PATH="/etc/systemd/system/server-monitor.service"
CONFIG_PATH="$CONFIG_DIR/config.yaml"

NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
BINARY_URL="${BINARY_URL:-${DOWNLOAD_URL:-}}"

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      echo "unsupported"
      ;;
  esac
}

usage() {
  cat <<'USAGE'
Usage: sudo ./quick-install.sh [options]

Options:
  --non-interactive      Do not prompt. Use env vars/defaults.
  --binary-url URL       Direct URL to binary or tar.gz asset.
  --release-tag TAG      GitHub release tag (default: latest).
  -h, --help             Show this help.

Environment variables:
  NON_INTERACTIVE=true
  BINARY_URL=https://github.com/<owner>/<repo>/releases/download/<tag>/server-monitor-linux-amd64.tar.gz
  RELEASE_TAG=v0.1.0
  MONITOR_INTERVAL=30s
  CPU_THRESHOLD=85
  RAM_THRESHOLD=85
  DISK_THRESHOLD=90
  NETWORK_RX_MBPS=1000
  NETWORK_TX_MBPS=1000
  EMAIL_ENABLED=true
  SMTP_HOST=email-smtp.us-east-2.amazonaws.com
  SMTP_PORT=587
  SMTP_USERNAME=...
  SMTP_PASSWORD=...
  EMAIL_FROM=admin@example.com
  EMAIL_TO=ops@example.com
  RETENTION_DAYS=30
  SUSTAIN_DURATION=1m
  COOLDOWN=15m
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive)
      NON_INTERACTIVE="true"
      ;;
    --binary-url)
      shift
      BINARY_URL="${1:-}"
      [[ -n "$BINARY_URL" ]] || { echo "--binary-url requires a value"; exit 1; }
      ;;
    --release-tag)
      shift
      RELEASE_TAG="${1:-}"
      [[ -n "$RELEASE_TAG" ]] || { echo "--release-tag requires a value"; exit 1; }
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

is_interactive() {
  [[ "$NON_INTERACTIVE" != "true" && -t 0 && -t 1 ]]
}

prompt_value() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="$3"
  local is_secret="${4:-false}"
  local input=""

  if is_interactive; then
    if [[ "$is_secret" == "true" ]]; then
      read -r -s -p "$prompt_text [hidden]: " input
      echo
    else
      read -r -p "$prompt_text [$default_value]: " input
    fi
    if [[ -z "$input" ]]; then
      printf -v "$var_name" '%s' "$default_value"
    else
      printf -v "$var_name" '%s' "$input"
    fi
  else
    printf -v "$var_name" '%s' "$default_value"
  fi
}

resolve_binary_url() {
  local arch
  arch="$(detect_arch)"
  if [[ "$arch" == "unsupported" ]]; then
    echo "Unsupported architecture: $(uname -m)"
    echo "Set BINARY_URL explicitly."
    exit 1
  fi

  if [[ -n "$BINARY_URL" ]]; then
    return
  fi

  local api_url
  if [[ "$RELEASE_TAG" == "latest" ]]; then
    api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
  else
    api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${RELEASE_TAG}"
  fi

  echo "Resolving release asset from GitHub..."
  local json
  json="$(curl -fsSL "$api_url")"

  BINARY_URL="$(printf '%s' "$json" | grep -Eo 'https://[^" ]+' | grep '/releases/download/' | grep 'server-monitor' | grep 'linux' | grep "$arch" | head -n 1 || true)"

  if [[ -z "$BINARY_URL" ]]; then
    echo "Could not auto-detect binary asset URL from release metadata."
    echo "Provide --binary-url or BINARY_URL explicitly."
    exit 1
  fi
}

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ca-certificates curl tar
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl tar
    return
  fi
  if command -v yum >/dev/null 2>&1; then
    yum install -y ca-certificates curl tar
    return
  fi
  if command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install ca-certificates curl tar
    return
  fi
  echo "No supported package manager found (apt/dnf/yum/zypper)."
  echo "Install dependencies manually: ca-certificates curl tar"
  exit 1
}

install_binary() {
  local tmp_file
  local tmp_dir
  tmp_file="$(mktemp)"
  echo "Downloading agent binary..."
  curl -fsSL "$BINARY_URL" -o "$tmp_file"

  if tar -tzf "$tmp_file" >/dev/null 2>&1; then
    tmp_dir="$(mktemp -d)"
    tar -xzf "$tmp_file" -C "$tmp_dir"
    local found_bin
    found_bin="$(find "$tmp_dir" -type f -name 'server-monitor*' | grep -v '\.service$' | head -n 1 || true)"
    if [[ -z "$found_bin" ]]; then
      echo "Downloaded archive does not contain a server-monitor binary"
      exit 1
    fi
    install -m 0755 "$found_bin" "$BIN_PATH"
    rm -rf "$tmp_dir"
  else
    install -m 0755 "$tmp_file" "$BIN_PATH"
  fi

  rm -f "$tmp_file"
}

configure_agent() {
  MONITOR_INTERVAL="${MONITOR_INTERVAL:-30s}"
  CPU_THRESHOLD="${CPU_THRESHOLD:-85}"
  RAM_THRESHOLD="${RAM_THRESHOLD:-85}"
  DISK_THRESHOLD="${DISK_THRESHOLD:-90}"
  NETWORK_RX_MBPS="${NETWORK_RX_MBPS:-1000}"
  NETWORK_TX_MBPS="${NETWORK_TX_MBPS:-1000}"
  EMAIL_ENABLED="${EMAIL_ENABLED:-true}"
  SMTP_HOST="${SMTP_HOST:-email-smtp.us-east-2.amazonaws.com}"
  SMTP_PORT="${SMTP_PORT:-587}"
  SMTP_USERNAME="${SMTP_USERNAME:-}"
  SMTP_PASSWORD="${SMTP_PASSWORD:-}"
  EMAIL_FROM="${EMAIL_FROM:-admin@example.com}"
  EMAIL_TO="${EMAIL_TO:-ops@example.com}"
  RETENTION_DAYS="${RETENTION_DAYS:-30}"
  SUSTAIN_DURATION="${SUSTAIN_DURATION:-1m}"
  COOLDOWN="${COOLDOWN:-15m}"

  if is_interactive; then
    echo
    echo "Server Monitor configuration"
    echo "Press Enter to keep defaults."
    prompt_value MONITOR_INTERVAL "Monitor interval" "$MONITOR_INTERVAL"
    prompt_value CPU_THRESHOLD "CPU threshold (%)" "$CPU_THRESHOLD"
    prompt_value RAM_THRESHOLD "RAM threshold (%)" "$RAM_THRESHOLD"
    prompt_value DISK_THRESHOLD "Disk threshold (%)" "$DISK_THRESHOLD"
    prompt_value NETWORK_RX_MBPS "Network RX threshold (Mbps)" "$NETWORK_RX_MBPS"
    prompt_value NETWORK_TX_MBPS "Network TX threshold (Mbps)" "$NETWORK_TX_MBPS"
    prompt_value RETENTION_DAYS "Log retention days" "$RETENTION_DAYS"
    prompt_value SUSTAIN_DURATION "Sustain duration" "$SUSTAIN_DURATION"
    prompt_value COOLDOWN "Cooldown" "$COOLDOWN"
    prompt_value EMAIL_ENABLED "Enable email alerts (true/false)" "$EMAIL_ENABLED"
    if [[ "$EMAIL_ENABLED" == "true" ]]; then
      prompt_value SMTP_HOST "SMTP host" "$SMTP_HOST"
      prompt_value SMTP_PORT "SMTP port" "$SMTP_PORT"
      prompt_value SMTP_USERNAME "SMTP username" "$SMTP_USERNAME"
      prompt_value SMTP_PASSWORD "SMTP password" "$SMTP_PASSWORD" true
      prompt_value EMAIL_FROM "Email From" "$EMAIL_FROM"
      prompt_value EMAIL_TO "Email To (comma separated)" "$EMAIL_TO"
    fi
  fi

  install -d -m 0750 "$CONFIG_DIR"
  umask 0077
  cat > "$CONFIG_PATH" <<EOF
monitor:
  interval: $MONITOR_INTERVAL

thresholds:
  cpu: $CPU_THRESHOLD
  ram: $RAM_THRESHOLD
  disk: $DISK_THRESHOLD
  network_rx_mbps: $NETWORK_RX_MBPS
  network_tx_mbps: $NETWORK_TX_MBPS

alerts:
  email:
    enabled: $EMAIL_ENABLED
    smtp_host: "$SMTP_HOST"
    smtp_port: $SMTP_PORT
    username: "$SMTP_USERNAME"
    password: "$SMTP_PASSWORD"
    from: "$EMAIL_FROM"
    to: "$EMAIL_TO"

logging:
  retention_days: $RETENTION_DAYS

analysis:
  collect_journal_logs: true
  collect_syslog: true
  process_history: true

alert_rules:
  sustain_duration: $SUSTAIN_DURATION
  cooldown: $COOLDOWN
EOF
  chmod 0640 "$CONFIG_PATH"
}

install_service() {
  cat > "$SERVICE_PATH" <<'EOF'
[Unit]
Description=Server Monitor Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=server-monitor
Group=server-monitor
Environment=SERVER_MONITOR_CONFIG=/etc/server-monitor-agent/config.yaml
WorkingDirectory=/var/log/server-monitor-agent
ExecStart=/usr/local/bin/server-monitor start
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$SERVICE_PATH"
}

if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo --preserve-env=RELEASE_TAG,NON_INTERACTIVE,BINARY_URL,DOWNLOAD_URL,MONITOR_INTERVAL,CPU_THRESHOLD,RAM_THRESHOLD,DISK_THRESHOLD,NETWORK_RX_MBPS,NETWORK_TX_MBPS,EMAIL_ENABLED,SMTP_HOST,SMTP_PORT,SMTP_USERNAME,SMTP_PASSWORD,EMAIL_FROM,EMAIL_TO,RETENTION_DAYS,SUSTAIN_DURATION,COOLDOWN bash "$0" "$@"
  fi
  echo "Please run as root (or install sudo)"
  exit 1
fi

install_deps
resolve_binary_url

getent group "$APP_GROUP" >/dev/null 2>&1 || groupadd --system "$APP_GROUP"
id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --gid "$APP_GROUP" --no-create-home --shell /usr/sbin/nologin "$APP_USER"
usermod -a -G "$APP_GROUP" "$APP_USER"

mkdir -p "$CONFIG_DIR" "$LOG_DIR"
install_binary
configure_agent
install_service
chown -R "$APP_USER":"$APP_GROUP" "$LOG_DIR" "$CONFIG_DIR"

systemctl daemon-reload
systemctl enable server-monitor.service
systemctl restart server-monitor.service

echo "Installed successfully"
echo "Binary URL: $BINARY_URL"
echo "Config: $CONFIG_PATH"
echo "Service: server-monitor.service"
