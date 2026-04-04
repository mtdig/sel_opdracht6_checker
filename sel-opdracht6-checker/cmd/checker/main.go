package main

import (
	_ "embed"
	"fmt"
	"os"
	"os/user"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mtdig/sel-opdracht6-checker/internal/checks"
	"github.com/mtdig/sel-opdracht6-checker/internal/secrets"
	"github.com/mtdig/sel-opdracht6-checker/internal/tui"
)

//go:embed secrets.env.enc
var embeddedSecrets []byte

// Version is set at build time via -ldflags.
var Version = "dev"

func main() {
	// -- Version flag --------------------------------------------------
	if len(os.Args) > 1 && (os.Args[1] == "--version" || os.Args[1] == "-v") {
		fmt.Println(Version)
		os.Exit(0)
	}

	target := envOr("TARGET", "192.168.56.20")
	localUser := envOr("LOCAL_USER", currentUser())
	decryptPass := os.Getenv("DECRYPT_PASS")

	// -- Validate inputs ------------------------------------------------
	if decryptPass == "" {
		fmt.Fprintln(os.Stderr, "ERROR: DECRYPT_PASS is not set.")
		fmt.Fprintln(os.Stderr, "Pass the decryption passphrase as an environment variable:")
		fmt.Fprintln(os.Stderr, `  DECRYPT_PASS="..." sel-opdracht6-checker`)
		os.Exit(1)
	}

	requiredKeys := []string{
		"SSH_USER", "SSH_PASS",
		"MYSQL_REMOTE_USER", "MYSQL_REMOTE_PASS",
		"MYSQL_LOCAL_USER", "MYSQL_LOCAL_PASS",
		"WP_USER", "WP_PASS",
	}

	// -- Load secrets: SECRETS_FILE overrides embedded ------------------
	var sec map[string]string
	var err error

	if path := os.Getenv("SECRETS_FILE"); path != "" {
		sec, err = secrets.LoadSecrets(path, decryptPass, requiredKeys)
	} else {
		sec, err = secrets.LoadSecretsFromBytes(embeddedSecrets, decryptPass, requiredKeys)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: %v\n", err)
		os.Exit(1)
	}

	// -- Build config & run TUI -----------------------------------------
	cfg := checks.NewCfg(target, localUser, sec)

	model := tui.NewModel(cfg, Version)
	p := tea.NewProgram(model, tea.WithAltScreen())
	finalModel, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "TUI error: %v\n", err)
		os.Exit(1)
	}

	// Clean exit with the final model's exit code
	if m, ok := finalModel.(tui.Model); ok {
		os.Exit(m.ExitCode())
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func currentUser() string {
	if u, err := user.Current(); err == nil {
		return u.Username
	}
	return "unknown"
}
