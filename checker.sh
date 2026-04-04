#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# SELab Opdracht6 Checker
# ============================================================================

TARGET="${TARGET:-192.168.56.20}"
LOCAL_USER="${LOCAL_USER:-$(whoami)}"

# ── Secrets (decrypted at runtime via openssl) ─────────────────────────────
SECRETS_FILE="/secrets.env.enc"

if [[ -z "${DECRYPT_PASS:-}" ]]; then
    echo -e "\e[31mERROR: DECRYPT_PASS is not set.\e[0m"
    echo "Pass the decryption passphrase as an environment variable:"
    echo "  docker run --rm -e DECRYPT_PASS=\"...\" -e LOCAL_USER=\$USER mtdig/sel-opdracht6-checker"
    exit 1
fi

if [[ ! -f "$SECRETS_FILE" ]]; then
    echo -e "\e[31mERROR: Encrypted secrets file ${SECRETS_FILE} not found.\e[0m"
    exit 1
fi

# Decrypt and source the secrets
eval "$(openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$DECRYPT_PASS" -in "$SECRETS_FILE" 2>/dev/null)" || {
    echo -e "\e[31mERROR: Failed to decrypt secrets. Is DECRYPT_PASS correct?\e[0m"
    exit 1
}

# Verify required secrets are present
for var in SSH_USER SSH_PASS MYSQL_REMOTE_USER MYSQL_REMOTE_PASS \
           MYSQL_LOCAL_USER MYSQL_LOCAL_PASS WP_USER WP_PASS; do
    if [[ -z "${!var:-}" ]]; then
        echo -e "\e[31mERROR: Secret ${var} missing after decryption.\e[0m"
        exit 1
    fi
done
# ────────────────────────────────────────────────────────────────────────────

PORTAINER_URL="https://${TARGET}:9443"
VAULTWARDEN_URL="https://${TARGET}:4123"
PLANKA_URL="http://${TARGET}:3000"
WP_URL="http://${TARGET}:8080"
APACHE_URL="https://${TARGET}"
MINETEST_PORT=30000
TRACE_DELAY_MS="${TRACE_DELAY_MS:-0}"

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

# ANSI codes
DIM=$'\e[2m'
RESET=$'\e[0m'
MOVE_UP=$'\e[1A'
CLEAR_LINE=$'\e[2K'

FAILURE_LOGS=()
SSH_OK=0

# Skip a check if SSH is not available
require_ssh() {
    if [[ "$SSH_OK" -eq 0 ]]; then
        fail "$1" "Overgeslagen — SSH-verbinding is niet beschikbaar"
        return 1
    fi
    return 0
}

trace() {
    echo -ne "${DIM}    → $1 ...${RESET}"
}
trace_done() {
    if [[ "$TRACE_DELAY_MS" -gt 0 ]]; then
        sleep "$(awk "BEGIN{printf \"%f\", ${TRACE_DELAY_MS}/1000}")" 
    fi
    echo -ne "\r${CLEAR_LINE}"
}

# Run a check function, on failure store its name for end summary
run_check() {
    local check_fn="$1"
    local failed_before=$FAILED

    "$check_fn" || true

    if [[ "$FAILED" -gt "$failed_before" ]]; then
        FAILURE_LOGS+=("$check_fn")
    fi
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

    trace "ping -c 2 -W 3 ${TARGET}"
    if ping -c 2 -W 3 "${TARGET}" &>/dev/null; then
        trace_done
        pass "VM is bereikbaar via ping op ${TARGET}"
    else
        trace_done
        fail "VM is niet bereikbaar via ping op ${TARGET}"
    fi
}

check_ssh() {
    section "SSH"

    trace "ssh ${SSH_USER}@${TARGET} echo ok"
    if ssh_cmd "echo ok" | grep -q "ok"; then
        trace_done
        SSH_OK=1
        pass "SSH-verbinding als ${SSH_USER} op poort 22"
    else
        trace_done
        fail "SSH-verbinding als ${SSH_USER} op poort 22" \
             "Kan niet inloggen met ${SSH_USER}/${SSH_PASS}"
    fi
}

