package ram

import (
	"bufio"
	"context"
	"os"
	"strconv"
	"strings"

	"github.com/ashokdevatwal/server-robot/internal/metrics"
	"github.com/shirou/gopsutil/v3/mem"
)

func Collect(ctx context.Context) (metrics.RAMStat, error) {
	vm, err := mem.VirtualMemoryWithContext(ctx)
	if err != nil {
		return metrics.RAMStat{}, err
	}
	sw, err := mem.SwapMemoryWithContext(ctx)
	if err != nil {
		return metrics.RAMStat{}, err
	}
	in, out := parseSwapActivity()
	return metrics.RAMStat{
		Total:           vm.Total,
		Used:            vm.Used,
		Free:            vm.Free,
		Cached:          vm.Cached,
		Buffers:         vm.Buffers,
		UsedPercent:     vm.UsedPercent,
		Available:       vm.Available,
		SwapTotal:       sw.Total,
		SwapUsed:        sw.Used,
		SwapUsedPercent: sw.UsedPercent,
		SwapPagesIn:     in,
		SwapPagesOut:    out,
	}, nil
}

func parseSwapActivity() (uint64, uint64) {
	f, err := os.Open("/proc/vmstat")
	if err != nil {
		return 0, 0
	}
	defer f.Close()
	var in, out uint64
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "pswpin ") {
			parts := strings.Fields(line)
			in, _ = strconv.ParseUint(parts[1], 10, 64)
		}
		if strings.HasPrefix(line, "pswpout ") {
			parts := strings.Fields(line)
			out, _ = strconv.ParseUint(parts[1], 10, 64)
		}
	}
	return in, out
}
