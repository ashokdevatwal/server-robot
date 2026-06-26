#!/usr/bin/env bash
set -euo pipefail

APP_USER="server-monitor"
APP_GROUP="server-monitor"
INSTALL_DIR="/opt/server-monitor-agent"
CONFIG_DIR="/etc/server-monitor-agent"
LOG_DIR="/var/log/server-monitor-agent"
BIN_PATH="/usr/local/bin/server-monitor"
SERVICE_PATH="/etc/systemd/system/server-monitor.service"
CONFIG_PATH="$CONFIG_DIR/config.yaml"

NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
SKIP_CONFIG_PROMPT="${SKIP_CONFIG_PROMPT:-false}"
DOWNLOAD_URL="${DOWNLOAD_URL:-}"

usage() {
  cat <<'USAGE'
Usage: sudo ./scripts/install.sh [options]

Options:
  --non-interactive    Do not prompt. Use existing config or env vars/defaults.
  --skip-config        Keep existing /etc config (if present), skip config wizard.
  --download-url URL   Download server-monitor binary or tar.gz from URL.
  -h, --help           Show this help.

Environment variables (for non-interactive installs):
  NON_INTERACTIVE=true
  SKIP_CONFIG_PROMPT=true
  DOWNLOAD_URL=https://example.com/server-monitor-linux-amd64.tar.gz
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
    --skip-config)
      SKIP_CONFIG_PROMPT="true"
      ;;
    --download-url)
      shift
      DOWNLOAD_URL="${1:-}"
      if [[ -z "$DOWNLOAD_URL" ]]; then
        echo "--download-url requires a value"
        exit 1
      fi
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
  local tmp_file=""
  local tmp_dir=""

  if [[ -n "$DOWNLOAD_URL" ]]; then
    echo "Downloading binary from $DOWNLOAD_URL"
    tmp_file="$(mktemp)"
    curl -fsSL "$DOWNLOAD_URL" -o "$tmp_file"
    if tar -tzf "$tmp_file" >/dev/null 2>&1; then
      tmp_dir="$(mktemp -d)"
      tar -xzf "$tmp_file" -C "$tmp_dir"
      if [[ -f "$tmp_dir/server-monitor" ]]; then
        install -m 0755 "$tmp_dir/server-monitor" "$BIN_PATH"
      else
        local found_bin
        found_bin="$(find "$tmp_dir" -type f -name server-monitor | head -n 1 || true)"
        if [[ -z "$found_bin" ]]; then
          echo "Downloaded archive does not contain server-monitor binary"
          exit 1
        fi
        install -m 0755 "$found_bin" "$BIN_PATH"
      fi
      rm -rf "$tmp_dir"
    else
      install -m 0755 "$tmp_file" "$BIN_PATH"
    fi
    rm -f "$tmp_file"
    return
  fi

  if [[ -f ./server-monitor ]]; then
    install -m 0755 ./server-monitor "$BIN_PATH"
    return
  fi

  echo "Building binary..."
  if ! command -v go >/dev/null 2>&1; then
    echo "Go compiler not found and no local/downloaded binary provided."
    echo "Provide DOWNLOAD_URL or place ./server-monitor before running install."
    exit 1
  fi
  go build -o "$BIN_PATH" ./cmd/monitor
}

load_existing_defaults() {
  local source_config=""

  yaml_val() {
    local key="$1"
    local value=""
    value="$(grep -E "^\\s*${key}:" "$source_config" | head -n1 | cut -d ':' -f2- | xargs || true)"
    value="${value#\"}"
    value="${value%\"}"
    printf '%s' "$value"
  }

  if [[ -f "$CONFIG_PATH" ]]; then
    source_config="$CONFIG_PATH"
  elif [[ -f configs/config.yaml ]]; then
    source_config="configs/config.yaml"
  fi

  if [[ -n "$source_config" ]]; then
    MONITOR_INTERVAL="${MONITOR_INTERVAL:-$(yaml_val interval)}"
    CPU_THRESHOLD="${CPU_THRESHOLD:-$(yaml_val cpu)}"
    RAM_THRESHOLD="${RAM_THRESHOLD:-$(yaml_val ram)}"
    DISK_THRESHOLD="${DISK_THRESHOLD:-$(yaml_val disk)}"
    NETWORK_RX_MBPS="${NETWORK_RX_MBPS:-$(yaml_val network_rx_mbps)}"
    NETWORK_TX_MBPS="${NETWORK_TX_MBPS:-$(yaml_val network_tx_mbps)}"
    SMTP_HOST="${SMTP_HOST:-$(yaml_val smtp_host)}"
    SMTP_PORT="${SMTP_PORT:-$(yaml_val smtp_port)}"
    SMTP_USERNAME="${SMTP_USERNAME:-$(yaml_val username)}"
    SMTP_PASSWORD="${SMTP_PASSWORD:-$(yaml_val password)}"
    EMAIL_FROM="${EMAIL_FROM:-$(yaml_val from)}"
    EMAIL_TO="${EMAIL_TO:-$(yaml_val to)}"
    RETENTION_DAYS="${RETENTION_DAYS:-$(yaml_val retention_days)}"
    SUSTAIN_DURATION="${SUSTAIN_DURATION:-$(yaml_val sustain_duration)}"
    COOLDOWN="${COOLDOWN:-$(yaml_val cooldown)}"
  fi

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
}

configure_agent() {
  load_existing_defaults

  if [[ "$SKIP_CONFIG_PROMPT" == "true" && -f "$CONFIG_PATH" ]]; then
    echo "Keeping existing config at $CONFIG_PATH"
    return
  fi

  if is_interactive && [[ "$SKIP_CONFIG_PROMPT" != "true" ]]; then
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

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

install_deps

getent group "$APP_GROUP" >/dev/null 2>&1 || groupadd --system "$APP_GROUP"
id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --gid "$APP_GROUP" --no-create-home --shell /usr/sbin/nologin "$APP_USER"
usermod -a -G "$APP_GROUP" "$APP_USER"

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"
cp -r cmd internal go.mod go.sum "$INSTALL_DIR" || true
install_binary
configure_agent
install -m 0644 systemd/server-monitor.service "$SERVICE_PATH"
chown -R "$APP_USER":"$APP_GROUP" "$LOG_DIR" "$CONFIG_DIR"

systemctl daemon-reload
systemctl enable server-monitor.service
systemctl restart server-monitor.service

echo "Installed successfully"
echo "Config: $CONFIG_PATH"
echo "Service: server-monitor.service"
