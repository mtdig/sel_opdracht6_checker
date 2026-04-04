// Package checks implements all assignment verification checks.
// Each check function returns one or more CheckResult values.
// Check functions have no dependency on any output/TUI layer.
package checks

import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"runtime"
	"strings"
	"time"

	"github.com/mtdig/sel-opdracht6-checker/internal/sshclient"
	"github.com/pkg/sftp"
	probing "github.com/prometheus-community/pro-bing"
)

// -- Result types

type Status int

const (
	StatusPass Status = iota
	StatusFail
	StatusSkip
)

// CheckResult is a single pass/fail/skip outcome.
type CheckResult struct {
	Status  Status
	Message string
	Detail  string // optional extra info shown on failure
}

func pass(msg string) CheckResult         { return CheckResult{StatusPass, msg, ""} }
func fail(msg, detail string) CheckResult { return CheckResult{StatusFail, msg, detail} }
func skip(msg, reason string) CheckResult { return CheckResult{StatusSkip, msg, reason} }

// -- Config

// Cfg holds all runtime configuration.
type Cfg struct {
	Target    string
	LocalUser string

	SSHUser string
	SSHPass string

	MysqlRemoteUser string
	MysqlRemotePass string
	MysqlLocalUser  string
	MysqlLocalPass  string

	WPUser string
	WPPass string

	// Derived URLs
	ApacheURL      string
	WPURL          string
	PortainerURL   string
	VaultwardenURL string
	PlankaURL      string
	MinetestPort   int

	// Runtime state
	SSHClient *sshclient.Client
	SSHOK     bool
}

// NewCfg builds the configuration from the given target/user + secrets map.
func NewCfg(target, localUser string, sec map[string]string) *Cfg {
	return &Cfg{
		Target:          target,
		LocalUser:       localUser,
		SSHUser:         sec["SSH_USER"],
		SSHPass:         sec["SSH_PASS"],
		MysqlRemoteUser: sec["MYSQL_REMOTE_USER"],
		MysqlRemotePass: sec["MYSQL_REMOTE_PASS"],
		MysqlLocalUser:  sec["MYSQL_LOCAL_USER"],
		MysqlLocalPass:  sec["MYSQL_LOCAL_PASS"],
		WPUser:          sec["WP_USER"],
		WPPass:          sec["WP_PASS"],
		ApacheURL:       "https://" + target,
		WPURL:           "http://" + target + ":8080",
		PortainerURL:    "https://" + target + ":9443",
		VaultwardenURL:  "https://" + target + ":4123",
		PlankaURL:       "http://" + target + ":3000",
		MinetestPort:    30000,
	}
}

// CheckDef describes a named check that produces results.
type CheckDef struct {
	ID      string
	Name    string   // human-readable description shown in the TUI
	Section string
	Deps    []string // IDs of checks that must complete before this one
	Proto   string   // protocol tested (ICMP, TCP/SSH, HTTPS, HTTP, TCP, UDP, SSH, SFTP)
	Port    string   // port(s) tested, e.g. "22", "443", "30000/udp", "-" for ICMP
	RunFunc func(c *Cfg) []CheckResult
}

