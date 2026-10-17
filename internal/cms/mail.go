package cms

import (
	"bytes"
	"context"
	"crypto/tls"
	"fmt"
	"mime"
	"mime/quotedprintable"
	"net"
	"net/mail"
	"net/smtp"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ---- email ---------------------------------------------------------------

// Email goes out through the SMTP server in Settings › Email, from its
// default name and address unless a message names its own. The core sends
// its test message with it; plugins granted "mail" send through lp_mail.
//
//	settings/email: smtp_host, smtp_port, smtp_security (starttls | tls |
//	none), smtp_username, smtp_password (sealed at rest), from_name,
//	from_email, reply_to

// Message is one email. From and Reply-To fall back to the settings'.
type Message struct {
	FromName  string   `json:"from_name"`
	FromEmail string   `json:"from_email"`
	ReplyTo   string   `json:"reply_to"`
	To        []string `json:"to"`
	Cc        []string `json:"cc"`
	Bcc       []string `json:"bcc"`
	Subject   string   `json:"subject"`
	Text      string   `json:"text"`
	HTML      string   `json:"html"`
}

// Mailer delivers a built message; SMTP by default, a capture in tests.
type Mailer interface {
	Send(ctx context.Context, cfg MailConfig, from string, to []string, msg []byte) error
}

// MailConfig is Settings › Email, with the password opened.
type MailConfig struct {
	Host, Security, Username, Password string
	Port                               int
	FromName, FromEmail, ReplyTo       string
}

func (c MailConfig) configured() bool { return c.Host != "" && c.FromEmail != "" }

const maxRecipients = 50

func (a *App) mailConfig(ctx context.Context) MailConfig {
	s := a.Setting(ctx, "email")
	port, _ := strconv.Atoi(fmt.Sprint(s["smtp_port"]))
	if f, ok := s["smtp_port"].(float64); ok {
		port = int(f)
	}
	security := str(s["smtp_security"])
	if security == "" {
		security = "starttls"
	}
	if port == 0 {
		port = map[string]int{"tls": 465, "none": 25}[security]
		if port == 0 {
			port = 587
		}
	}
	password, _ := a.Secrets.Open(str(s["smtp_password"]))
	return MailConfig{
		Host: strings.TrimSpace(str(s["smtp_host"])), Port: port, Security: security,
		Username: str(s["smtp_username"]), Password: password,
		FromName: str(s["from_name"]), FromEmail: strings.TrimSpace(str(s["from_email"])), ReplyTo: strings.TrimSpace(str(s["reply_to"])),
	}
}

// SendMail checks and sends one message: real addresses only, no header
// injection, at most 50 recipients.
func (a *App) SendMail(ctx context.Context, m Message) error {
	cfg := a.mailConfig(ctx)
	if !cfg.configured() {
		return fmt.Errorf("email isn't set up: add an SMTP server and a from address in Settings › Email")
	}
	if m.FromName == "" {
		m.FromName = cfg.FromName
	}
	if m.FromEmail == "" {
		m.FromEmail = cfg.FromEmail
	}
	if m.ReplyTo == "" {
		m.ReplyTo = cfg.ReplyTo
	}
	from, err := oneAddress(m.FromEmail)
	if err != nil {
		return fmt.Errorf("from: %w", err)
	}
	var rcpt []string
	headers := [][2]string{}
	for _, list := range []struct {
		name  string
		addrs []string
	}{{"To", m.To}, {"Cc", m.Cc}, {"Bcc", m.Bcc}} {
		var shown []string
		for _, raw := range list.addrs {
			if strings.TrimSpace(raw) == "" {
				continue
			}
			addr, err := oneAddress(raw)
			if err != nil {
				return fmt.Errorf("%s: %w", strings.ToLower(list.name), err)
			}
			rcpt = append(rcpt, addr)
			shown = append(shown, addr)
		}
		if len(shown) > 0 && list.name != "Bcc" {
			headers = append(headers, [2]string{list.name, strings.Join(shown, ", ")})
		}
	}
	if len(rcpt) == 0 {
		return fmt.Errorf("a message needs at least one recipient")
	}
	if len(rcpt) > maxRecipients {
		return fmt.Errorf("a message goes to at most %d recipients", maxRecipients)
	}
	if strings.TrimSpace(m.Subject) == "" {
		return fmt.Errorf("a message needs a subject")
	}
	if m.Text == "" && m.HTML == "" {
		return fmt.Errorf("a message needs a body")
	}
	head := [][2]string{{"From", (&mail.Address{Name: oneLine(m.FromName), Address: from}).String()}}
	head = append(head, headers...)
	if m.ReplyTo != "" {
		if rt, err := oneAddress(m.ReplyTo); err == nil {
			head = append(head, [2]string{"Reply-To", rt})
		}
	}
	head = append(head,
		[2]string{"Subject", mime.QEncoding.Encode("utf-8", oneLine(m.Subject))},
		[2]string{"Date", time.Now().Format(time.RFC1123Z)},
		[2]string{"Message-ID", fmt.Sprintf("<%s@%s>", strings.ToLower(strings.TrimRight(base32Key(), "=")), domainOf(from))},
		[2]string{"MIME-Version", "1.0"},
	)
	return a.mailer().Send(ctx, cfg, from, rcpt, buildMIME(head, m.Text, m.HTML))
}

func oneAddress(s string) (string, error) {
	addr, err := mail.ParseAddress(strings.TrimSpace(s))
	if err != nil || strings.ContainsAny(addr.Address, "\r\n") {
		return "", fmt.Errorf("%q isn't an email address", s)
	}
	return addr.Address, nil
}

func oneLine(s string) string { return strings.Join(strings.Fields(s), " ") }

func domainOf(addr string) string {
	if i := strings.LastIndex(addr, "@"); i >= 0 {
		return addr[i+1:]
	}
	return "localhost"
}

func buildMIME(head [][2]string, text, html string) []byte {
	var b bytes.Buffer
	for _, h := range head {
		fmt.Fprintf(&b, "%s: %s\r\n", h[0], h[1])
	}
	part := func(contentType, body string) {
		fmt.Fprintf(&b, "Content-Type: %s; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n", contentType)
		w := quotedprintable.NewWriter(&b)
		w.Write([]byte(strings.ReplaceAll(body, "\n", "\r\n")))
		w.Close()
		b.WriteString("\r\n")
	}
	switch {
	case html == "":
		part("text/plain", text)
	case text == "":
		part("text/html", html)
	default:
		boundary := "lp-" + strings.ToLower(strings.TrimRight(base32Key(), "="))
		fmt.Fprintf(&b, "Content-Type: multipart/alternative; boundary=%q\r\n\r\n", boundary)
		fmt.Fprintf(&b, "--%s\r\n", boundary)
		part("text/plain", text)
		fmt.Fprintf(&b, "--%s\r\n", boundary)
		part("text/html", html)
		fmt.Fprintf(&b, "--%s--\r\n", boundary)
	}
	return b.Bytes()
}

func (a *App) mailer() Mailer {
	if a.Config.Mailer != nil {
		return a.Config.Mailer
	}
	return smtpMailer{}
}

type smtpMailer struct{}

func (smtpMailer) Send(ctx context.Context, cfg MailConfig, from string, to []string, msg []byte) error {
	addr := net.JoinHostPort(cfg.Host, strconv.Itoa(cfg.Port))
	d := net.Dialer{Timeout: 15 * time.Second}
	if dl, ok := ctx.Deadline(); ok {
		d.Deadline = dl
	} else {
		d.Deadline = time.Now().Add(45 * time.Second)
	}
	var conn net.Conn
	var err error
	if cfg.Security == "tls" {
		conn, err = tls.DialWithDialer(&d, "tcp", addr, &tls.Config{ServerName: cfg.Host})
	} else {
		conn, err = d.DialContext(ctx, "tcp", addr)
	}
	if err != nil {
		return fmt.Errorf("couldn't reach %s: %w", addr, err)
	}
	conn.SetDeadline(d.Deadline)
	c, err := smtp.NewClient(conn, cfg.Host)
	if err != nil {
		conn.Close()
		return err
	}
	defer c.Close()
	if cfg.Security == "starttls" {
		if ok, _ := c.Extension("STARTTLS"); !ok {
			return fmt.Errorf("%s doesn't offer STARTTLS; choose TLS or none", cfg.Host)
		}
		if err := c.StartTLS(&tls.Config{ServerName: cfg.Host}); err != nil {
			return err
		}
	}
	if cfg.Username != "" {
		if err := c.Auth(smtp.PlainAuth("", cfg.Username, cfg.Password, cfg.Host)); err != nil {
			return fmt.Errorf("the SMTP server refused the login: %w", err)
		}
	}
	if err := c.Mail(from); err != nil {
		return err
	}
	for _, r := range to {
		if err := c.Rcpt(r); err != nil {
			return fmt.Errorf("the SMTP server refused %s: %w", r, err)
		}
	}
	w, err := c.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(msg); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return c.Quit()
}

// mailLimiter caps what each plugin sends: 200 messages an hour.
type mailLimiter struct {
	mu    sync.Mutex
	sends map[string][]time.Time
}

func (l *mailLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.sends == nil {
		l.sends = map[string][]time.Time{}
	}
	cut := time.Now().Add(-time.Hour)
	kept := l.sends[key][:0]
	for _, t := range l.sends[key] {
		if t.After(cut) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= 200 {
		l.sends[key] = kept
		return false
	}
	l.sends[key] = append(kept, time.Now())
	return true
}

// ---- the API -------------------------------------------------------------

// sendTestMail sends Settings › Email's test message to the address given
// (or the person asking).
func (a *App) sendTestMail(c *Ctx) error {
	if err := c.Need("settings:write"); err != nil {
		return err
	}
	var body struct {
		To string `json:"to"`
	}
	c.Body(&body)
	to := body.To
	if to == "" && c.Actor != nil {
		to = c.Actor.Email
	}
	err := a.SendMail(c.R.Context(), Message{
		To: []string{to}, Subject: "Test email from " + strOr(str(a.general()["title"]), "Libre Publish"),
		Text: "This is a test from Settings › Email. If you can read it, email is working.",
	})
	if err != nil {
		return &Error{Status: 422, Code: "mail_failed", Message: err.Error()}
	}
	a.audit(c.R.Context(), c.Actor, "email.tested", "Setting", 0, "email", map[string]any{"to": to})
	return c.JSON(200, O("ok", true, "to", to))
}

func strOr(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

// sealMailPassword keeps settings/email's password encrypted at rest.
func (a *App) sealMailPassword(data map[string]any) {
	if pw, ok := data["smtp_password"].(string); ok && pw != "" && !strings.HasPrefix(pw, "***") && !strings.HasPrefix(pw, sealedPrefix) {
		data["smtp_password"] = a.Secrets.Seal(pw)
	}
}
