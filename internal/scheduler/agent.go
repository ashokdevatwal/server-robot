package scheduler

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/ashokdevatwal/server-robot/internal/alerts"
	"github.com/ashokdevatwal/server-robot/internal/config"
	"github.com/ashokdevatwal/server-robot/internal/cpu"
	"github.com/ashokdevatwal/server-robot/internal/disk"
	"github.com/ashokdevatwal/server-robot/internal/logs"
	"github.com/ashokdevatwal/server-robot/internal/metrics"
	"github.com/ashokdevatwal/server-robot/internal/network"
	"github.com/ashokdevatwal/server-robot/internal/process"
	"github.com/ashokdevatwal/server-robot/internal/ram"
	"github.com/ashokdevatwal/server-robot/internal/rootcause"
	"github.com/ashokdevatwal/server-robot/internal/services"
	"github.com/shirou/gopsutil/v3/host"
)

type Agent struct {
	cfg    config.Config
	logger *log.Logger
	net    *network.Collector
	sender alerts.Sender
	state  map[string]breachState
}

type breachState struct {
	firstExceeded time.Time
	lastAlerted   time.Time
}

func New(cfg config.Config, logger *log.Logger) *Agent {
	return &Agent{
		cfg:    cfg,
		logger: logger,
		net:    network.NewCollector(),
		sender: alerts.NewEmailSender(cfg.Alerts.Email),
		state:  map[string]breachState{},
	}
}

func (a *Agent) Run(ctx context.Context) error {
	interval, _ := a.cfg.Interval()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	a.logger.Println("agent started")
	for {
		if err := a.tick(ctx); err != nil {
			a.logger.Printf("tick error: %v", err)
		}
		select {
		case <-ctx.Done():
			a.logger.Println("agent stopped")
			return nil
		case <-ticker.C:
		}
	}
}

func (a *Agent) tick(ctx context.Context) error {
	snapshot, err := a.collectSnapshot(ctx)
	if err != nil {
		return err
	}
	_ = a.writeStatus(snapshot)
	breaches := a.detectBreaches(snapshot)
	if len(breaches) == 0 {
		for k := range a.state {
			delete(a.state, k)
		}
		return nil
	}
	now := time.Now()
	sustain, _ := a.cfg.SustainDuration()
	cooldown, _ := a.cfg.Cooldown()
	active := []string{}
	for metric := range breaches {
		st := a.state[metric]
		if st.firstExceeded.IsZero() {
			st.firstExceeded = now
		}
		a.state[metric] = st
		if now.Sub(st.firstExceeded) >= sustain && now.Sub(st.lastAlerted) >= cooldown {
			active = append(active, metric)
			st.lastAlerted = now
			a.state[metric] = st
		}
	}
	if len(active) == 0 {
		return nil
	}
	sort.Strings(active)
	return a.handleIncident(ctx, snapshot, active, breaches)
}

func (a *Agent) collectSnapshot(ctx context.Context) (metrics.Snapshot, error) {
	cpuStat, err := cpu.Collect(ctx)
	if err != nil {
		return metrics.Snapshot{}, err
	}
	ramStat, err := ram.Collect(ctx)
	if err != nil {
		return metrics.Snapshot{}, err
	}
	diskStat, err := disk.Collect(ctx)
	if err != nil {
		return metrics.Snapshot{}, err
	}
	netStat, err := a.net.Collect(ctx)
	if err != nil {
		return metrics.Snapshot{}, err
	}
	procs, err := process.CollectTop(ctx, 8)
	if err != nil {
		return metrics.Snapshot{}, err
	}
	h, _ := host.InfoWithContext(ctx)
	servicesMap := make([]metrics.ServiceStat, 0, len(procs))
	for _, p := range procs {
		svc := services.ServiceForPID(p.PID)
		if svc == "" {
			continue
		}
		servicesMap = append(servicesMap, metrics.ServiceStat{Name: svc, PID: p.PID, Status: "active", CPU: p.CPU, Memory: p.Memory})
	}
	return metrics.Snapshot{
		Timestamp:    time.Now().UTC(),
		Hostname:     h.Hostname,
		IP:           firstIP(),
		OSVersion:    h.Platform + " " + h.PlatformVersion,
		Uptime:       h.Uptime,
		CPU:          cpuStat,
		RAM:          ramStat,
		Disks:        diskStat,
		Network:      netStat,
		TopProcesses: procs,
		TopServices:  servicesMap,
	}, nil
}