// AllChecks returns the ordered list of all check definitions.
func AllChecks() []CheckDef {
	return []CheckDef{
		// -- No dependencies: run immediately in parallel --
		{ID: "ping", Name: "VM bereikbaar via ICMP ping", Section: "Netwerk", Proto: "ICMP", Port: "-", RunFunc: checkPing},
		{ID: "ssh", Name: "SSH-verbinding op poort 22", Section: "SSH", Proto: "TCP/SSH", Port: "22", RunFunc: checkSSH},
		{ID: "apache", Name: "Apache HTTPS + index.html inhoud", Section: "Apache", Proto: "HTTPS", Port: "443", RunFunc: checkApacheHTTPS},
		{ID: "wp_reachable", Name: "WordPress bereikbaar op poort 8080", Section: "WordPress", Proto: "HTTP", Port: "8080", RunFunc: checkWordPressReachable},
		{ID: "wp_posts", Name: "WordPress minstens 3 posts via REST API", Section: "WordPress", Proto: "HTTP", Port: "8080", RunFunc: checkWordPressPosts},
		{ID: "wp_login", Name: "WordPress login via XML-RPC", Section: "WordPress", Proto: "HTTP", Port: "8080", RunFunc: checkWordPressLogin},
		{ID: "portainer", Name: "Portainer bereikbaar via HTTPS (poort 9443)", Section: "Portainer", Proto: "HTTPS", Port: "9443", RunFunc: checkPortainer},
		{ID: "vaultwarden", Name: "Vaultwarden bereikbaar via HTTPS (poort 4123)", Section: "Vaultwarden", Proto: "HTTPS", Port: "4123", RunFunc: checkVaultwarden},
		{ID: "planka", Name: "Planka bereikbaar + login (poort 3000)", Section: "Planka", Proto: "HTTP", Port: "3000", RunFunc: checkPlanka},

		// -- Depend on SSH --
		{ID: "internet", Name: "Internettoegang vanuit de VM (ping 8.8.8.8)", Section: "Netwerk", Proto: "ICMP", Port: "-", Deps: []string{"ssh"}, RunFunc: checkInternet},
		{ID: "sftp", Name: "SFTP upload + HTTPS roundtrip", Section: "SFTP", Proto: "SFTP", Port: "22", Deps: []string{"ssh"}, RunFunc: checkSFTPUpload},
		{ID: "mysql_remote", Name: "MySQL remote login op poort 3306", Section: "MySQL", Proto: "TCP", Port: "3306", Deps: []string{"ssh"}, RunFunc: checkMySQLRemote},
		{ID: "mysql_local", Name: "MySQL lokaal via SSH", Section: "MySQL", Proto: "SSH", Port: "22", Deps: []string{"ssh"}, RunFunc: checkMySQLLocalViaSSH},
		{ID: "mysql_admin", Name: "MySQL admin niet bereikbaar van buitenaf", Section: "MySQL", Proto: "SSH", Port: "3306", Deps: []string{"ssh"}, RunFunc: checkMySQLAdminNotRemote},
		{ID: "wp_db", Name: "WordPress database wpdb bereikbaar", Section: "WordPress", Proto: "SSH", Port: "22", Deps: []string{"ssh"}, RunFunc: checkWordPressDB},
		{ID: "minetest", Name: "Minetest UDP poort 30000 open", Section: "Minetest", Proto: "UDP", Port: "30000", Deps: []string{"ssh"}, RunFunc: checkMinetest},
		{ID: "docker", Name: "Docker containers, volumes & compose", Section: "Docker", Proto: "SSH", Port: "22", Deps: []string{"ssh"}, RunFunc: checkDockerCompose},
	}
}

// -- HTTP helper

var httpClient = &http.Client{
	Timeout: 5 * time.Second,
	Transport: &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	},
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 10 {
			return fmt.Errorf("too many redirects")
		}
		return nil
	},
}

