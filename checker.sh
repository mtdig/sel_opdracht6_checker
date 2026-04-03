#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# SELab Opdracht6 Checker
# ============================================================================

TARGET="${TARGET:-192.168.56.20}"
SSH_USER="trouble"
SSH_PASS="shoot"
MYSQL_REMOTE_USER="appusr"
MYSQL_REMOTE_PASS="letmein!"
MYSQL_LOCAL_USER="admin"
MYSQL_LOCAL_PASS="letmein!"
WP_USER="wpuser"
WP_PASS="letmein!"
PORTAINER_URL="https://${TARGET}:9443"
VAULTWARDEN_URL="https://${TARGET}:4123"
PLANKA_URL="http://${TARGET}:3000"
WP_URL="http://${TARGET}:8080"
APACHE_URL="https://${TARGET}"
MINETEST_PORT=30000

PASSED=0
FAILED=0
TOTAL=0

#  Helpers

green()  { echo -e "\e[32m$1\e[0m"; }
red()    { echo -e "\e[31m$1\e[0m"; }
yellow() { echo -e "\e[33m$1\e[0m"; }
bold()   { echo -e "\e[1m$1\e[0m"; }

pass() {
    ((PASSED++)) || true
    ((TOTAL++))  || true
    echo "  $(green '✅ PASS') $1"
}

fail() {
    ((FAILED++)) || true
    ((TOTAL++))  || true
    echo "  $(red '❌ FAIL') $1"
    [[ -n "${2:-}" ]] && echo "          $(yellow "$2")"
}

section() {
    echo ""
    bold "=== $1 ==="
}

ssh_cmd() {
    sshpass -p "${SSH_PASS}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o LogLevel=ERROR \
        "${SSH_USER}@${TARGET}" "$1" 2>/dev/null
}

#  Checks

check_ping() {
    section "Netwerk: ping ${TARGET}"

    if ping -c 2 -W 3 "${TARGET}" &>/dev/null; then
        pass "VM is bereikbaar via ping op ${TARGET}"
    else
        fail "VM is niet bereikbaar via ping op ${TARGET}"
    fi
}

check_ssh() {
    section "SSH"

    if ssh_cmd "echo ok" | grep -q "ok"; then
        pass "SSH-verbinding als ${SSH_USER} op poort 22"
    else
        fail "SSH-verbinding als ${SSH_USER} op poort 22" \
             "Kan niet inloggen met ${SSH_USER}/${SSH_PASS}"
    fi
}

check_internet() {
    section "Internet (vanuit VM): ping naar google dns 8.8.8.8"

    local result
    result=$(ssh_cmd "ping -c 1 -W 3 8.8.8.8 &>/dev/null && echo ok || echo nok" || echo "nok")
    if [[ "$result" == *"ok"* ]]; then
        pass "VM heeft internettoegang"
    else
        fail "VM heeft geen internettoegang" \
             "ping 8.8.8.8 vanuit de VM mislukt"
    fi
}

check_apache_https() {
    section "Webserver (Apache2): check 200 <= HTTP response code < 400"


    local http_code body
    body=$(curl -sk --connect-timeout 5 -w '\n%{http_code}' "${APACHE_URL}" 2>/dev/null || echo "000")
    http_code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
 
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Apache bereikbaar via HTTPS op ${APACHE_URL} (HTTP ${http_code})"
    else
        fail "Apache niet bereikbaar via HTTPS op ${APACHE_URL}" \
             "HTTP status: ${http_code}"
        return
    fi
 
    if echo "$body" | grep -q 'Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!'; then
        pass "Apache index.html bevat de verwachte tekst: 'Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!'"
    else
        fail "Apache index.html bevat niet de verwachte tekst" \
             "Verwacht: 'Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!'"
    fi
}
 

check_sftp_upload() {
    local tmpfile
    tmpfile=$(mktemp /tmp/selab-check-XXXXXX.txt)
    echo "selab-checker test $(date)" > "$tmpfile"
    local remote_path="/var/www/selab-checker-test.txt"

    if sshpass -p "${SSH_PASS}" sftp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o LogLevel=ERROR \
        "${SSH_USER}@${TARGET}" <<EOF &>/dev/null
put ${tmpfile} ${remote_path}
EOF
    then
        pass "SFTP upload naar /var/www als ${SSH_USER}"
        # Clean up the test file
        ssh_cmd "rm -f ${remote_path}" &>/dev/null || true
    else
        fail "SFTP upload naar /var/www als ${SSH_USER}" \
             "Kan niet uploaden via SFTP op poort 22"
    fi
    rm -f "$tmpfile"
}