check_internet() {
    section "Internet (vanuit VM): ping naar google dns 8.8.8.8"
    require_ssh "Internet check" || return

    trace "ssh ${SSH_USER}@${TARGET} 'ping -c 1 -W 3 8.8.8.8'"
    local result
    result=$(ssh_cmd "ping -c 1 -W 3 8.8.8.8 &>/dev/null && echo ok || echo nok" || echo "nok")
    trace_done
    if [[ "$result" == *"ok"* ]]; then
        pass "VM heeft internettoegang"
    else
        fail "VM heeft geen internettoegang" \
             "ping 8.8.8.8 vanuit de VM mislukt"
    fi
}

check_apache_https() {
    section "Webserver (Apache2): check 200 <= HTTP response code < 400"

    trace "curl -sk ${APACHE_URL}"
    local http_code body
    body=$(curl -sk --connect-timeout 5 -w '\n%{http_code}' "${APACHE_URL}" 2>/dev/null || echo "000")
    http_code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
    trace_done

    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Apache bereikbaar via HTTPS op ${APACHE_URL} (HTTP ${http_code})"
    else
        fail "Apache niet bereikbaar via HTTPS op ${APACHE_URL}" \
             "HTTP status: ${http_code}"
        return
    fi

    trace "grep verwachte tekst in response body"
    if echo "$body" | grep -q 'Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!'; then
        trace_done
        pass "Apache index.html bevat de verwachte tekst: 'Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!'"
    else
        trace_done
        fail "Apache index.html bevat niet de verwachte tekst" \
             "Verwacht: 'Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!'"
    fi
}


check_sftp_upload() {
    section "SFTP upload & roundtrip check"
    require_ssh "SFTP upload" || return

    local tmpfile
    tmpfile=$(mktemp /tmp/selab-opdracht6-XXXXXX.html)
    local remote_path="/var/www/html/opdracht6.html"
    local check_url="${APACHE_URL}/opdracht6.html"

    # Create an HTML file containing the local username
    cat > "$tmpfile" <<HTMLEOF
<!DOCTYPE html>
<html>
    <head><title>Opdracht 6</title></head>
    <body>
        <h1>SELab Opdracht 6</h1>
        <p>Ingediend door: ${LOCAL_USER}</p>
    </body>
</html>
HTMLEOF

    # Step 1: Upload via SFTP
    trace "sftp ${SSH_USER}@${TARGET} put opdracht6.html ${remote_path}"
    if sshpass -p "${SSH_PASS}" sftp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o LogLevel=ERROR \
        "${SSH_USER}@${TARGET}" <<EOF &>/dev/null
put ${tmpfile} ${remote_path}
EOF
    then
        trace_done
        pass "SFTP upload van opdracht6.html naar ${remote_path} als ${SSH_USER}"
    else
        trace_done
        fail "SFTP upload van opdracht6.html naar ${remote_path} als ${SSH_USER}" \
             "Kan niet uploaden via SFTP op poort 22"
        rm -f "$tmpfile"
        return
    fi

    # Step 1b: Fix permissions so www-data can read the file
    trace "ssh ${SSH_USER}@${TARGET} chmod 644 ${remote_path}"
    ssh_cmd "chmod 644 ${remote_path}" &>/dev/null || true
    trace_done

    # Step 2: Fetch the page via HTTPS and verify the username is present
    trace "curl -sk ${check_url}"
    local body http_code
    body=$(curl -sk --connect-timeout 5 -w '\n%{http_code}' "${check_url}" 2>/dev/null || echo "000")
    http_code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
    trace_done

    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "opdracht6.html bereikbaar via HTTPS op ${check_url} (HTTP ${http_code})"
    else
        fail "opdracht6.html niet bereikbaar via HTTPS op ${check_url}" \
             "HTTP status: ${http_code}"
        rm -f "$tmpfile"
        return
    fi

    trace "grep '${LOCAL_USER}' in response body"
    if echo "$body" | grep -q "${LOCAL_USER}"; then
        trace_done
        pass "Roundtrip OK: gebruiker '${LOCAL_USER}' gevonden in opdracht6.html"
    else
        trace_done
        fail "Roundtrip NIET OK: gebruiker '${LOCAL_USER}' niet gevonden in opdracht6.html" \
             "Verwacht '${LOCAL_USER}' in de pagina-inhoud"
    fi

}

