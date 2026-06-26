package network

import (
	"context"
	"sync"
	"time"

	"github.com/ashokdevatwal/server-robot/internal/metrics"
	gnet "github.com/shirou/gopsutil/v3/net"
)

type Collector struct {
	mu   sync.Mutex
	prev map[string]counter
}

type counter struct {
	RX uint64
	TX uint64
	At time.Time
}

func NewCollector() *Collector {
	return &Collector{prev: map[string]counter{}}
}

func (c *Collector) Collect(ctx context.Context) ([]metrics.NetworkStat, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	io, err := gnet.IOCountersWithContext(ctx, true)
	if err != nil {
		return nil, err
	}
	ifs, _ := gnet.InterfacesWithContext(ctx)
	up := map[string]bool{}
	for _, it := range ifs {
		for _, f := range it.Flags {
			if f == "up" {
				up[it.Name] = true
			}
		}
	}
	now := time.Now()
	out := make([]metrics.NetworkStat, 0, len(io))
	for _, n := range io {
		pr := c.prev[n.Name]
		deltaSec := now.Sub(pr.At).Seconds()
		if deltaSec <= 0 {
			deltaSec = 1
		}
		rxMbps := float64(0)
		txMbps := float64(0)
		if !pr.At.IsZero() {
			rxMbps = (float64(n.BytesRecv-pr.RX) * 8 / 1024 / 1024) / deltaSec
			txMbps = (float64(n.BytesSent-pr.TX) * 8 / 1024 / 1024) / deltaSec
		}
		c.prev[n.Name] = counter{RX: n.BytesRecv, TX: n.BytesSent, At: now}
		out = append(out, metrics.NetworkStat{
			Interface: n.Name,
			RXBytes:   n.BytesRecv,
			TXBytes:   n.BytesSent,
			RXMbps:    rxMbps,
			TXMbps:    txMbps,
			Errors:    n.Errin + n.Errout,
			Dropped:   n.Dropin + n.Dropout,
			Up:        up[n.Name],
		})
	}
	return out, nil
}
