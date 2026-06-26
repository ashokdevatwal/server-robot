package config

import (
	"errors"
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Monitor    MonitorConfig   `yaml:"monitor"`
	Thresholds ThresholdConfig `yaml:"thresholds"`
	Alerts     AlertConfig     `yaml:"alerts"`
	Logging    LoggingConfig   `yaml:"logging"`
	Analysis   AnalysisConfig  `yaml:"analysis"`
	Rules      AlertRuleConfig `yaml:"alert_rules"`
}

type MonitorConfig struct {
	Interval string `yaml:"interval"`
}

type ThresholdConfig struct {
	CPU           float64 `yaml:"cpu"`
	RAM           float64 `yaml:"ram"`
	Disk          float64 `yaml:"disk"`
	NetworkRXMbps float64 `yaml:"network_rx_mbps"`
	NetworkTXMbps float64 `yaml:"network_tx_mbps"`
}

type AlertConfig struct {
	Email EmailConfig `yaml:"email"`
}

type EmailConfig struct {
	Enabled  bool   `yaml:"enabled"`
	SMTPHost string `yaml:"smtp_host"`
	SMTPPort int    `yaml:"smtp_port"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
	From     string `yaml:"from"`
	To       string `yaml:"to"`
}

type LoggingConfig struct {
	RetentionDays int `yaml:"retention_days"`
}

type AnalysisConfig struct {
	CollectJournalLogs bool `yaml:"collect_journal_logs"`
	CollectSyslog      bool `yaml:"collect_syslog"`
	ProcessHistory     bool `yaml:"process_history"`
}

type AlertRuleConfig struct {
	SustainDuration string `yaml:"sustain_duration"`
	Cooldown        string `yaml:"cooldown"`
}

func Load(path string) (Config, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}
	cfg := Config{}
	if err := yaml.Unmarshal(b, &cfg); err != nil {
		return Config{}, err
	}
	cfg.applyDefaults()
	return cfg, cfg.Validate()
}

func (c *Config) applyDefaults() {
	if c.Monitor.Interval == "" {
		c.Monitor.Interval = "30s"
	}
	if c.Logging.RetentionDays == 0 {
		c.Logging.RetentionDays = 30
	}
	if c.Rules.SustainDuration == "" {
		c.Rules.SustainDuration = "5m"
	}
	if c.Rules.Cooldown == "" {
		c.Rules.Cooldown = "15m"
	}
}

func (c Config) Validate() error {
	if _, err := c.Interval(); err != nil {
		return fmt.Errorf("monitor.interval: %w", err)
	}
	if _, err := c.SustainDuration(); err != nil {
		return fmt.Errorf("alert_rules.sustain_duration: %w", err)
	}
	if _, err := c.Cooldown(); err != nil {
		return fmt.Errorf("alert_rules.cooldown: %w", err)
	}
	if c.Thresholds.CPU <= 0 || c.Thresholds.CPU > 100 {
		return errors.New("thresholds.cpu must be in (0,100]")
	}
	if c.Thresholds.RAM <= 0 || c.Thresholds.RAM > 100 {
		return errors.New("thresholds.ram must be in (0,100]")
	}
	if c.Thresholds.Disk <= 0 || c.Thresholds.Disk > 100 {
		return errors.New("thresholds.disk must be in (0,100]")
	}
	if c.Alerts.Email.Enabled {
		if c.Alerts.Email.SMTPHost == "" || c.Alerts.Email.SMTPPort == 0 || c.Alerts.Email.Username == "" || c.Alerts.Email.Password == "" || c.Alerts.Email.From == "" || c.Alerts.Email.To == "" {
			return errors.New("all email fields are required when alerts.email.enabled is true")
		}
	}
	return nil
}

func (c Config) Interval() (time.Duration, error) {
	return time.ParseDuration(c.Monitor.Interval)
}

func (c Config) SustainDuration() (time.Duration, error) {
	return time.ParseDuration(c.Rules.SustainDuration)
}

func (c Config) Cooldown() (time.Duration, error) {
	return time.ParseDuration(c.Rules.Cooldown)
}
