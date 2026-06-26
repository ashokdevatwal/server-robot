#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

systemctl stop server-monitor.service || true
systemctl disable server-monitor.service || true
rm -f /etc/systemd/system/server-monitor.service
systemctl daemon-reload
rm -f /usr/local/bin/server-monitor
rm -rf /etc/server-monitor-agent /var/log/server-monitor-agent /opt/server-monitor-agent
userdel server-monitor 2>/dev/null || true
echo "Uninstalled"
