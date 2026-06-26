package disk

import (
	"context"
	"strings"

	"github.com/ashokdevatwal/server-robot/internal/metrics"
	"github.com/shirou/gopsutil/v3/disk"
)

func Collect(ctx context.Context) ([]metrics.DiskStat, error) {
	parts, err := disk.PartitionsWithContext(ctx, true)
	if err != nil {
		return nil, err
	}
	io, _ := disk.IOCountersWithContext(ctx)
	stats := make([]metrics.DiskStat, 0, len(parts))
	for _, p := range parts {
		u, err := disk.UsageWithContext(ctx, p.Mountpoint)
		if err != nil {
			continue
		}
		ioName := trimDevice(p.Device)
		dio := io[ioName]
		stats = append(stats, metrics.DiskStat{
			Mountpoint:  p.Mountpoint,
			Filesystem:  p.Fstype,
			UsedPercent: u.UsedPercent,
			FreeBytes:   u.Free,
			InodesUsed:  u.InodesUsed,
			InodesFree:  u.InodesFree,
			ReadIOPS:    dio.ReadCount,
			WriteIOPS:   dio.WriteCount,
			ReadMBps:    float64(dio.ReadBytes) / 1024 / 1024,
			WriteMBps:   float64(dio.WriteBytes) / 1024 / 1024,
		})
	}
	return stats, nil
}

func trimDevice(dev string) string {
	base := strings.TrimPrefix(dev, "/dev/")
	if base == "" {
		return dev
	}
	return base
}