check_mysql_remote() {
    section "Databankserver (MySQL)"

    trace "mysql -h ${TARGET} -P 3306 -u ${MYSQL_REMOTE_USER} -e 'SELECT 1'"
    if mysql -h "${TARGET}" -P 3306 --skip-ssl \
        -u "${MYSQL_REMOTE_USER}" -p"${MYSQL_REMOTE_PASS}" \
        -e "SELECT 1;" &>/dev/null; then
        trace_done
        pass "MySQL bereikbaar op ${TARGET}:3306 als ${MYSQL_REMOTE_USER}"
    else
        trace_done
        fail "MySQL niet bereikbaar op ${TARGET}:3306 als ${MYSQL_REMOTE_USER}" \
             "Controleer gebruiker/wachtwoord en of remote access is ingeschakeld"
    fi

    # Check appdb database exists
    trace "mysql -h ${TARGET} -P 3306 -u ${MYSQL_REMOTE_USER} appdb -e 'SELECT 1'"
    if mysql -h "${TARGET}" -P 3306 --skip-ssl \
        -u "${MYSQL_REMOTE_USER}" -p"${MYSQL_REMOTE_PASS}" \
        appdb -e "SELECT 1;" &>/dev/null; then
        trace_done
        pass "Database appdb is bereikbaar als ${MYSQL_REMOTE_USER}"
    else
        trace_done
        fail "Database appdb niet bereikbaar als ${MYSQL_REMOTE_USER}" \
             "Controleer of database appdb bestaat en gebruiker toegang heeft"
    fi
}

check_mysql_local_via_ssh() {
    require_ssh "MySQL lokaal via SSH" || return

    trace "ssh ${SSH_USER}@${TARGET} mysql -u ${MYSQL_LOCAL_USER} -e 'SELECT 1'"
    local result
    result=$(ssh_cmd "mysql -u ${MYSQL_LOCAL_USER} -p'${MYSQL_LOCAL_PASS}' -e 'SELECT 1;' 2>/dev/null" || echo "error")
    trace_done
    if [[ "$result" == *"1"* ]]; then
        pass "MySQL lokaal bereikbaar via SSH als ${MYSQL_LOCAL_USER}"
    else
        fail "MySQL lokaal niet bereikbaar via SSH als ${MYSQL_LOCAL_USER}" \
             "Controleer of admin gebruiker bestaat met juiste rechten"
    fi
}

check_mysql_admin_not_remote() {
    trace "mysql -h ${TARGET} -P 3306 -u ${MYSQL_LOCAL_USER} -e 'SELECT 1' (should fail)"
    if mysql -h "${TARGET}" -P 3306 --skip-ssl \
        -u "${MYSQL_LOCAL_USER}" -p"${MYSQL_LOCAL_PASS}" \
        -e "SELECT 1;" &>/dev/null 2>&1; then
        trace_done
        fail "MySQL admin is bereikbaar van buitenaf (zou alleen lokaal mogen zijn)"
    else
        trace_done
        pass "MySQL admin is niet bereikbaar van buitenaf (correct)"
    fi
}

check_wordpress_reachable() {
    section "WordPress"

    trace "curl -sk ${WP_URL}"
    local http_code
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "${WP_URL}" 2>/dev/null || echo "000")
    trace_done
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "WordPress bereikbaar op ${WP_URL} (HTTP ${http_code})"
    else
        fail "WordPress niet bereikbaar op ${WP_URL}" \
             "HTTP status: ${http_code}"
    fi
}

