// Package tui implements the Bubble Tea TUI for the checker.
package tui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mtdig/sel-opdracht6-checker/internal/checks"
)

var (
	bannerStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("15")).
			Background(lipgloss.Color("99")).
			Padding(0, 1)
	sectionStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("12"))
	passStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("10"))
	failStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("9"))
	skipStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("11"))
	detailStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("11")).PaddingLeft(10)
	dimStyle     = lipgloss.NewStyle().Faint(true)
	summaryBox   = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("99")).
			Padding(1, 3).
			MarginTop(1)
)

type checkStartMsg struct{ index int }
type checkDoneMsg struct {
	index   int
	results []checks.CheckResult
	elapsed time.Duration
}
type allDoneMsg struct{}

type groupState int

const (
	groupPending groupState = iota
	groupRunning
	groupDone
)

type checkGroup struct {
	def     checks.CheckDef
	state   groupState
	results []checks.CheckResult
	elapsed time.Duration
}

type Model struct {
	cfg          *checks.Cfg
	version      string
	groups       []checkGroup
	idIndex      map[string]int // check ID -> index in groups
	spinner      spinner.Model
	viewport     viewport.Model
	running      int // number of currently running checks
	done         bool
	passed       int
	failed       int
	skipped      int
	quitting     bool
	width        int
	height       int
	ready        bool // true once we know the terminal size
	totalStart   time.Time
	totalElapsed time.Duration
}

func NewModel(cfg *checks.Cfg, version string) Model {
	defs := checks.AllChecks()
	groups := make([]checkGroup, len(defs))
	idIndex := make(map[string]int, len(defs))
	for i, d := range defs {
		groups[i] = checkGroup{def: d, state: groupPending}
		idIndex[d.ID] = i
	}

	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("205"))

	return Model{
		cfg:        cfg,
		version:    version,
		groups:     groups,
		idIndex:    idIndex,
		spinner:    s,
		totalStart: time.Now(),
	}
}

// ExitCode returns the number of failed checks.
func (m Model) ExitCode() int {
	return m.failed
}

func (m Model) Init() tea.Cmd {
	cmds := []tea.Cmd{m.spinner.Tick}
	cmds = append(cmds, m.launchReady()...)
	return tea.Batch(cmds...)
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		// Reserve lines for fixed header (banner + blank) and footer
		const headerLines = 2 // banner + empty line
		const footerLines = 1
		vpHeight := msg.Height - headerLines - footerLines
		if vpHeight < 1 {
			vpHeight = 1
		}
		if !m.ready {
			m.viewport = viewport.New(msg.Width, vpHeight)
			m.ready = true
		} else {
			m.viewport.Width = msg.Width
			m.viewport.Height = vpHeight
		}
		if m.done {
			m.viewport.SetContent(m.renderContent())
		}
		return m, nil

	case tea.KeyMsg:
		if m.done {
			// In done state: scroll keys navigate, anything else quits
			key := msg.String()
			switch key {
			case "up", "down", "pgup", "pgdown", "home", "end",
				"k", "j", "u", "d":
				var cmd tea.Cmd
				m.viewport, cmd = m.viewport.Update(msg)
				return m, cmd
			default:
				m.quitting = true
				return m, tea.Quit
			}
		}
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		}

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case checkStartMsg:
		m.groups[msg.index].state = groupRunning
		m.running++
		return m, m.runCheck(msg.index)

	case checkDoneMsg:
		g := &m.groups[msg.index]
		g.state = groupDone
		g.results = msg.results
		g.elapsed = msg.elapsed
		m.running--
		for _, r := range msg.results {
			switch r.Status {
			case checks.StatusPass:
				m.passed++
			case checks.StatusFail:
				m.failed++
			case checks.StatusSkip:
				m.skipped++
			}
		}
		// Launch any checks whose deps are now satisfied
		cmds := m.launchReady()
		if m.running == 0 && len(cmds) == 0 {
			cmds = append(cmds, func() tea.Msg { return allDoneMsg{} })
		}
		return m, tea.Batch(cmds...)

	case allDoneMsg:
		m.done = true
		m.totalElapsed = time.Since(m.totalStart)
		content := m.renderContent()
		m.viewport.SetContent(content)
		// Scroll to the bottom so the summary is visible first
		m.viewport.GotoBottom()
		return m, nil
	}

	return m, nil
}

// launchReady returns Cmds for all pending checks whose dependencies are met.
func (m Model) launchReady() []tea.Cmd {
	var cmds []tea.Cmd
	for i, g := range m.groups {
		if g.state != groupPending {
			continue
		}
		if m.depsReady(g.def.Deps) {
			idx := i
			cmds = append(cmds, func() tea.Msg { return checkStartMsg{index: idx} })
		}
	}
	return cmds
}

