package process

import (
	"context"
	"sort"
	"time"

	"github.com/ashokdevatwal/server-robot/internal/metrics"
	"github.com/shirou/gopsutil/v3/process"
)

func CollectTop(ctx context.Context, limit int) ([]metrics.ProcessStat, error) {
	procs, err := process.ProcessesWithContext(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]metrics.ProcessStat, 0, len(procs))
	now := time.Now()
	for _, p := range procs {
		cpu, _ := p.CPUPercentWithContext(ctx)
		memP, _ := p.MemoryPercentWithContext(ctx)
		n, _ := p.NameWithContext(ctx)
		u, _ := p.UsernameWithContext(ctx)
		cmd, _ := p.CmdlineWithContext(ctx)
		ct, _ := p.CreateTimeWithContext(ctx)
		io, _ := p.IOCountersWithContext(ctx)
		runtime := ""
		if ct > 0 {
			runtime = now.Sub(time.UnixMilli(ct)).String()
		}
		stat := metrics.ProcessStat{PID: p.Pid, Name: n, User: u, CPU: cpu, Memory: memP, Command: cmd, Runtime: runtime}
		if io != nil {
			stat.ReadBytes = io.ReadBytes
			stat.WriteBytes = io.WriteBytes
		}
		out = append(out, stat)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].CPU == out[j].CPU {
			return out[i].Memory > out[j].Memory
		}
		return out[i].CPU > out[j].CPU
	})
	if len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}
