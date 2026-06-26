package config

import "testing"

func TestValidateRejectsInvalidCPUThreshold(t *testing.T) {
	cfg := Config{Monitor: MonitorConfig{Interval: "30s"}, Thresholds: ThresholdConfig{CPU: 101, RAM: 90, Disk: 90}, Rules: AlertRuleConfig{SustainDuration: "5m", Cooldown: "10m"}}
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected validation error")
	}
}

func TestValidateRequiresEmailFieldsWhenEnabled(t *testing.T) {
	cfg := Config{Monitor: MonitorConfig{Interval: "30s"}, Thresholds: ThresholdConfig{CPU: 80, RAM: 80, Disk: 80}, Alerts: AlertConfig{Email: EmailConfig{Enabled: true}}, Rules: AlertRuleConfig{SustainDuration: "5m", Cooldown: "10m"}}
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected validation error")
	}
}