func httpGet(url string) (int, string, error) {
	resp, err := httpClient.Get(url)
	if err != nil {
		return 0, "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(body), nil
}

// -- SSH helpers

func requireSSH(c *Cfg, name string) ([]CheckResult, bool) {
	if !c.SSHOK {
		return []CheckResult{skip(name, "SSH-verbinding is niet beschikbaar")}, false
	}
	return nil, true
}

func sshRun(c *Cfg, cmd string) (string, error) {
	if c.SSHClient == nil {
		return "", fmt.Errorf("no SSH connection")
	}
	return c.SSHClient.Run(cmd)
}

// -- Check implementations --

func checkPing(c *Cfg) []CheckResult {
	pinger, err := probing.NewPinger(c.Target)
	if err != nil {
		return []CheckResult{fail(
			fmt.Sprintf("VM is niet bereikbaar op %s", c.Target),
			fmt.Sprintf("Kan pinger niet aanmaken: %v", err),
		)}
	}
	pinger.Count = 1
	pinger.Timeout = 5 * time.Second

	// On Windows raw ICMP sockets are required.
	if runtime.GOOS == "windows" {
		pinger.SetPrivileged(true)
	}

	if err := pinger.Run(); err != nil {
		return []CheckResult{fail(
			fmt.Sprintf("VM is niet bereikbaar op %s", c.Target),
			fmt.Sprintf("Ping mislukt: %v", err),
		)}
	}
	stats := pinger.Statistics()
	if stats.PacketsRecv > 0 {
		return []CheckResult{pass(fmt.Sprintf("VM is bereikbaar op %s (ping, %v)", c.Target, stats.AvgRtt))}
	}
	return []CheckResult{fail(
		fmt.Sprintf("VM is niet bereikbaar op %s", c.Target),
		"Ping naar de VM mislukt -- 0 pakketten ontvangen",
	)}
}

func checkSSH(c *Cfg) []CheckResult {
	client, err := sshclient.Dial(c.Target, c.SSHUser, c.SSHPass)
	if err != nil {
		return []CheckResult{fail(
			fmt.Sprintf("SSH-verbinding als %s op poort 22", c.SSHUser),
			fmt.Sprintf("Kan niet inloggen met %s/%s", c.SSHUser, c.SSHPass),
		)}
	}
	out, err := client.Run("echo ok")
	if err != nil || !strings.Contains(out, "ok") {
		client.Close()
		return []CheckResult{fail(
			fmt.Sprintf("SSH-verbinding als %s op poort 22", c.SSHUser),
			fmt.Sprintf("Kan niet inloggen met %s/%s", c.SSHUser, c.SSHPass),
		)}
	}
	c.SSHClient = client
	c.SSHOK = true
	return []CheckResult{pass(fmt.Sprintf("SSH-verbinding als %s op poort 22", c.SSHUser))}
}

func checkInternet(c *Cfg) []CheckResult {
	if r, ok := requireSSH(c, "Internet check"); !ok {
		return r
	}
	result, _ := sshRun(c, "ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && echo ok || echo nok")
	if strings.Contains(result, "ok") {
		return []CheckResult{pass("VM heeft internettoegang")}
	}
	return []CheckResult{fail("VM heeft geen internettoegang", "ping 8.8.8.8 vanuit de VM mislukt")}
}

func checkApacheHTTPS(c *Cfg) []CheckResult {
	var results []CheckResult

	code, body, err := httpGet(c.ApacheURL)
	if err != nil || code < 200 || code >= 400 {
		codeStr := "0"
		if err == nil {
			codeStr = fmt.Sprintf("%d", code)
		}
		return []CheckResult{fail(
			fmt.Sprintf("Apache niet bereikbaar via HTTPS op %s", c.ApacheURL),
			fmt.Sprintf("HTTP status: %s", codeStr),
		)}
	}
	results = append(results, pass(fmt.Sprintf("Apache bereikbaar via HTTPS (HTTP %d)", code)))

	expected := "Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!"
	if strings.Contains(body, expected) {
		results = append(results, pass("index.html bevat de verwachte tekst"))
	} else {
		results = append(results, fail("index.html bevat niet de verwachte tekst",
			fmt.Sprintf("Verwacht: '%s'", expected)))
	}
	return results
}

func checkSFTPUpload(c *Cfg) []CheckResult {
	if r, ok := requireSSH(c, "SFTP upload"); !ok {
		return r
	}

	var results []CheckResult
	remotePath := "/var/www/html/opdracht6.html"
	checkURL := c.ApacheURL + "/opdracht6.html"

	htmlContent := fmt.Sprintf(`<!DOCTYPE html>
<html>
    <head><title>Opdracht 6</title></head>
    <body>
        <h1>SELab Opdracht 6</h1>
        <p>Ingediend door: %s</p>
    </body>
</html>`, c.LocalUser)

	// Upload via SFTP
	sftpClient, err := sftp.NewClient(c.SSHClient.Conn())
	if err != nil {
		return []CheckResult{fail(
			fmt.Sprintf("SFTP upload naar %s", remotePath),
			fmt.Sprintf("SFTP sessie kon niet geopend worden: %v", err),
		)}
	}
	defer sftpClient.Close()

	f, err := sftpClient.Create(remotePath)
	if err != nil {
		return []CheckResult{fail(
			fmt.Sprintf("SFTP upload naar %s", remotePath),
			fmt.Sprintf("Kan bestand niet aanmaken: %v", err),
		)}
	}
	_, err = f.Write([]byte(htmlContent))
	f.Close()
	if err != nil {
		return []CheckResult{fail(
			fmt.Sprintf("SFTP upload naar %s", remotePath),
			fmt.Sprintf("Schrijven mislukt: %v", err),
		)}
	}
	results = append(results, pass(fmt.Sprintf("SFTP upload naar %s als %s", remotePath, c.SSHUser)))

	// chmod 644
	sshRun(c, fmt.Sprintf("chmod 644 %s", remotePath))

	// Fetch via HTTPS
	httpCode, body, err := httpGet(checkURL)
	if err != nil || httpCode < 200 || httpCode >= 400 {
		codeStr := "0"
		if err == nil {
			codeStr = fmt.Sprintf("%d", httpCode)
		}
		results = append(results, fail(
			"opdracht6.html niet bereikbaar via HTTPS",
			fmt.Sprintf("HTTP status: %s", codeStr),
		))
		return results
	}
	results = append(results, pass(fmt.Sprintf("opdracht6.html bereikbaar via HTTPS (HTTP %d)", httpCode)))

	// Roundtrip
	if strings.Contains(body, c.LocalUser) {
		results = append(results, pass(fmt.Sprintf("Roundtrip OK: '%s' gevonden in pagina", c.LocalUser)))
	} else {
		results = append(results, fail(
			fmt.Sprintf("Roundtrip: '%s' niet gevonden in pagina", c.LocalUser),
			"Verwacht jouw username in de pagina-inhoud",
		))
	}
	return results
}

func checkMySQLRemote(c *Cfg) []CheckResult {
	var results []CheckResult

	addr := net.JoinHostPort(c.Target, "3306")
	conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		return []CheckResult{fail(
			fmt.Sprintf("MySQL niet bereikbaar op %s:3306", c.Target),
			"Controleer of remote access is ingeschakeld",
		)}
	}
	conn.Close()
	results = append(results, pass(fmt.Sprintf("MySQL bereikbaar op %s:3306 als %s", c.Target, c.MysqlRemoteUser)))

	if c.SSHOK {
		result, err := sshRun(c, fmt.Sprintf(
			"mysql -u %s -p'%s' appdb -e 'SELECT 1;' 2>/dev/null",
			c.MysqlRemoteUser, c.MysqlRemotePass,
		))
		if err == nil && strings.Contains(result, "1") {
			results = append(results, pass(fmt.Sprintf("Database appdb bereikbaar als %s", c.MysqlRemoteUser)))
		} else {
			results = append(results, fail(
				fmt.Sprintf("Database appdb niet bereikbaar als %s", c.MysqlRemoteUser),
				"Controleer of database appdb bestaat en gebruiker toegang heeft",
			))
		}
	} else {
		results = append(results, skip("Database appdb", "Geen SSH voor login-validatie"))
	}
	return results
}

