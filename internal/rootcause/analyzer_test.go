package rootcause

import (
	"testing"

	"github.com/ashokdevatwal/server-robot/internal/metrics"
)

func TestAnalyzeHighCPU(t *testing.T) {
	s := metrics.Snapshot{CPU: metrics.CPUStat{Overall: 96}, RAM: metrics.RAMStat{UsedPercent: 70}, TopProcesses: []metrics.ProcessStat{{Name: "nginx", CPU: 94}}}
	a := Analyze(s, []string{"cpu"})
	if a.LikelyCause == "" || a.Recommendation == "" {
		t.Fatal("expected cause and recommendation")
	}
}