check_wordpress_post() {
    trace "curl -sk ${WP_URL}/?rest_route=/wp/v2/posts"
    local response
    response=$(curl -sk --connect-timeout 5 "${WP_URL}/?rest_route=/wp/v2/posts" 2>/dev/null || echo "[]")
    local count
    count=$(echo "$response" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
    trace_done

    if [[ "$count" -gt 2 ]]; then
        pass "WordPress heeft minstens 3 post (${count} gevonden)"
    else
        fail "WordPress heeft geen posts" \
             "Maak minstens 1 post aan"
    fi
}

check_wordpress_login() {
    trace "curl -sk ${WP_URL}/xmlrpc.php (wp.getUsersBlogs)"
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
    trace_done

    if echo "$response" | grep -q "blogid"; then
        pass "WordPress login als ${WP_USER}"
    else
        fail "WordPress login als ${WP_USER} mislukt" \
             "Controleer gebruiker/wachtwoord of XML-RPC beschikbaarheid"
    fi
}

check_wordpress_db() {
    require_ssh "WordPress database check" || return

    trace "ssh ${SSH_USER}@${TARGET} mysql -u ${WP_USER} wpdb -e 'SELECT 1'"
    local result
    result=$(ssh_cmd "mysql -u ${WP_USER} -p'${WP_PASS}' wpdb -e 'SELECT 1;' 2>/dev/null" || echo "error")
    trace_done
    if [[ "$result" == *"1"* ]]; then
        pass "WordPress database wpdb bestaat en is bereikbaar via SSH"
    else
        fail "WordPress database wpdb niet bereikbaar via SSH" \
             "Controleer of database wpdb bestaat en gebruiker ${WP_USER} toegang heeft"
    fi
}

check_portainer() {
    section "Docker - Portainer"

    trace "curl -sk ${PORTAINER_URL}"
    local http_code
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "${PORTAINER_URL}" 2>/dev/null || echo "000")
    trace_done
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Portainer bereikbaar via HTTPS op ${PORTAINER_URL} (HTTP ${http_code})"
    else
        fail "Portainer niet bereikbaar op ${PORTAINER_URL}" \
             "HTTP status: ${http_code}"
    fi
}

check_vaultwarden() {
    section "Docker - Vaultwarden"

    trace "curl -sk ${VAULTWARDEN_URL}"
    local http_code
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "${VAULTWARDEN_URL}" 2>/dev/null || echo "000")
    trace_done
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Vaultwarden bereikbaar via HTTPS op ${VAULTWARDEN_URL} (HTTP ${http_code})"
    else
        fail "Vaultwarden niet bereikbaar op ${VAULTWARDEN_URL}" \
             "HTTP status: ${http_code}"
    fi
}

check_minetest() {
    section "Docker - Minetest"

    trace "nc -u -w 2 ${TARGET} ${MINETEST_PORT}"
    if echo "test" | nc -u -w 2 "${TARGET}" "${MINETEST_PORT}" &>/dev/null; then
        trace_done
        pass "Minetest UDP poort ${MINETEST_PORT} is open"
    else
        trace_done
        fail "Minetest niet bereikbaar op UDP poort ${MINETEST_PORT}" \
             "Controleer of de Minetest container draait"
    fi
}

check_planka() {
    section "Docker - Planka"

    trace "curl -sk ${PLANKA_URL}"
    local http_code
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "${PLANKA_URL}" 2>/dev/null || echo "000")
    trace_done
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Planka bereikbaar op ${PLANKA_URL} (HTTP ${http_code})"
    else
        fail "Planka niet bereikbaar op ${PLANKA_URL}" \
             "HTTP status: ${http_code}"
    fi

    trace "curl -sk -X POST ${PLANKA_URL}/api/access-tokens (login)"
    local login_response
    login_response=$(curl -sk --connect-timeout 5 \
        -X POST "${PLANKA_URL}/api/access-tokens" \
        -H "Content-Type: application/json" \
        -d "{\"emailOrUsername\":\"troubleshoot@selab.hogent.be\",\"password\":\"shoot\"}" \
        2>/dev/null || echo "")
    trace_done

    if echo "$login_response" | jq -e '.item' &>/dev/null; then
        pass "Planka login als troubleshoot@selab.hogent.be"
    else
        fail "Planka login als troubleshoot@selab.hogent.be mislukt" \
             "Controleer gebruiker/wachtwoord"
    fi
}

