// Package runner executes all checks and produces a JSON report.
package runner

import (
	"encoding/json"
	"fmt"
	"io"
	"sync"
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
	Proto      string       `json:"proto"`
	Port       string       `json:"port"`
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

// checkResult carries the completed GroupJSON back from a goroutine.
type checkResult struct {
	index int
	group GroupJSON
}

// Run executes all checks concurrently (respecting dependency order),
// printing progress to w (may be io.Discard for silence), and returns
// the full report.
func Run(cfg *checks.Cfg, version string, w io.Writer) *ReportJSON {
	defs := checks.AllChecks()

	report := &ReportJSON{
		Version:   version,
		Target:    cfg.Target,
		User:      cfg.LocalUser,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Checks:    make([]GroupJSON, len(defs)),
	}

	totalStart := time.Now()

	// Build index
	idIndex := make(map[string]int, len(defs))
	for i, d := range defs {
		idIndex[d.ID] = i
	}

	done := make([]bool, len(defs))
	launched := make([]bool, len(defs))
	resultCh := make(chan checkResult, len(defs))

	var mu sync.Mutex // protects w (progress output)

	depsReady := func(def checks.CheckDef) bool {
		for _, dep := range def.Deps {
			if idx, ok := idIndex[dep]; ok && !done[idx] {
				return false
			}
		}
		return true
	}

	launchCheck := func(i int, def checks.CheckDef) {
		launched[i] = true
		go func() {
			mu.Lock()
			fmt.Fprintf(w, "Running: %s ...\n", def.Name)
			mu.Unlock()

			start := time.Now()
			results := def.RunFunc(cfg)
			elapsed := time.Since(start)

			g := GroupJSON{
				ID:         def.ID,
				Name:       def.Name,
				Section:    def.Section,
				Proto:      def.Proto,
				Port:       def.Port,
				Duration:   elapsed.Round(time.Millisecond).String(),
				DurationMs: elapsed.Milliseconds(),
				Results:    make([]ResultJSON, 0, len(results)),
			}
			for _, r := range results {
				g.Results = append(g.Results, ResultJSON{
					Status:  statusString(r.Status),
					Message: r.Message,
					Detail:  r.Detail,
				})
			}
			resultCh <- checkResult{index: i, group: g}
		}()
	}

	// Launch all checks that have no deps.
	for i, def := range defs {
		if depsReady(def) {
			launchCheck(i, def)
		}
	}

	// Process completions and launch newly unblocked checks.
	completed := 0
	for completed < len(defs) {
		cr := <-resultCh
		report.Checks[cr.index] = cr.group
		done[cr.index] = true
		completed++

		// Launch any checks that are now unblocked.
		for i, def := range defs {
			if !launched[i] && depsReady(def) {
				launchCheck(i, def)
			}
		}
	}

	totalElapsed := time.Since(totalStart)
	report.Duration = totalElapsed.Round(time.Millisecond).String()
	report.DurationMs = totalElapsed.Milliseconds()

	for _, g := range report.Checks {
		for _, r := range g.Results {
			switch r.Status {
			case "pass":
				report.Summary.Passed++
			case "fail":
				report.Summary.Failed++
			case "skip":
				report.Summary.Skipped++
			}
		}
	}
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