func checkMySQLLocalViaSSH(c *Cfg) []CheckResult {
	if r, ok := requireSSH(c, "MySQL lokaal via SSH"); !ok {
		return r
	}
	result, _ := sshRun(c, fmt.Sprintf(
		"mysql -u %s -p'%s' -e 'SELECT 1;' 2>/dev/null",
		c.MysqlLocalUser, c.MysqlLocalPass,
	))
	if strings.Contains(result, "1") {
		return []CheckResult{pass(fmt.Sprintf("MySQL lokaal bereikbaar via SSH als %s", c.MysqlLocalUser))}
	}
	return []CheckResult{fail(
		fmt.Sprintf("MySQL lokaal niet bereikbaar als %s", c.MysqlLocalUser),
		"Controleer of admin gebruiker bestaat met juiste rechten",
	)}
}

func checkMySQLAdminNotRemote(c *Cfg) []CheckResult {
	if !c.SSHOK {
		return []CheckResult{skip("MySQL admin remote check", "SSH-verbinding is niet beschikbaar")}
	}

	result, _ := sshRun(c, fmt.Sprintf(
		"mysql -h %s -P 3306 -u %s -p'%s' -e 'SELECT 1;' 2>&1",
		c.Target, c.MysqlLocalUser, c.MysqlLocalPass,
	))
	if strings.Contains(result, "Access denied") || strings.Contains(result, "ERROR") || !strings.Contains(result, "1") {
		return []CheckResult{pass("MySQL admin is niet bereikbaar van buitenaf (correct)")}
	}
	return []CheckResult{fail("MySQL admin is bereikbaar van buitenaf", "Zou alleen lokaal mogen zijn")}
}

func checkWordPressReachable(c *Cfg) []CheckResult {
	code, _, err := httpGet(c.WPURL)
	if err == nil && code >= 200 && code < 400 {
		return []CheckResult{pass(fmt.Sprintf("WordPress bereikbaar op %s (HTTP %d)", c.WPURL, code))}
	}
	codeStr := "0"
	if err == nil {
		codeStr = fmt.Sprintf("%d", code)
	}
	return []CheckResult{fail(
		fmt.Sprintf("WordPress niet bereikbaar op %s", c.WPURL),
		fmt.Sprintf("HTTP status: %s", codeStr),
	)}
}