check_docker_compose() {
    section "Docker - Compose & Volumes"
    require_ssh "Docker compose check" || return

    trace "ssh ${SSH_USER}@${TARGET} docker ps"
    local containers
    containers=$(ssh_cmd "docker ps --format '{{.Names}}' 2>/dev/null" || echo "")
    trace_done

    for svc in vaultwarden minetest portainer; do
        if echo "$containers" | grep -qi "$svc"; then
            pass "Container ${svc} draait"
        else
            fail "Container ${svc} draait niet"
        fi
    done

    if echo "$containers" | grep -qi "planka"; then
        pass "Container planka draait"
    else
        fail "Container planka draait niet"
    fi

    trace "ssh ${SSH_USER}@${TARGET} docker inspect vaultwarden (mounts)"
    local vw_mount
    vw_mount=$(ssh_cmd "docker inspect \$(docker ps -q --filter name=vaultwarden) --format '{{json .Mounts}}' 2>/dev/null" || echo "[]")
    trace_done
    if echo "$vw_mount" | grep -q '"Type":"bind"'; then
        pass "Vaultwarden gebruikt een lokale map voor data"
    else
        fail "Vaultwarden gebruikt geen lokale map (bind mount) voor data"
    fi

    trace "ssh ${SSH_USER}@${TARGET} docker inspect minetest (mounts)"
    local mt_mount
    mt_mount=$(ssh_cmd "docker inspect \$(docker ps -q --filter name=minetest) --format '{{json .Mounts}}' 2>/dev/null" || echo "[]")
    trace_done
    if echo "$mt_mount" | grep -q '"Type":"bind"'; then
        pass "Minetest gebruikt een lokale map voor data"
    else
        fail "Minetest gebruikt geen lokale map (bind mount) voor data"
    fi

    trace "ssh ${SSH_USER}@${TARGET} docker inspect portainer (mounts)"
    local pt_mount
    pt_mount=$(ssh_cmd "docker inspect \$(docker ps -q --filter name=portainer) --format '{{json .Mounts}}' 2>/dev/null" || echo "[]")
    trace_done
    if echo "$pt_mount" | grep -q '"Type":"volume"'; then
        pass "Portainer gebruikt een Docker volume voor data"
    else
        fail "Portainer gebruikt geen Docker volume voor data"
    fi

    trace "ssh ${SSH_USER}@${TARGET} test -f ~/docker/planka/docker-compose.yml"
    local planka_compose
    planka_compose=$(ssh_cmd "test -f ~/docker/planka/docker-compose.yml && echo ok || test -f ~/docker/planka/compose.yml && echo ok || echo nok")
    trace_done
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
bold "         Voor: ${LOCAL_USER}"
bold "====================================================="

run_check check_ping
run_check check_ssh
run_check check_internet
run_check check_apache_https
run_check check_sftp_upload
run_check check_mysql_remote
run_check check_mysql_local_via_ssh
run_check check_mysql_admin_not_remote
run_check check_wordpress_reachable
run_check check_wordpress_post
run_check check_wordpress_login
run_check check_wordpress_db
run_check check_portainer
run_check check_vaultwarden
run_check check_minetest
run_check check_planka
run_check check_docker_compose

echo ""
bold "=== Resultaat ==="
echo ""
echo "  Totaal: ${TOTAL}  |  $(green "Geslaagd: ${PASSED}")  |  $(red "Gefaald: ${FAILED}")"
echo ""

if [[ "$FAILED" -eq 0 ]]; then
    green "  🎉 Alle checks geslaagd!"
else
    yellow "  ⚠️  Er zijn ${FAILED} checks gefaald. Zie ❌ hierboven voor details."
fi
echo ""

exit "${FAILED}"