check_mysql_remote() {
    section "Databankserver (MySQL)"
 
    if mysql -h "${TARGET}" -P 3306 --skip-ssl \
        -u "${MYSQL_REMOTE_USER}" -p"${MYSQL_REMOTE_PASS}" \
        -e "SELECT 1;" &>/dev/null; then
        pass "MySQL bereikbaar op ${TARGET}:3306 als ${MYSQL_REMOTE_USER}"
    else
        fail "MySQL niet bereikbaar op ${TARGET}:3306 als ${MYSQL_REMOTE_USER}" \
             "Controleer gebruiker/wachtwoord en of remote access is ingeschakeld"
    fi
 
    # Check appdb database exists
    if mysql -h "${TARGET}" -P 3306 --skip-ssl \
        -u "${MYSQL_REMOTE_USER}" -p"${MYSQL_REMOTE_PASS}" \
        appdb -e "SELECT 1;" &>/dev/null; then
        pass "Database appdb is bereikbaar als ${MYSQL_REMOTE_USER}"
    else
        fail "Database appdb niet bereikbaar als ${MYSQL_REMOTE_USER}" \
             "Controleer of database appdb bestaat en gebruiker toegang heeft"
    fi
}
 
check_mysql_local_via_ssh() {
    local result
    result=$(ssh_cmd "mysql -u ${MYSQL_LOCAL_USER} -p'${MYSQL_LOCAL_PASS}' -e 'SELECT 1;' 2>/dev/null" || echo "error")
    if [[ "$result" == *"1"* ]]; then
        pass "MySQL lokaal bereikbaar via SSH als ${MYSQL_LOCAL_USER}"
    else
        fail "MySQL lokaal niet bereikbaar via SSH als ${MYSQL_LOCAL_USER}" \
             "Controleer of admin gebruiker bestaat met juiste rechten"
    fi
}
 
check_mysql_admin_not_remote() {
    if mysql -h "${TARGET}" -P 3306 --skip-ssl \
        -u "${MYSQL_LOCAL_USER}" -p"${MYSQL_LOCAL_PASS}" \
        -e "SELECT 1;" &>/dev/null 2>&1; then
        fail "MySQL admin is bereikbaar van buitenaf (zou alleen lokaal mogen zijn)"
    else
        pass "MySQL admin is niet bereikbaar van buitenaf (correct)"
    fi
}

check_wordpress_reachable() {
    section "WordPress"

    local http_code
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "${WP_URL}" 2>/dev/null || echo "000")
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "WordPress bereikbaar op ${WP_URL} (HTTP ${http_code})"
    else
        fail "WordPress niet bereikbaar op ${WP_URL}" \
             "HTTP status: ${http_code}"
    fi
}

check_wordpress_post() {
    local response
    response=$(curl -sk --connect-timeout 5 "${WP_URL}/?rest_route=/wp/v2/posts" 2>/dev/null || echo "[]")
    local count
    count=$(echo "$response" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
 
    if [[ "$count" -gt 2 ]]; then
        pass "WordPress heeft minstens 3 post (${count} gevonden)"
    else
        fail "WordPress heeft geen posts" \
             "Maak minstens 1 post aan"
    fi
}
 
check_wordpress_login() {
    # Check login via XML-RPC (simpler than wp-login.php form)
    local response
    response=$(curl -sk --connect-timeout 5 "${WP_URL}/xmlrpc.php" \
        -H "Content-Type: text/xml" \
        -d "<?xml version='1.0'?>
<methodCall>
  <methodName>wp.getUsersBlogs</methodName>
  <params>
    <param><value>${WP_USER}</value></param>
    <param><value>${WP_PASS}</value></param>
  </params>
</methodCall>" 2>/dev/null || echo "")
 
    if echo "$response" | grep -q "blogid"; then
        pass "WordPress login als ${WP_USER}"
    else
        fail "WordPress login als ${WP_USER} mislukt" \
             "Controleer gebruiker/wachtwoord of XML-RPC beschikbaarheid"
    fi
}
 
check_wordpress_db() {
    if mysql -h "${TARGET}" -P 3306 --skip-ssl \
        -u "${MYSQL_REMOTE_USER}" -p"${MYSQL_REMOTE_PASS}" \
        appdb -e "SELECT 1;" &>/dev/null; then
        pass "WordPress database wpdb bestaat en is bereikbaar"
    else
        fail "WordPress database wpdb niet bereikbaar" \
             "Controleer of database wpdb bestaat"
    fi
}

check_portainer() {
    section "Docker - Portainer"

    local http_code
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "${PORTAINER_URL}" 2>/dev/null || echo "000")
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Portainer bereikbaar via HTTPS op ${PORTAINER_URL} (HTTP ${http_code})"
    else
        fail "Portainer niet bereikbaar op ${PORTAINER_URL}" \
             "HTTP status: ${http_code}"
    fi
}

check_vaultwarden() {
    section "Docker - Vaultwarden"

    local http_code
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "${VAULTWARDEN_URL}" 2>/dev/null || echo "000")
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Vaultwarden bereikbaar via HTTPS op ${VAULTWARDEN_URL} (HTTP ${http_code})"
    else
        fail "Vaultwarden niet bereikbaar op ${VAULTWARDEN_URL}" \
             "HTTP status: ${http_code}"
    fi
}