// depsReady returns true if every dep ID is in groupDone state.
func (m Model) depsReady(deps []string) bool {
	for _, id := range deps {
		idx, ok := m.idIndex[id]
		if !ok || m.groups[idx].state != groupDone {
			return false
		}
	}
	return true
}

func (m Model) runCheck(index int) tea.Cmd {
	return func() tea.Msg {
		start := time.Now()
		results := m.groups[index].def.RunFunc(m.cfg)
		elapsed := time.Since(start)
		return checkDoneMsg{index: index, results: results, elapsed: elapsed}
	}
}

// renderContent builds the check results text (without banner -- that's a fixed header).
func (m Model) renderContent() string {
	var b strings.Builder

	// Check groups
	lastSection := ""
	for _, g := range m.groups {
		if g.def.Section != lastSection {
			if lastSection != "" {
				b.WriteString("\n")
			}
			b.WriteString(sectionStyle.Render("- "+g.def.Section) + "\n")
			lastSection = g.def.Section
		}

		// Proto:port tag for this check
		var tag string
		if g.def.Proto != "" {
			if g.def.Port != "" && g.def.Port != "-" {
				tag = fmt.Sprintf(" [%s:%s]", g.def.Proto, g.def.Port)
			} else {
				tag = fmt.Sprintf(" [%s]", g.def.Proto)
			}
		}

		switch g.state {
		case groupPending:
			b.WriteString(dimStyle.Render(fmt.Sprintf("  - %s%s", g.def.Name, tag)) + "\n")

		case groupRunning:
			b.WriteString(fmt.Sprintf("  %s %s%s\n",
				m.spinner.View(), g.def.Name, dimStyle.Render(tag)))

		case groupDone:
			timing := dimStyle.Render(fmt.Sprintf(" (%s)", g.elapsed.Round(time.Millisecond)))
			for i, r := range g.results {
				// Show timing + tag on the first result line of each group
				suffix := ""
				if i == 0 {
					suffix = dimStyle.Render(tag) + timing
				}
				switch r.Status {
				case checks.StatusPass:
					b.WriteString(passStyle.Render(fmt.Sprintf("  [PASS] %s", r.Message)) + suffix + "\n")
				case checks.StatusFail:
					b.WriteString(failStyle.Render(fmt.Sprintf("  [FAIL] %s", r.Message)) + suffix + "\n")
					if r.Detail != "" {
						b.WriteString(detailStyle.Render(r.Detail) + "\n")
					}
				case checks.StatusSkip:
					b.WriteString(skipStyle.Render(fmt.Sprintf("  [SKIP] %s", r.Message)) + suffix + "\n")
					if r.Detail != "" {
						b.WriteString(detailStyle.Render(r.Detail) + "\n")
					}
				}
			}
		}
	}

	// Summary
	if m.done {
		total := m.passed + m.failed + m.skipped
		var sl []string
		sl = append(sl, lipgloss.NewStyle().Bold(true).Render("Resultaat"))
		sl = append(sl, "")
		sl = append(sl, fmt.Sprintf(
			"Totaal: %d   %s   %s",
			total,
			passStyle.Render(fmt.Sprintf("Geslaagd: %d", m.passed)),
			failStyle.Render(fmt.Sprintf("Gefaald: %d", m.failed)),
		))
		if m.skipped > 0 {
			sl = append(sl, skipStyle.Render(fmt.Sprintf("Overgeslagen: %d", m.skipped)))
		}
		sl = append(sl, dimStyle.Render(fmt.Sprintf("Totale tijd: %s", m.totalElapsed.Round(time.Millisecond))))
		sl = append(sl, "")
		if m.failed == 0 {
			sl = append(sl, passStyle.Bold(true).Render("Alle checks geslaagd!"))
		} else {
			sl = append(sl, failStyle.Render(fmt.Sprintf("%d checks gefaald", m.failed)))
		}
		b.WriteString("\n")
		b.WriteString(summaryBox.Render(strings.Join(sl, "\n")))
		b.WriteString("\n")
	}

	return b.String()
}

// renderBanner returns the fixed header bar.
func (m Model) renderBanner() string {
	title := fmt.Sprintf(" SELab Opdracht 6 Checker v%s -- %s (user: %s) ",
		m.version, m.cfg.Target, m.cfg.LocalUser)
	bar := bannerStyle.Width(m.width).Render(title)
	return bar
}

func (m Model) View() string {
	if m.quitting {
		return ""
	}

	banner := m.renderBanner()

	// While checks are running: fixed banner + live content
	if !m.done {
		return banner + "\n" + m.renderContent()
	}

	// When done: fixed banner + scrollable viewport + footer
	footer := dimStyle.Render("up/down to scroll, any other key to quit")
	return banner + "\n" + m.viewport.View() + "\n" + footer
}
