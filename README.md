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
go build -o server-monitor ./cmd/monitor
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

## Configuration
Edit `/etc/server-monitor-agent/config.yaml` after install, then:
```bash
sudo systemctl restart server-monitor.service
```
