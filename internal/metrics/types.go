package metrics

import "time"

type CPUStat struct {
	Overall         float64   `json:"overall"`
	PerCore         []float64 `json:"per_core"`
	Load1           float64   `json:"load1"`
	Load5           float64   `json:"load5"`
	Load15          float64   `json:"load15"`
	Steal           float64   `json:"steal"`
	ContextSwitches uint64    `json:"context_switches"`
	TemperatureC    *float64  `json:"temperature_c,omitempty"`
}

type RAMStat struct {
	Total           uint64  `json:"total"`
	Used            uint64  `json:"used"`
	Free            uint64  `json:"free"`
	Cached          uint64  `json:"cached"`
	Buffers         uint64  `json:"buffers"`
	UsedPercent     float64 `json:"used_percent"`
	SwapTotal       uint64  `json:"swap_total"`
	SwapUsed        uint64  `json:"swap_used"`
	SwapUsedPercent float64 `json:"swap_used_percent"`
	SwapPagesIn     uint64  `json:"swap_pages_in"`
	SwapPagesOut    uint64  `json:"swap_pages_out"`
	Available       uint64  `json:"available"`
}

type DiskStat struct {
	Mountpoint  string  `json:"mountpoint"`
	Filesystem  string  `json:"filesystem"`
	UsedPercent float64 `json:"used_percent"`
	FreeBytes   uint64  `json:"free_bytes"`
	InodesUsed  uint64  `json:"inodes_used"`
	InodesFree  uint64  `json:"inodes_free"`
	ReadIOPS    uint64  `json:"read_iops"`
	WriteIOPS   uint64  `json:"write_iops"`
	ReadMBps    float64 `json:"read_mbps"`
	WriteMBps   float64 `json:"write_mbps"`
}

type NetworkStat struct {
	Interface string  `json:"interface"`
	RXBytes   uint64  `json:"rx_bytes"`
	TXBytes   uint64  `json:"tx_bytes"`
	RXMbps    float64 `json:"rx_mbps"`
	TXMbps    float64 `json:"tx_mbps"`
	Errors    uint64  `json:"errors"`
	Dropped   uint64  `json:"dropped"`
	Up        bool    `json:"up"`
}

type ProcessStat struct {
	PID        int32   `json:"pid"`
	Name       string  `json:"name"`
	User       string  `json:"user"`
	CPU        float64 `json:"cpu"`
	Memory     float32 `json:"memory"`
	ReadBytes  uint64  `json:"read_bytes"`
	WriteBytes uint64  `json:"write_bytes"`
	Command    string  `json:"command"`
	Runtime    string  `json:"runtime"`
}

type ServiceStat struct {
	Name         string  `json:"name"`
	PID          int32   `json:"pid"`
	Status       string  `json:"status"`
	RestartCount int64   `json:"restart_count"`
	CPU          float64 `json:"cpu"`
	Memory       float32 `json:"memory"`
}

type Snapshot struct {
	Timestamp    time.Time     `json:"timestamp"`
	Hostname     string        `json:"hostname"`
	IP           string        `json:"ip"`
	OSVersion    string        `json:"os_version"`
	Uptime       uint64        `json:"uptime_seconds"`
	CPU          CPUStat       `json:"cpu"`
	RAM          RAMStat       `json:"ram"`
	Disks        []DiskStat    `json:"disks"`
	Network      []NetworkStat `json:"network"`
	TopProcesses []ProcessStat `json:"top_processes"`
	TopServices  []ServiceStat `json:"top_services"`
}