func (a *Agent) detectBreaches(s metrics.Snapshot) map[string]float64 {
	out := map[string]float64{}
	if s.CPU.Overall >= a.cfg.Thresholds.CPU {
		out["cpu"] = s.CPU.Overall
	}
	if s.RAM.UsedPercent >= a.cfg.Thresholds.RAM {
		out["ram"] = s.RAM.UsedPercent
	}
	for _, d := range s.Disks {
		if d.UsedPercent >= a.cfg.Thresholds.Disk {
			out["disk"] = d.UsedPercent
			break
		}
	}
	for _, n := range s.Network {
		if n.RXMbps >= a.cfg.Thresholds.NetworkRXMbps {
			out["network_rx"] = n.RXMbps
		}
		if n.TXMbps >= a.cfg.Thresholds.NetworkTXMbps {
			out["network_tx"] = n.TXMbps
		}
	}
	return out
}

func (a *Agent) handleIncident(ctx context.Context, snap metrics.Snapshot, active []string, breaches map[string]float64) error {
	analysis := rootcause.Analyze(snap, active)
	subject := fmt.Sprintf("[Critical] Server %s alert on %s", strings.ToUpper(strings.Join(active, ",")), snap.Hostname)
	archive, err := logs.CollectIncident(ctx, "logs")
	if err != nil {
		a.logger.Printf("collect incident failed: %v", err)
	}
	body := a.renderAlertHTML(snap, active, breaches, analysis)
	err = a.sender.Send(alerts.Alert{Subject: subject, HTMLBody: body, AttachmentPaths: []string{archive}})
	if err != nil {
		a.logger.Printf("send email failed: %v", err)
	}
	a.logger.Printf("incident triggered: %s", strings.Join(active, ","))
	return nil
}

func (a *Agent) renderAlertHTML(s metrics.Snapshot, active []string, breaches map[string]float64, r rootcause.Analysis) string {
	rows := ""
	for _, p := range s.TopProcesses {
		rows += fmt.Sprintf("<tr><td>%d</td><td>%s</td><td>%.2f</td><td>%.2f</td><td>%s</td></tr>", p.PID, p.Name, p.CPU, p.Memory, p.Command)
	}
	return fmt.Sprintf(`<h2>Server Monitor Alert</h2><p><b>Host:</b> %s (%s)</p><p><b>OS:</b> %s</p><p><b>Uptime:</b> %ds</p><p><b>Triggered:</b> %s</p><p><b>Breaches:</b> %v</p><p><b>Root Cause:</b> %s</p><p><b>Summary:</b> %s</p><p><b>Recommendation:</b> %s</p><table border="1" cellpadding="4" cellspacing="0"><tr><th>PID</th><th>Name</th><th>CPU %%</th><th>RAM %%</th><th>Command</th></tr>%s</table>`, s.Hostname, s.IP, s.OSVersion, s.Uptime, strings.Join(active, ", "), breaches, r.LikelyCause, r.Summary, r.Recommendation, rows)
}

func (a *Agent) writeStatus(s metrics.Snapshot) error {
	if err := os.MkdirAll("logs", 0o750); err != nil {
		return err
	}
	b, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile("logs/status.json", b, 0o640)
}

func firstIP() string {
	ifaces, _ := net.Interfaces()
	for _, i := range ifaces {
		if i.Flags&net.FlagUp == 0 || i.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := i.Addrs()
		for _, a := range addrs {
			ip, _, _ := net.ParseCIDR(a.String())
			if ip != nil && ip.To4() != nil {
				return ip.String()
			}
		}
	}
	return ""
}
