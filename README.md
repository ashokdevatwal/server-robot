# server-monitor-agent

Production-oriented Linux monitoring daemon for Ubuntu, built in Go.

## Features
- CPU, RAM, Disk, Network monitoring
- Process and systemd service correlation
- Sustained-threshold alerts with cooldown/dedup
- Root cause hints and incident log bundles
- HTML email alerts with attachments
- systemd service support and install/uninstall scripts

## Repository Layout
- `/cmd/monitor` CLI entrypoint
- `/internal/*` modular collectors, scheduler, alerts, root-cause engine
- `/configs/config.yaml` runtime configuration
- `/scripts/install.sh` and `/scripts/uninstall.sh`
- `/systemd/server-monitor.service`

## Build
```bash
go build -o server-monitor-0.1.0 ./cmd/monitor
```

## Move To Dist with .tar.gz
```bash
tar -czvf dist/server-monitor-0.1.0.tar.gz server-monitor-0.1.0
rm server-monitor-0.1.0
```  


## Validate Config
```bash
./server-monitor config validate
```

## Run Locally
```bash
./server-monitor start
```

## CLI Commands
```bash
server-monitor status
server-monitor version
server-monitor test-email
server-monitor collect
server-monitor config validate
server-monitor start
server-monitor stop
server-monitor restart
```

## Install on Ubuntu
```bash
sudo ./scripts/install.sh
```

Interactive install now asks for SMTP, alert, and threshold settings during setup.

### Direct Install On Server (Download + Run)
Use this when you want installation to begin immediately on a fresh server.
This flow has no repo source dependency and installs from binary release assets only:

```bash
curl -fsSL https://raw.githubusercontent.com/ashokdevatwal/server-robot/main/scripts/quick-install.sh -o quick-install.sh
chmod +x quick-install.sh
sudo ./quick-install.sh
```

Or run in one line:

```bash
curl -fsSL https://raw.githubusercontent.com/ashokdevatwal/server-robot/main/scripts/quick-install.sh | sudo bash
```

Binary URL can be provided explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/ashokdevatwal/server-robot/main/scripts/quick-install.sh | \
	sudo env BINARY_URL="https://github.com/ashokdevatwal/server-robot/releases/download/v0.1.0/server-monitor-linux-amd64.tar.gz" bash
```

## Easy Server Distribution
Non-interactive install is supported for automation tools (Ansible, cloud-init, CI/CD):

```bash
sudo NON_INTERACTIVE=true \
	BINARY_URL="https://github.com/ashokdevatwal/server-robot/releases/download/v0.1.0/server-monitor-linux-amd64.tar.gz" \
	EMAIL_ENABLED=true \
	SMTP_HOST="email-smtp.us-east-2.amazonaws.com" \
	SMTP_PORT=587 \
	SMTP_USERNAME="YOUR_SMTP_USER" \
	SMTP_PASSWORD="YOUR_SMTP_PASS" \
	EMAIL_FROM="admin@tractorjunction.com" \
	EMAIL_TO="ops@tractorjunction.com" \
	CPU_THRESHOLD=85 RAM_THRESHOLD=85 DISK_THRESHOLD=90 \
	./quick-install.sh --non-interactive
```

To keep existing config on upgrades:

```bash
sudo systemctl restart server-monitor.service
```

## Configuration
Edit `/etc/server-monitor-agent/config.yaml` after install, then:
```bash
sudo systemctl restart server-monitor.service
```
