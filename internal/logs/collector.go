package logs

import (
	"archive/zip"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

func CollectIncident(ctx context.Context, outDir string) (string, error) {
	incident := time.Now().UTC().Format("20060102-150405")
	dir := filepath.Join(outDir, "incident-"+incident)
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return "", err
	}
	cmds := map[string][]string{
		"journalctl.txt": {"journalctl", "-n", "500", "--no-pager"},
		"syslog.txt":     {"tail", "-n", "500", "/var/log/syslog"},
		"dmesg.txt":      {"dmesg", "-T"},
		"top.txt":        {"top", "-b", "-n", "1"},
		"ps.txt":         {"ps", "aux"},
		"vmstat.txt":     {"vmstat"},
		"iostat.txt":     {"iostat", "-x", "1", "1"},
		"netstat.txt":    {"netstat", "-s"},
		"ss.txt":         {"ss", "-s"},
		"df.txt":         {"df", "-h"},
		"free.txt":       {"free", "-m"},
		"uptime.txt":     {"uptime"},
	}
	for name, cmdArgs := range cmds {
		_ = runCommand(ctx, filepath.Join(dir, name), cmdArgs)
	}
	archive := filepath.Join(outDir, "incident-"+incident+".zip")
	if err := zipDir(dir, archive); err != nil {
		return "", err
	}
	return archive, nil
}

func runCommand(ctx context.Context, file string, args []string) error {
	if len(args) == 0 {
		return nil
	}
	f, err := os.Create(file)
	if err != nil {
		return err
	}
	defer f.Close()
	cmdCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(cmdCtx, args[0], args[1:]...)
	cmd.Stdout = f
	cmd.Stderr = f
	if err := cmd.Run(); err != nil {
		_, _ = f.WriteString("\nerror: " + err.Error())
	}
	return nil
}

func zipDir(srcDir, dst string) error {
	f, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer f.Close()
	zw := zip.NewWriter(f)
	defer zw.Close()

	return filepath.Walk(srcDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		rel, _ := filepath.Rel(srcDir, path)
		w, err := zw.Create(rel)
		if err != nil {
			return err
		}
		r, err := os.Open(path)
		if err != nil {
			return err
		}
		defer r.Close()
		_, err = io.Copy(w, r)
		if err != nil {
			return fmt.Errorf("copy %s: %w", path, err)
		}
		return nil
	})
}