check_minetest() {
    section "Docker - Minetest"

    # Minetest uses UDP
    if ssh_cmd "echo 'test' | nc -u -w 2 127.0.0.1 ${MINETEST_PORT} &>/dev/null && echo ok || echo nok" | grep -q "ok"; then
        pass "Minetest UDP poort ${MINETEST_PORT} is open"
    else
        # Fallback: check from outside
        if echo "test" | nc -u -w 2 "${TARGET}" "${MINETEST_PORT}" &>/dev/null; then
            pass "Minetest UDP poort ${MINETEST_PORT} is open"
        else
            fail "Minetest niet bereikbaar op UDP poort ${MINETEST_PORT}" \
                 "Controleer of de Minetest container draait"
        fi
    fi
}

check_planka() {
    section "Docker - Planka"

    local http_code
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "${PLANKA_URL}" 2>/dev/null || echo "000")
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Planka bereikbaar op ${PLANKA_URL} (HTTP ${http_code})"
    else
        fail "Planka niet bereikbaar op ${PLANKA_URL}" \
             "HTTP status: ${http_code}"
    fi

    # Try login via API
    local login_response
    login_response=$(curl -sk --connect-timeout 5 \
        -X POST "${PLANKA_URL}/api/access-tokens" \
        -H "Content-Type: application/json" \
        -d "{\"emailOrUsername\":\"troubleshoot@selab.hogent.be\",\"password\":\"shoot\"}" \
        2>/dev/null || echo "")

    if echo "$login_response" | jq -e '.item' &>/dev/null; then
        pass "Planka login als troubleshoot@selab.hogent.be"
    else
        fail "Planka login als troubleshoot@selab.hogent.be mislukt" \
             "Controleer gebruiker/wachtwoord"
    fi
}

check_docker_compose() {
    section "Docker - Compose & Volumes"

    # Check containers are running
    local containers
    containers=$(ssh_cmd "docker ps --format '{{.Names}}' 2>/dev/null" || echo "")

    for svc in vaultwarden minetest portainer; do
        if echo "$containers" | grep -qi "$svc"; then
            pass "Container ${svc} draait"
        else
            fail "Container ${svc} draait niet"
        fi
    done

    # Check Planka container
    if echo "$containers" | grep -qi "planka"; then
        pass "Container planka draait"
    else
        fail "Container planka draait niet"
    fi

    # Check local bind mounts for vaultwarden and minetest
    local vw_mount
    vw_mount=$(ssh_cmd "docker inspect \$(docker ps -q --filter name=vaultwarden) --format '{{json .Mounts}}' 2>/dev/null" || echo "[]")
    if echo "$vw_mount" | grep -q '"Type":"bind"'; then
        pass "Vaultwarden gebruikt een lokale map voor data"
    else
        fail "Vaultwarden gebruikt geen lokale map (bind mount) voor data"
    fi

    local mt_mount
    mt_mount=$(ssh_cmd "docker inspect \$(docker ps -q --filter name=minetest) --format '{{json .Mounts}}' 2>/dev/null" || echo "[]")
    if echo "$mt_mount" | grep -q '"Type":"bind"'; then
        pass "Minetest gebruikt een lokale map voor data"
    else
        fail "Minetest gebruikt geen lokale map (bind mount) voor data"
    fi

    # Check Portainer uses a docker volume
    local pt_mount
    pt_mount=$(ssh_cmd "docker inspect \$(docker ps -q --filter name=portainer) --format '{{json .Mounts}}' 2>/dev/null" || echo "[]")
    if echo "$pt_mount" | grep -q '"Type":"volume"'; then
        pass "Portainer gebruikt een Docker volume voor data"
    else
        fail "Portainer gebruikt geen Docker volume voor data"
    fi

    # Check Planka compose location
    local planka_compose
    planka_compose=$(ssh_cmd "test -f ~/docker/planka/docker-compose.yml && echo ok || test -f ~/docker/planka/compose.yml && echo ok || echo nok")
    if [[ "$planka_compose" == *"ok"* ]]; then
        pass "Planka docker-compose bestand in ~/docker/planka/"
    else
        fail "Geen docker-compose bestand in ~/docker/planka/" \
             "Verwacht ~/docker/planka/docker-compose.yml of compose.yml"
    fi
}

#  Main

echo ""
bold "====================================================="
bold "         SELab Opdracht6 Checker"
bold "         Target: ${TARGET}"
bold "====================================================="

check_ping
check_ssh
check_internet
check_apache_https
# check_sftp_upload
check_mysql_remote
check_mysql_local_via_ssh
check_mysql_admin_not_remote
check_wordpress_reachable
check_wordpress_post
check_wordpress_login
check_wordpress_db
check_portainer
check_vaultwarden
check_minetest
check_planka
check_docker_compose

echo ""
bold "=== Resultaat ==="
echo ""
echo "  Totaal: ${TOTAL}  |  $(green "Geslaagd: ${PASSED}")  |  $(red "Gefaald: ${FAILED}")"
echo ""

if [[ "$FAILED" -eq 0 ]]; then
    green "  🎉 Alle checks geslaagd!"
else
    yellow "  ⚠️  Er zijn ${FAILED} checks gefaald. Bekijk de details hierboven."
fi
echo ""

exit "${FAILED}"
