package rootcause

import (
	"fmt"
	"strings"

	"github.com/ashokdevatwal/server-robot/internal/metrics"
)

type Analysis struct {
	LikelyCause    string
	Summary        string
	Recommendation string
}

func Analyze(snapshot metrics.Snapshot, breaches []string) Analysis {
	cause := "Resource pressure due to sustained load"
	reco := "Inspect top process and recent deployment changes"
	if len(snapshot.TopProcesses) > 0 {
		top := snapshot.TopProcesses[0]
		if top.Memory > 80 {
			cause = "Possible memory leak or OOM risk"
			reco = "Capture heap profile and restart affected service"
		} else if top.CPU > 85 {
			cause = "Possible infinite loop or traffic surge"
			reco = "Review request volume, recent code changes, and restart service if needed"
		} else if top.WriteBytes > top.ReadBytes*3 {
			cause = "Heavy disk writes or log explosion"
			reco = "Inspect log growth and scheduled jobs writing to disk"
		}
	}
	summary := fmt.Sprintf("Triggered metrics: %s. CPU %.1f%%, RAM %.1f%%.", strings.Join(breaches, ", "), snapshot.CPU.Overall, snapshot.RAM.UsedPercent)
	return Analysis{LikelyCause: cause, Summary: summary, Recommendation: reco}
}
