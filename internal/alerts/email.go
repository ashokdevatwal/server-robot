package alerts

import (
	"fmt"
	"strings"

	"github.com/ashokdevatwal/server-robot/internal/config"
	gomail "gopkg.in/gomail.v2"
)

type Alert struct {
	Subject         string
	HTMLBody        string
	AttachmentPaths []string
}

type Sender interface {
	Send(alert Alert) error
}

type EmailSender struct {
	cfg config.EmailConfig
}

func NewEmailSender(cfg config.EmailConfig) *EmailSender {
	return &EmailSender{cfg: cfg}
}

func (e *EmailSender) Send(alert Alert) error {
	if !e.cfg.Enabled {
		return nil
	}
	m := gomail.NewMessage()
	m.SetHeader("From", e.cfg.From)
	m.SetHeader("To", strings.Split(e.cfg.To, ",")...)
	m.SetHeader("Subject", alert.Subject)
	m.SetBody("text/html", alert.HTMLBody)
	for _, a := range alert.AttachmentPaths {
		m.Attach(a)
	}
	d := gomail.NewDialer(e.cfg.SMTPHost, e.cfg.SMTPPort, e.cfg.Username, e.cfg.Password)
	if err := d.DialAndSend(m); err != nil {
		return fmt.Errorf("sending alert email: %w", err)
	}
	return nil
}
