// Package runner executes all checks and produces a JSON report.
package runner

import (
	"encoding/json"
	"fmt"
	"io"
	"time"

	"github.com/mtdig/sel-opdracht6-checker/internal/checks"
)

// ResultJSON is a single check outcome in JSON form.
type ResultJSON struct {
	Status  string `json:"status"`
	Message string `json:"message"`
	Detail  string `json:"detail,omitempty"`
}

// GroupJSON is one check group (e.g. "ping", "ssh") with all its results.
type GroupJSON struct {
	ID         string       `json:"id"`
	Name       string       `json:"name"`
	Section    string       `json:"section"`
	Duration   string       `json:"duration"`
	DurationMs int64        `json:"duration_ms"`
	Results    []ResultJSON `json:"results"`
}

// SummaryJSON holds the final tallies.
type SummaryJSON struct {
	Total   int `json:"total"`
	Passed  int `json:"passed"`
	Failed  int `json:"failed"`
	Skipped int `json:"skipped"`
}

// ReportJSON is the top-level JSON output.
type ReportJSON struct {
	Version    string      `json:"version"`
	Target     string      `json:"target"`
	User       string      `json:"user"`
	Timestamp  string      `json:"timestamp"`
	Duration   string      `json:"duration"`
	DurationMs int64       `json:"duration_ms"`
	Summary    SummaryJSON `json:"summary"`
	Checks     []GroupJSON `json:"checks"`
}

// Run executes every check group sequentially, printing progress to w (may be
// io.Discard for silence), and returns the full report.
func Run(cfg *checks.Cfg, version string, w io.Writer) *ReportJSON {
	defs := checks.AllChecks()

	report := &ReportJSON{
		Version:   version,
		Target:    cfg.Target,
		User:      cfg.LocalUser,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Checks:    make([]GroupJSON, 0, len(defs)),
	}

	totalStart := time.Now()

	for _, def := range defs {
		fmt.Fprintf(w, "Running: %s ...\n", def.Name)

		start := time.Now()
		results := def.RunFunc(cfg)
		elapsed := time.Since(start)

		g := GroupJSON{
			ID:         def.ID,
			Name:       def.Name,
			Section:    def.Section,
			Duration:   elapsed.Round(time.Millisecond).String(),
			DurationMs: elapsed.Milliseconds(),
			Results:    make([]ResultJSON, 0, len(results)),
		}

		for _, r := range results {
			rj := ResultJSON{
				Status:  statusString(r.Status),
				Message: r.Message,
				Detail:  r.Detail,
			}
			g.Results = append(g.Results, rj)

			switch r.Status {
			case checks.StatusPass:
				report.Summary.Passed++
			case checks.StatusFail:
				report.Summary.Failed++
			case checks.StatusSkip:
				report.Summary.Skipped++
			}
		}

		report.Checks = append(report.Checks, g)
	}

	totalElapsed := time.Since(totalStart)
	report.Duration = totalElapsed.Round(time.Millisecond).String()
	report.DurationMs = totalElapsed.Milliseconds()
	report.Summary.Total = report.Summary.Passed + report.Summary.Failed + report.Summary.Skipped

	return report
}

// JSON marshals the report to indented JSON.
func (r *ReportJSON) JSON() ([]byte, error) {
	return json.MarshalIndent(r, "", "  ")
}

func statusString(s checks.Status) string {
	switch s {
	case checks.StatusPass:
		return "pass"
	case checks.StatusFail:
		return "fail"
	case checks.StatusSkip:
		return "skip"
	default:
		return "unknown"
	}
}
