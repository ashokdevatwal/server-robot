package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/ashokdevatwal/server-robot/internal/alerts"
	"github.com/ashokdevatwal/server-robot/internal/config"
	"github.com/ashokdevatwal/server-robot/internal/logs"
	"github.com/ashokdevatwal/server-robot/internal/scheduler"
	"gopkg.in/natefinch/lumberjack.v2"
)

var version = "0.1.0"

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		return startAgent()
	}
	switch args[0] {
	case "start":
		return startAgent()
	case "status":
		return printStatus()
	case "version":
		fmt.Println(version)
		return nil
	case "test-email":
		cfg, err := loadConfig()
		if err != nil {
			return err
		}
		if !cfg.Alerts.Email.Enabled {
			return errors.New("email alerts are disabled")
		}
		sender := alerts.NewEmailSender(cfg.Alerts.Email)
		return sender.Send(alerts.Alert{Subject: "[Test] Server Monitor Agent", HTMLBody: "<p>Test email from server-monitor-agent.</p>"})
	case "collect":
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		archive, err := logs.CollectIncident(ctx, "logs")
		if err != nil {
			return err
		}
		fmt.Println(archive)
		return nil
	case "config":
		if len(args) > 1 && args[1] == "validate" {
			_, err := loadConfig()
			if err != nil {
				return err
			}
			fmt.Println("config valid")
			return nil
		}
		return errors.New("supported: config validate")
	case "stop", "restart":
		return runSystemctl(args[0])
	default:
		return fmt.Errorf("unknown command: %s", args[0])
	}
}

func startAgent() error {
	cfg, err := loadConfig()
	if err != nil {
		return err
	}
	logger := log.New(&lumberjack.Logger{
		Filename:   "logs/agent.log",
		MaxSize:    20,
		MaxBackups: 10,
		MaxAge:     cfg.Logging.RetentionDays,
		Compress:   true,
	}, "", log.LstdFlags|log.LUTC)
	agent := scheduler.New(cfg, logger)
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	return agent.Run(ctx)
}

func printStatus() error {
	statusPath := filepath.Join("logs", "status.json")
	b, err := os.ReadFile(statusPath)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Println("no status available")
			return nil
		}
		return err
	}
	fmt.Println(string(b))
	return nil
}

func runSystemctl(command string) error {
	cmd := exec.Command("systemctl", command, "server-monitor.service")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func loadConfig() (config.Config, error) {
	configPath := os.Getenv("SERVER_MONITOR_CONFIG")
	if configPath == "" {
		configPath = "configs/config.yaml"
	}
	return config.Load(configPath)
}