func checkWordPressPosts(c *Cfg) []CheckResult {
	_, body, err := httpGet(c.WPURL + "/?rest_route=/wp/v2/posts")
	if err != nil {
		return []CheckResult{fail("WordPress posts ophalen mislukt", err.Error())}
	}
	var posts []json.RawMessage
	if err := json.Unmarshal([]byte(body), &posts); err != nil {
		return []CheckResult{fail("WordPress posts ophalen mislukt", "Ongeldig JSON antwoord")}
	}
	if len(posts) > 2 {
		return []CheckResult{pass(fmt.Sprintf("Minstens 3 posts (%d gevonden)", len(posts)))}
	}
	return []CheckResult{fail("Niet genoeg posts",
		fmt.Sprintf("Slechts %d gevonden, minstens 3 verwacht", len(posts)))}
}

func checkWordPressLogin(c *Cfg) []CheckResult {
	xmlPayload := fmt.Sprintf(`<?xml version='1.0'?>
<methodCall>
  <methodName>wp.getUsersBlogs</methodName>
  <params>
    <param><value>%s</value></param>
    <param><value>%s</value></param>
  </params>
</methodCall>`, c.WPUser, c.WPPass)

	resp, err := httpClient.Post(c.WPURL+"/xmlrpc.php", "text/xml", strings.NewReader(xmlPayload))
	if err != nil {
		return []CheckResult{fail(
			fmt.Sprintf("WordPress login als %s mislukt", c.WPUser),
			"Controleer gebruiker/wachtwoord of XML-RPC beschikbaarheid",
		)}
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	if strings.Contains(string(body), "blogid") {
		return []CheckResult{pass(fmt.Sprintf("WordPress login als %s", c.WPUser))}
	}
	return []CheckResult{fail(
		fmt.Sprintf("WordPress login als %s mislukt", c.WPUser),
		"Controleer gebruiker/wachtwoord of XML-RPC beschikbaarheid",
	)}
}

func checkWordPressDB(c *Cfg) []CheckResult {
	if r, ok := requireSSH(c, "WordPress database check"); !ok {
		return r
	}
	result, _ := sshRun(c, fmt.Sprintf(
		"mysql -u %s -p'%s' wpdb -e 'SELECT 1;' 2>/dev/null",
		c.WPUser, c.WPPass,
	))
	if strings.Contains(result, "1") {
		return []CheckResult{pass("Database wpdb bestaat en is bereikbaar")}
	}
	return []CheckResult{fail("Database wpdb niet bereikbaar",
		fmt.Sprintf("Controleer of wpdb bestaat en %s toegang heeft", c.WPUser))}
}

func checkPortainer(c *Cfg) []CheckResult {
	code, _, err := httpGet(c.PortainerURL)
	if err == nil && code >= 200 && code < 400 {
		return []CheckResult{pass(fmt.Sprintf("Portainer bereikbaar via HTTPS (HTTP %d)", code))}
	}
	codeStr := "0"
	if err == nil {
		codeStr = fmt.Sprintf("%d", code)
	}
	return []CheckResult{fail("Portainer niet bereikbaar", fmt.Sprintf("HTTP status: %s", codeStr))}
}

func checkVaultwarden(c *Cfg) []CheckResult {
	code, _, err := httpGet(c.VaultwardenURL)
	if err == nil && code >= 200 && code < 400 {
		return []CheckResult{pass(fmt.Sprintf("Vaultwarden bereikbaar via HTTPS (HTTP %d)", code))}
	}
	codeStr := "0"
	if err == nil {
		codeStr = fmt.Sprintf("%d", code)
	}
	return []CheckResult{fail("Vaultwarden niet bereikbaar", fmt.Sprintf("HTTP status: %s", codeStr))}
}

func checkMinetest(c *Cfg) []CheckResult {
	if r, ok := requireSSH(c, "Minetest check"); !ok {
		return r
	}

	// Check if the container is running and listening on the expected port
	out, _ := sshRun(c, "docker ps --filter name=minetest --format '{{.Ports}}' 2>/dev/null")
	if strings.Contains(out, fmt.Sprintf("%d", c.MinetestPort)) {
		return []CheckResult{pass(fmt.Sprintf("Minetest container draait op UDP poort %d", c.MinetestPort))}
	}

	// Fallback: check if the container is running at all
	names, _ := sshRun(c, "docker ps --format '{{.Names}}' 2>/dev/null")
	if strings.Contains(strings.ToLower(names), "minetest") {
		return []CheckResult{pass("Minetest container draait (poort niet bevestigd)")}
	}

	return []CheckResult{fail(
		fmt.Sprintf("Minetest container niet gevonden op UDP poort %d", c.MinetestPort),
		"Controleer of de Minetest container draait",
	)}
}

func checkPlanka(c *Cfg) []CheckResult {
	var results []CheckResult

	code, _, err := httpGet(c.PlankaURL)
	if err == nil && code >= 200 && code < 400 {
		results = append(results, pass(fmt.Sprintf("Planka bereikbaar (HTTP %d)", code)))
	} else {
		codeStr := "0"
		if err == nil {
			codeStr = fmt.Sprintf("%d", code)
		}
		return []CheckResult{fail("Planka niet bereikbaar", fmt.Sprintf("HTTP status: %s", codeStr))}
	}

	loginPayload := `{"emailOrUsername":"troubleshoot@selab.hogent.be","password":"shoot"}`
	resp, err := httpClient.Post(c.PlankaURL+"/api/access-tokens", "application/json",
		strings.NewReader(loginPayload))
	if err != nil {
		results = append(results, fail("Planka login mislukt", "Controleer gebruiker/wachtwoord"))
		return results
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	var jsonResult map[string]interface{}
	if err := json.Unmarshal(body, &jsonResult); err == nil {
		if _, ok := jsonResult["item"]; ok {
			results = append(results, pass("Planka login als troubleshoot@selab.hogent.be"))
			return results
		}
	}
	results = append(results, fail("Planka login mislukt", "Controleer gebruiker/wachtwoord"))
	return results
}

func checkDockerCompose(c *Cfg) []CheckResult {
	if r, ok := requireSSH(c, "Docker compose check"); !ok {
		return r
	}

	var results []CheckResult
	containers, _ := sshRun(c, "docker ps --format '{{.Names}}' 2>/dev/null")
	lcContainers := strings.ToLower(containers)

	for _, svc := range []string{"vaultwarden", "minetest", "portainer"} {
		if strings.Contains(lcContainers, svc) {
			results = append(results, pass(fmt.Sprintf("Container %s draait", svc)))
		} else {
			results = append(results, fail(fmt.Sprintf("Container %s draait niet", svc), ""))
		}
	}

	if strings.Contains(lcContainers, "planka") {
		results = append(results, pass("Container planka draait"))
	} else {
		results = append(results, fail("Container planka draait niet", ""))
	}

	vwMount, _ := sshRun(c, "docker inspect $(docker ps -q --filter name=vaultwarden) --format '{{json .Mounts}}' 2>/dev/null")
	if strings.Contains(vwMount, `"Type":"bind"`) {
		results = append(results, pass("Vaultwarden: lokale map (bind mount)"))
	} else {
		results = append(results, fail("Vaultwarden: geen bind mount voor data", ""))
	}

	mtMount, _ := sshRun(c, "docker inspect $(docker ps -q --filter name=minetest) --format '{{json .Mounts}}' 2>/dev/null")
	if strings.Contains(mtMount, `"Type":"bind"`) {
		results = append(results, pass("Minetest: lokale map (bind mount)"))
	} else {
		results = append(results, fail("Minetest: geen bind mount voor data", ""))
	}

	ptMount, _ := sshRun(c, "docker inspect $(docker ps -q --filter name=portainer) --format '{{json .Mounts}}' 2>/dev/null")
	if strings.Contains(ptMount, `"Type":"volume"`) {
		results = append(results, pass("Portainer: Docker volume"))
	} else {
		results = append(results, fail("Portainer: geen Docker volume voor data", ""))
	}

	plankaCompose, _ := sshRun(c, "test -f ~/docker/planka/docker-compose.yml && echo ok || test -f ~/docker/planka/compose.yml && echo ok || echo nok")
	if strings.Contains(plankaCompose, "ok") {
		results = append(results, pass("Planka compose in ~/docker/planka/"))
	} else {
		results = append(results, fail("Geen compose in ~/docker/planka/",
			"Verwacht docker-compose.yml of compose.yml"))
	}

	return results
}
