#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="ashokdevatwal"
REPO_NAME="server-robot"
REPO_REF="${REPO_REF:-main}"

WORK_DIR="$(mktemp -d)"
ARCHIVE_PATH="$WORK_DIR/${REPO_NAME}.tar.gz"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo --preserve-env=REPO_REF,NON_INTERACTIVE,SKIP_CONFIG_PROMPT,DOWNLOAD_URL,MONITOR_INTERVAL,CPU_THRESHOLD,RAM_THRESHOLD,DISK_THRESHOLD,NETWORK_RX_MBPS,NETWORK_TX_MBPS,EMAIL_ENABLED,SMTP_HOST,SMTP_PORT,SMTP_USERNAME,SMTP_PASSWORD,EMAIL_FROM,EMAIL_TO,RETENTION_DAYS,SUSTAIN_DURATION,COOLDOWN bash "$0" "$@"
  fi
  echo "Please run as root (or install sudo)"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required"
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "tar is required"
  exit 1
fi

ARCHIVE_URL="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${REPO_REF}"
echo "Downloading ${REPO_OWNER}/${REPO_NAME} (${REPO_REF})..."
curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"

tar -xzf "$ARCHIVE_PATH" -C "$WORK_DIR"
REPO_DIR="$WORK_DIR/${REPO_NAME}-${REPO_REF}"

if [[ ! -f "$REPO_DIR/scripts/install.sh" ]]; then
  echo "install.sh not found in downloaded archive"
  exit 1
fi

chmod +x "$REPO_DIR/scripts/install.sh"
echo "Starting installer..."
bash "$REPO_DIR/scripts/install.sh" "$@"
