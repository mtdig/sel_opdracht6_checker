// Package tui implements the Bubble Tea TUI for the checker.
package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mtdig/sel-opdracht6-checker/internal/checks"
)

// -- Styles -----------------------------------------------------------------

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

// -- Messages ---------------------------------------------------------------

type checkStartMsg struct{ index int }
type checkDoneMsg struct {
	index   int
	results []checks.CheckResult
}
type allDoneMsg struct{}

// -- Check group state ------------------------------------------------------

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
}

// -- Model ------------------------------------------------------------------

type Model struct {
	cfg      *checks.Cfg
	version  string
	groups   []checkGroup
	spinner  spinner.Model
	viewport viewport.Model
	current  int
	done     bool
	passed   int
	failed   int
	skipped  int
	quitting bool
	width    int
	height   int
	ready    bool // true once we know the terminal size
}

func NewModel(cfg *checks.Cfg, version string) Model {
	defs := checks.AllChecks()
	groups := make([]checkGroup, len(defs))
	for i, d := range defs {
		groups[i] = checkGroup{def: d, state: groupPending}
	}

	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("205"))

	return Model{
		cfg:     cfg,
		version: version,
		groups:  groups,
		spinner: s,
		current: -1,
	}
}

// ExitCode returns the number of failed checks.
func (m Model) ExitCode() int {
	return m.failed
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(m.spinner.Tick, m.startNext())
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
		m.current = msg.index
		m.groups[msg.index].state = groupRunning
		return m, m.runCheck(msg.index)

	case checkDoneMsg:
		g := &m.groups[msg.index]
		g.state = groupDone
		g.results = msg.results
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
		return m, m.startNext()

	case allDoneMsg:
		m.done = true
		content := m.renderContent()
		m.viewport.SetContent(content)
		// Scroll to the bottom so the summary is visible first
		m.viewport.GotoBottom()
		return m, nil
	}

	return m, nil
}

func (m Model) startNext() tea.Cmd {
	next := -1
	for i, g := range m.groups {
		if g.state == groupPending {
			next = i
			break
		}
	}
	if next == -1 {
		return func() tea.Msg { return allDoneMsg{} }
	}
	idx := next
	return func() tea.Msg { return checkStartMsg{index: idx} }
}

func (m Model) runCheck(index int) tea.Cmd {
	return func() tea.Msg {
		results := m.groups[index].def.RunFunc(m.cfg)
		return checkDoneMsg{index: index, results: results}
	}
}

// renderContent builds the check results text (without banner -- that's a fixed header).
func (m Model) renderContent() string {
	var b strings.Builder

	// Check groups
	lastSection := ""
	for i, g := range m.groups {
		if g.def.Section != lastSection {
			if lastSection != "" {
				b.WriteString("\n")
			}
			b.WriteString(sectionStyle.Render("- "+g.def.Section) + "\n")
			lastSection = g.def.Section
		}

		switch g.state {
		case groupPending:
			b.WriteString(dimStyle.Render(fmt.Sprintf("  - %s", g.def.Name)) + "\n")

		case groupRunning:
			b.WriteString(fmt.Sprintf("  %s %s\n",
				m.spinner.View(), g.def.Name))
			_ = i

		case groupDone:
			for _, r := range g.results {
				switch r.Status {
				case checks.StatusPass:
					b.WriteString(passStyle.Render(fmt.Sprintf("  [PASS] %s", r.Message)) + "\n")
				case checks.StatusFail:
					b.WriteString(failStyle.Render(fmt.Sprintf("  [FAIL] %s", r.Message)) + "\n")
					if r.Detail != "" {
						b.WriteString(detailStyle.Render(r.Detail) + "\n")
					}
				case checks.StatusSkip:
					b.WriteString(skipStyle.Render(fmt.Sprintf("  [SKIP] %s", r.Message)) + "\n")
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
