// librepublish is the whole CMS in one file: the API, the admin, the
// database (SQLite) and the plugin host. Download it, run it.
//
//	librepublish serve [--data ./data] [--addr :8080] [--url https://cms.example.com]
//	librepublish user create --email you@example.com --name You --password … [--role Administrator]
//	librepublish token create --name PRODUCTION [--role "Production site"]
//	librepublish seed-blocks
//	librepublish version
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/Martin-Business-Consultants/libre-publish/go/internal/admin"
	"github.com/Martin-Business-Consultants/libre-publish/go/internal/cms"
)

func main() {
	args := os.Args[1:]
	cmd := "serve"
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		cmd, args = args[0], args[1:]
	}
	var err error
	switch cmd {
	case "serve":
		err = serve(args)
	case "user":
		err = user(args)
	case "token":
		err = token(args)
	case "seed-blocks":
		err = seedBlocks(args)
	case "version", "--version":
		fmt.Println("librepublish", cms.Version)
	case "help", "-h", "--help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "librepublish: unknown command %q\n\n", cmd)
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "librepublish:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `librepublish: a headless CMS in one file.

  serve        run it (the default)         --data DIR --addr :8080 --url https://cms.example.com
  user create  add a person                 --email --name --password [--role Administrator]
  user password      a new password         --email --password
  user disable-2fa   turn two-factor off    --email
  token create issue a service token        --name PRODUCTION [--role "Production site"]
  seed-blocks  install the starter block types
  version

Every flag has an environment variable: DATA_DIR, ADDR (or PORT), APP_URL,
SITE_KEY, CMS_DELIVERY_RATE_LIMIT, SECRET_KEY, and TRUST_PROXY=1 behind a
proxy (Caddy, nginx, a load balancer) so client addresses come from
X-Forwarded-For.
`)
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// common reads the flags every command shares, then the command's own.
func common(name string, args []string, extra func(*flag.FlagSet)) (cms.Config, *flag.FlagSet, error) {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	addr := env("ADDR", "")
	if addr == "" {
		addr = ":" + env("PORT", "8080")
	}
	data := fs.String("data", env("DATA_DIR", "./data"), "where the database and files live")
	listen := fs.String("addr", addr, "address to listen on")
	url := fs.String("url", env("APP_URL", ""), "the CMS's own address, which asset URLs start with")
	if extra != nil {
		extra(fs)
	}
	if err := fs.Parse(args); err != nil {
		return cms.Config{}, nil, err
	}
	base := strings.TrimRight(*url, "/")
	if base == "" {
		host := *listen
		if strings.HasPrefix(host, ":") {
			host = "localhost" + host
		}
		base = "http://" + host
	}
	limit, _ := strconv.Atoi(env("CMS_DELIVERY_RATE_LIMIT", "1200"))
	if limit == 0 {
		limit = -1
	}
	trust := os.Getenv("TRUST_PROXY") == "1" || os.Getenv("TRUST_PROXY") == "true"
	return cms.Config{DataDir: *data, Addr: *listen, BaseURL: base, SiteKey: os.Getenv("SITE_KEY"), DeliveryRateLimit: limit, TrustProxy: trust}, fs, nil
}

func serve(args []string) error {
	cfg, _, err := common("serve", args, nil)
	if err != nil {
		return err
	}
	cfg.Logger = slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))
	app, err := cms.NewApp(cfg)
	if err != nil {
		return err
	}
	defer app.Close()
	app.Admin = admin.Handler()

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           logRequests(cfg.Logger, app.Handler()),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       5 * time.Minute,
		WriteTimeout:      5 * time.Minute,
		IdleTimeout:       2 * time.Minute,
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shut, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		srv.Shutdown(shut)
	}()
	cfg.Logger.Info("libre publish is up", "version", cms.Version, "admin", cfg.BaseURL+"/cms/", "data", cfg.DataDir, "addr", cfg.Addr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(s int) {
	w.status = s
	w.ResponseWriter.WriteHeader(s)
}

func logRequests(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(sw, r)
		if r.URL.Path != "/up" {
			log.Info("request", "method", r.Method, "path", r.URL.Path, "status", sw.status, "ms", time.Since(start).Milliseconds())
		}
	})
}

func open(name string, args []string, extra func(*flag.FlagSet)) (*cms.App, error) {
	cfg, _, err := common(name, args, extra)
	if err != nil {
		return nil, err
	}
	cfg.Logger = slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn}))
	return cms.NewApp(cfg)
}

func user(args []string) error {
	if len(args) > 0 && (args[0] == "password" || args[0] == "disable-2fa") {
		return userAccount(args[0], args[1:])
	}
	if len(args) == 0 || args[0] != "create" {
		return errors.New("usage: librepublish user create|password|disable-2fa --email … [--name … --password … --role Administrator]")
	}
	var email, name, password, role string
	app, err := open("user create", args[1:], func(fs *flag.FlagSet) {
		fs.StringVar(&email, "email", "", "their email, which they sign in with")
		fs.StringVar(&name, "name", "", "their name")
		fs.StringVar(&password, "password", "", "at least 10 characters")
		fs.StringVar(&role, "role", "Administrator", "the role")
	})
	if err != nil {
		return err
	}
	defer app.Close()
	ctx := context.Background()
	id, err := app.CreateUserWithRole(ctx, name, email, password, role)
	if err != nil {
		return err
	}
	fmt.Printf("Created user %d (%s), %s. Sign in at %s/cms/\n", id, email, role, app.BaseURL)
	return nil
}

// userAccount: a new password for someone locked out, or a second factor
// turned off for an account the Rails core set it up on.
func userAccount(cmd string, args []string) error {
	var email, password string
	app, err := open("user "+cmd, args, func(fs *flag.FlagSet) {
		fs.StringVar(&email, "email", "", "whose account")
		if cmd == "password" {
			fs.StringVar(&password, "password", "", "the new password, at least 10 characters")
		}
	})
	if err != nil {
		return err
	}
	defer app.Close()
	if cmd == "password" {
		if err := app.SetPassword(context.Background(), email, password); err != nil {
			return err
		}
		fmt.Println("Password changed; their sessions were signed out.")
		return nil
	}
	if err := app.DisableTwoFactor(context.Background(), email); err != nil {
		return err
	}
	fmt.Println("Two-factor sign-in is off for", email+". They sign in with their password alone now.")
	return nil
}

func token(args []string) error {
	if len(args) == 0 || args[0] != "create" {
		return errors.New(`usage: librepublish token create --name PRODUCTION [--role "Production site"]`)
	}
	var name, role string
	app, err := open("token create", args[1:], func(fs *flag.FlagSet) {
		fs.StringVar(&name, "name", "PRODUCTION", "what it's for")
		fs.StringVar(&role, "role", "Production site", "the role it acts with")
	})
	if err != nil {
		return err
	}
	defer app.Close()
	plain, err := app.CreateServiceTokenForRole(context.Background(), name, role)
	if err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "Issued %q on %s. It is shown once; keep it in the site's environment, never in a repo.\n", name, role)
	fmt.Println(plain)
	return nil
}

func seedBlocks(args []string) error {
	app, err := open("seed-blocks", args, nil)
	if err != nil {
		return err
	}
	defer app.Close()
	added, err := app.SeedBlockTypes(context.Background(), nil)
	if err != nil {
		return err
	}
	fmt.Printf("Installed %d block types: %s\n", len(added), strings.Join(added, ", "))
	return nil
}
