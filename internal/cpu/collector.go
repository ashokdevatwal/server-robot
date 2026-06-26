package cpu

import (
	"bufio"
	"context"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/ashokdevatwal/server-robot/internal/metrics"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/load"
)

func Collect(ctx context.Context) (metrics.CPUStat, error) {
	overall, err := cpu.PercentWithContext(ctx, time.Second, false)
	if err != nil {
		return metrics.CPUStat{}, err
	}
	cores, err := cpu.PercentWithContext(ctx, 0, true)
	if err != nil {
		return metrics.CPUStat{}, err
	}
	avg, err := load.AvgWithContext(ctx)
	if err != nil {
		return metrics.CPUStat{}, err
	}
	timesStat, err := cpu.TimesWithContext(ctx, false)
	if err != nil {
		return metrics.CPUStat{}, err
	}
	var temp *float64
	temps, err := host.SensorsTemperaturesWithContext(ctx)
	if err == nil && len(temps) > 0 {
		t := temps[0].Temperature
		temp = &t
	}
	return metrics.CPUStat{
		Overall:         overall[0],
		PerCore:         cores,
		Load1:           avg.Load1,
		Load5:           avg.Load5,
		Load15:          avg.Load15,
		Steal:           timesStat[0].Steal,
		ContextSwitches: parseContextSwitches(),
		TemperatureC:    temp,
	}, nil
}

func parseContextSwitches() uint64 {
	f, err := os.Open("/proc/stat")
	if err != nil {
		return 0
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "ctxt ") {
			parts := strings.Fields(line)
			if len(parts) == 2 {
				v, _ := strconv.ParseUint(parts[1], 10, 64)
				return v
			}
		}
	}
	return 0
}
