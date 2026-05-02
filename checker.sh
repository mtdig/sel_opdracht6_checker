#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# SELab Opdracht6 Checker v1.0.13
# ============================================================================

# Verbosity: LOGLEVEL=INFO or -v = show commands + responses
#            LOGLEVEL=TRACE or -vv = set -x per check
case "${LOGLEVEL:-}" in
    TRACE|trace|2) VERBOSE=2 ;;
    INFO|info|1)   VERBOSE=1 ;;
    *)             VERBOSE=0 ;;
esac
for _arg in "$@"; do
    case "$_arg" in
        -vv) VERBOSE=2 ;;
        -v)  [[ "$VERBOSE" -lt 1 ]] && VERBOSE=1 ;;
    esac
done

TARGET="${TARGET:-192.168.56.20}"
LOCAL_USER="${LOCAL_USER:-$(whoami)}"
MIN_WP_POSTS="${MIN_WP_POSTS:-3}"
VW_TEST_SECRET="${VW_TEST_SECRET:-test_secret}"
VW_TEST_USER="${VW_TEST_USER:-testuser}"
VW_TEST_PASSWORD="${VW_TEST_PASSWORD:-Sup3rS3crP@55}"

#  Secrets (decrypted at runtime via openssl) 
SECRETS_FILE="secrets.env.enc"

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
           MYSQL_LOCAL_USER MYSQL_LOCAL_PASS WP_USER WP_PASS \
           PORTAINER_USER PORTAINER_PASS VAULTWARDEN_USER VAULTWARDEN_PASS \
           PLANKA_USER PLANKA_PASS; do
    if [[ -z "${!var:-}" ]]; then
        echo -e "\e[31mERROR: Secret ${var} missing after decryption.\e[0m"
        exit 1
    fi
done
# 

PORTAINER_URL="https://${TARGET}:9443"
VAULTWARDEN_URL="https://${TARGET}:4123"
PLANKA_URL="http://${TARGET}:3000"
WP_URL="http://${TARGET}:8080"
APACHE_URL="https://${TARGET}"
APACHE_EXPECTED_TEXT="Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!"
MINETEST_PORT=30000
TRACE_DELAY_MS="${TRACE_DELAY_MS:-0}"
MYSQL_HOST_CMD="mariadb --skip-ssl"
# MYSQL_HOST_CMD="mysql"

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
        fail "$1" "Overgeslagen - SSH-verbinding is niet beschikbaar"
        return 1
    fi
    return 0
}

trace() {
    if [[ "$VERBOSE" -ge 1 ]]; then
        echo -e "${DIM}    > $1${RESET}"
    else
        echo -ne "${DIM}    → $1 ...${RESET}"
    fi
}
trace_done() {
    if [[ "$VERBOSE" -lt 1 ]]; then
        if [[ "$TRACE_DELAY_MS" -gt 0 ]]; then
            sleep "$(awk "BEGIN{printf \"%f\", ${TRACE_DELAY_MS}/1000}")"
        fi
        echo -ne "\r${CLEAR_LINE}"
    fi
}
trace_output() {
    [[ "$VERBOSE" -lt 1 || -z "${1:-}" ]] && return
    local total
    total=$(echo "$1" | wc -l)
    echo "$1" | head -20 | while IFS= read -r _line; do
        echo -e "      ${DIM}${_line}${RESET}"
    done
    if [[ "$total" -gt 20 ]]; then
        echo -e "      ${DIM}... ($((total - 20)) more lines truncated)${RESET}"
    fi
}

# Run a check function, on failure store its name for end summary
run_check() {
    local check_fn="$1"
    local failed_before=$FAILED

    if [[ "$VERBOSE" -ge 2 ]]; then
        set -x
        "$check_fn" || true
        set +x
    else
        "$check_fn" || true
    fi

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
    result=$(ping -c 2 -W 3 "${TARGET}" 2>&1 || echo "error")
    trace_output "$result"
    if echo "$result" | grep -q "0% packet loss"; then
         trace_done
         pass "VM is bereikbaar via ping op ${TARGET}"
    else
        trace_done
        fail "VM is niet bereikbaar via ping op ${TARGET}" \
             "Controleer netwerkconfiguratie en of VM aanstaat"
    fi
}

check_ssh() {
    section "SSH"

    trace "ssh ${SSH_USER}@${TARGET} echo ok"
    result=$(ssh_cmd "echo ok" || echo "error")
    trace_output "$result"
    if echo "$result" | grep -q "ok"; then
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
    result=$(ssh_cmd "ping -c 1 -W 3 8.8.8.8 && echo ok || echo nok" || echo "nok")
    trace_done; trace_output "$result"
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
    # remove the last line (HTTP code) from body
    body=$(echo "$body" | sed '$d')
    trace_done; trace_output "HTTP ${http_code}"$'\n'"${body}"

    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Apache bereikbaar via HTTPS op ${APACHE_URL} (HTTP ${http_code})"
    else
        fail "Apache niet bereikbaar via HTTPS op ${APACHE_URL}" \
             "HTTP status: ${http_code}"
        return
    fi

    trace "grep verwachte tekst in response body"
    if echo "$body" | grep -q "${APACHE_EXPECTED_TEXT}"; then
        trace_done
        pass "Apache index.html bevat de verwachte tekst: '${APACHE_EXPECTED_TEXT}'"
    else
        trace_done
        fail "Apache index.html bevat niet de verwachte tekst" \
             "Verwacht: '${APACHE_EXPECTED_TEXT}'"
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
    timestamp=$(date)
    cat > "$tmpfile" <<HTMLEOF
<!DOCTYPE html>
<html>
    <head><title>Opdracht 6</title></head>
    <body>
        <h1>SELab Opdracht 6</h1>
        <p>Ingediend door: ${LOCAL_USER}</p>
        <p>Timestamp: ${timestamp}</p>  
    </body>
</html>
HTMLEOF
    trace_output "Gegenereerd temp HTML-bestand:\n$(cat "$tmpfile")"
    # 1: Upload via SFTP
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

    # 1b: Fix permissions so www-data can read the file
    trace "ssh ${SSH_USER}@${TARGET} chmod 644 ${remote_path}"
    ssh_cmd "chmod 644 ${remote_path}" &>/dev/null || true
    trace_done

    # 2: Fetch the page via HTTPS and verify the username and timestamp are present
    trace "curl -sk ${check_url}"
    local body http_code
    body=$(curl -sk --connect-timeout 5 -w '\n%{http_code}' "${check_url}" 2>/dev/null || echo "000")
    http_code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
    trace_done; trace_output "HTTP ${http_code}"

    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "opdracht6.html bereikbaar via HTTPS op ${check_url} (HTTP ${http_code})"
    else
        fail "opdracht6.html niet bereikbaar via HTTPS op ${check_url}" \
             "HTTP status: ${http_code}"
        rm -f "$tmpfile"
        return
    fi

    trace "grep '${LOCAL_USER}' in response body"
    if echo "$body" | grep -q "${LOCAL_USER}" && echo "$body" | grep -q "${timestamp}"; then
        trace_done
        pass "Roundtrip OK: gebruiker '${LOCAL_USER}' en timestamp '${timestamp}' gevonden in opdracht6.html"
    else
        trace_done
        fail "Roundtrip NIET OK: gebruiker '${LOCAL_USER}' of timestamp '${timestamp}' niet gevonden in opdracht6.html" \
             "Verwacht '${LOCAL_USER}' en '${timestamp}' in de pagina-inhoud"
    fi

}

check_mysql_remote() {
    section "Databankserver (MySQL)"

    trace "${MYSQL_HOST_CMD} -h ${TARGET} -P 3306 -u ${MYSQL_REMOTE_USER} -e 'SELECT 1 AS test_col'"
    local mysql_err
    if mysql_err=$(${MYSQL_HOST_CMD} -h "${TARGET}" -P 3306 --skip-ssl \
        -u "${MYSQL_REMOTE_USER}" -p"${MYSQL_REMOTE_PASS}" \
        -e "SELECT 1 AS test_col;" 2>&1); then
        trace_done; trace_output "$mysql_err"
        pass "MySQL bereikbaar op ${TARGET}:3306 als ${MYSQL_REMOTE_USER}"
    else
        trace_done; trace_output "$mysql_err"
        fail "MySQL niet bereikbaar op ${TARGET}:3306 als ${MYSQL_REMOTE_USER}" \
             "Controleer gebruiker/wachtwoord en of remote access is ingeschakeld"
    fi

    # Check appdb database exists
    trace "${MYSQL_HOST_CMD} -h ${TARGET} -P 3306 -u ${MYSQL_REMOTE_USER} appdb -e 'SELECT 1 AS test_col'"
    local mysql_err2
    if mysql_err2=$(${MYSQL_HOST_CMD} -h "${TARGET}" -P 3306 --skip-ssl \
        -u "${MYSQL_REMOTE_USER}" -p"${MYSQL_REMOTE_PASS}" \
        appdb -e "SELECT 1 AS test_col;" 2>&1); then
        trace_done; trace_output "$mysql_err2"
        pass "Database appdb is bereikbaar als ${MYSQL_REMOTE_USER}"
    else
        trace_done; trace_output "$mysql_err2"
        fail "Database appdb niet bereikbaar als ${MYSQL_REMOTE_USER}" \
             "Controleer of database appdb bestaat en gebruiker toegang heeft"
    fi
}

check_mysql_local_via_ssh() {
    echo "testing MySQL lokaal via SSH... met gebruiker ${MYSQL_LOCAL_USER}"
    require_ssh "MySQL lokaal via SSH" || return

    trace "ssh ${SSH_USER}@${TARGET} mysql -u ${MYSQL_LOCAL_USER} -e 'SELECT 1 AS test_col'"
    local result
    result=$(ssh_cmd "mysql -u ${MYSQL_LOCAL_USER} -p'${MYSQL_LOCAL_PASS}' -e 'SELECT 1 AS test_col;' 2>/dev/null" || echo "error")
    trace_done; trace_output "$result"
    if [[ "$result" == *"1"* ]]; then
        pass "MySQL lokaal bereikbaar via SSH als ${MYSQL_LOCAL_USER}"
    else
        fail "MySQL lokaal niet bereikbaar via SSH als ${MYSQL_LOCAL_USER}" \
             "Controleer of admin gebruiker bestaat met juiste rechten"
    fi
}

check_mysql_admin_not_remote() {
    trace "${MYSQL_HOST_CMD} -h ${TARGET} -P 3306 -u ${MYSQL_LOCAL_USER} -e 'SELECT 1 AS test_col' (should fail)"
    local mysql_err3
    if mysql_err3=$(${MYSQL_HOST_CMD} -h "${TARGET}" -P 3306 --skip-ssl \
        -u "${MYSQL_LOCAL_USER}" -p"${MYSQL_LOCAL_PASS}" \
        -e "SELECT 1 AS test_col;" 2>&1); then
        trace_done; trace_output "$mysql_err3"
        fail "MySQL admin is bereikbaar van buitenaf (zou alleen lokaal mogen zijn)"
    else
        trace_done; trace_output "$mysql_err3"
        pass "MySQL admin is niet bereikbaar van buitenaf (correct)"
    fi
}

check_wordpress_reachable() {
    section "WordPress"

    trace "curl -sk ${WP_URL}"
    local http_code body
    body=$(curl -sk --connect-timeout 5 -w '\n%{http_code}' "${WP_URL}" 2>/dev/null || echo -e "\n000")
    http_code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
    trace_done; trace_output "HTTP ${http_code}"$'\n'"${body}"
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
    trace_output "$(echo $response | jq '.[] | {id: .id, title: .title.rendered}')"
    local count
    count=$(echo "$response" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
    trace_done; trace_output "posts=${count}"

    if [[ "$count" -ge "$MIN_WP_POSTS" ]]; then
        pass "WordPress heeft minstens ${MIN_WP_POSTS} post(s) (${count} gevonden)"
    else
        fail "WordPress heeft geen of niet genoeg posts" \
             "Maak minstens ${MIN_WP_POSTS} post(s) aan"
    fi
}

check_wordpress_login() {
    trace "curl -sk ${WP_URL}/xmlrpc.php (wp.getUsersBlogs)"
    trace_output "Login testen via XML-RPC endpoint met gebruiker ${WP_USER} (${WP_PASS:0:2}****)"
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
    trace_output "$response"
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

    trace "ssh ${SSH_USER}@${TARGET} mysql -u ${WP_USER} wpdb -e 'SELECT 1 AS test_col'"
    local result
    result=$(ssh_cmd "mysql -u ${WP_USER} -p'${WP_PASS}' wpdb -e 'SELECT 1 AS test_col;' 2>/dev/null" || echo "error")
    trace_done; trace_output "$result"
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
    local http_code body
    body=$(curl -sk -o /dev/null --connect-timeout 5 -w '\n%{http_code}' "${PORTAINER_URL}" 2>/dev/null || echo -e "\n000")
    http_code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
    trace_done; trace_output "HTTP ${http_code}"$'\n'"${body}"
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Portainer bereikbaar via HTTPS op ${PORTAINER_URL} (HTTP ${http_code})"
    else
        fail "Portainer niet bereikbaar op ${PORTAINER_URL}" \
             "HTTP status: ${http_code}"
        return
    fi

    # Login
    trace "curl -sk -X POST ${PORTAINER_URL}/api/auth (login als ${PORTAINER_USER})"
    local token
    token=$(curl -sk --connect-timeout 5 \
        -X POST "${PORTAINER_URL}/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${PORTAINER_USER}\",\"password\":\"${PORTAINER_PASS}\"}" \
        2>/dev/null | jq -r '.jwt // empty')
    trace_done; trace_output "token=${token:0:20}..."
    if [[ -z "$token" ]]; then
        fail "Portainer login als ${PORTAINER_USER} mislukt" \
             "Controleer gebruiker/wachtwoord"
        return
    fi
    pass "Portainer login als ${PORTAINER_USER}"

    # Resolve the first available endpoint ID dynamically
    local endpoint_id
    endpoint_id=$(curl -sk --connect-timeout 5 \
        -H "Authorization: Bearer ${token}" \
        "${PORTAINER_URL}/api/endpoints" \
        2>/dev/null | jq -r 'if type == "array" then .[0].Id else empty end')
    if [[ -z "$endpoint_id" ]]; then
        fail "Portainer endpoint niet gevonden" \
             "Geen endpoints beschikbaar in Portainer"
        return
    fi

    # Container count
    trace "curl -sk ${PORTAINER_URL}/api/endpoints/${endpoint_id}/docker/containers/json"
    local containers_json container_count container_names
    containers_json=$(curl -sk --connect-timeout 5 \
        -H "Authorization: Bearer ${token}" \
        "${PORTAINER_URL}/api/endpoints/${endpoint_id}/docker/containers/json?all=true" \
        2>/dev/null || echo "[]")
    container_count=$(echo "$containers_json" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
    container_names=$(echo "$containers_json" | jq -r 'if type == "array" then .[].Names[0] else "" end' 2>/dev/null | sed 's|^/||' | tr '\n' ' ')
    trace_done; trace_output "containers=${container_count}: ${container_names}"
    if [[ "$container_count" -gt 0 ]]; then
        pass "Portainer ziet ${container_count} container(s): ${container_names}"
    else
        fail "Portainer ziet geen containers" \
             "Controleer of de Docker endpoint correct is geconfigureerd"
    fi
}

check_vaultwarden() {
    section "Docker - Vaultwarden"

    trace "curl -sk ${VAULTWARDEN_URL}"
    local http_code body
    body=$(curl -sk -o /dev/null --connect-timeout 5 -w '\n%{http_code}' "${VAULTWARDEN_URL}" 2>/dev/null || echo -e "\n000")
    http_code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
    trace_done; trace_output "HTTP ${http_code}"$'\n'"${body}"
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Vaultwarden bereikbaar via HTTPS op ${VAULTWARDEN_URL} (HTTP ${http_code})"
    else
        fail "Vaultwarden niet bereikbaar op ${VAULTWARDEN_URL}" \
             "HTTP status: ${http_code}"
        return
    fi

    # Use a temporary data dir so bw config doesn't bleed between runs
    local bw_data_dir
    bw_data_dir=$(mktemp -d)

    _bw_cleanup() { rm -rf "${bw_data_dir:-}"; unset BITWARDENCLI_APPDATA_DIR BW_PASSWORD NODE_TLS_REJECT_UNAUTHORIZED; }
    trap _bw_cleanup RETURN

    export BITWARDENCLI_APPDATA_DIR="$bw_data_dir"
    export BW_PASSWORD="${VAULTWARDEN_PASS}"
    export NODE_TLS_REJECT_UNAUTHORIZED=0

    # Point bw at our Vaultwarden instance
    trace "bw config server ${VAULTWARDEN_URL}"
    bw config server "${VAULTWARDEN_URL}" &>/dev/null
    trace_done

    # Login - --passwordenv reads password from env var, --raw prints only the session key
    trace "bw login ${VAULTWARDEN_USER} (bw CLI)"
    local bw_session
    bw_session=$(bw login "${VAULTWARDEN_USER}" \
        --passwordenv BW_PASSWORD \
        --raw --nointeraction 2>/dev/null || echo "")
    trace_done
    if [[ -z "$bw_session" ]]; then
        fail "Vaultwarden login als ${VAULTWARDEN_USER} mislukt" \
             "Controleer gebruiker/wachtwoord"
        return
    fi
    pass "Vaultwarden login als ${VAULTWARDEN_USER}"

    # Sync vault
    trace "bw sync (vault ophalen)"
    if ! bw sync --session "$bw_session" --nointeraction &>/dev/null; then
        fail "Vaultwarden sync mislukt" "bw sync gaf een fout terug"
        bw logout --nointeraction &>/dev/null || true
        return
    fi
    trace_done

    # Retrieve the item by name match (bw list items --search, then filter by exact name)
    trace "bw list items --search ${VW_TEST_SECRET}"
    trace_output "Verwacht wachtwoord: ${VW_TEST_PASSWORD}"
    trace_output "Verwachte gebruiker: ${VW_TEST_USER}"
    local item_json secret_password list_json
    list_json=$(bw list items --search "${VW_TEST_SECRET}" --session "$bw_session" --nointeraction 2>/dev/null || echo "[]")
    item_json=$(echo "$list_json" | jq -r --arg name "${VW_TEST_SECRET}" 'map(select(.name == $name)) | first // empty')
    trace_output "Ruwe item JSON:\n$item_json"
    secret_password=$(echo "$item_json" | jq -r '.login.password // empty')
    secret_username=$(echo "$item_json" | jq -r '.login.username // empty')

    trace_done; trace_output "user=${secret_username} password=${secret_password}"

    bw logout --nointeraction &>/dev/null || true

    if [[ -z "$secret_password" ]]; then
        fail "Credentials voor '${VW_TEST_SECRET}' niet gevonden in Vaultwarden" \
             "Controleer of het item '${VW_TEST_SECRET}' bestaat in de kluis"
    elif [[ "$secret_password" == "${VW_TEST_PASSWORD}" ]]; then
        pass "Vaultwarden '${VW_TEST_SECRET}' wachtwoord correct (${VW_TEST_PASSWORD})"
    else
        fail "Vaultwarden '${VW_TEST_SECRET}' wachtwoord incorrect" \
             "Verwacht: ${VW_TEST_PASSWORD}, gevonden: ${secret_password}"
    fi
}

check_minetest() {
    section "Docker - Minetest"

    # Confirm container is running via SSH
    require_ssh "Minetest container check" || return

    trace "ssh ${SSH_USER}@${TARGET} docker ps --filter name=minetest"
    local ports
    ports=$(ssh_cmd "docker ps --filter name=minetest --format '{{.Ports}}' 2>/dev/null" || echo "")
    trace_done; trace_output "$ports"

    if echo "$ports" | grep -q "${MINETEST_PORT}"; then
        pass "Minetest container draait met UDP poort ${MINETEST_PORT} gemapped"
    elif ssh_cmd "docker ps --format '{{.Names}}' 2>/dev/null" | grep -qi minetest; then
        pass "Minetest container draait (poort mapping niet bevestigd)"
    else
        fail "Minetest container niet gevonden" \
             "Controleer of de Minetest container draait"
        return
    fi

    # Send a minimal Minetest/Luanti TOSERVER_INIT packet and check for any response.
    #
    # The Luanti UDP protocol wraps every payload in a low-level "base packet"
    # header, followed by the command-specific payload.
    #
    #  Low-level reliable-packet wrapper 
    #  Offset  Size  Value       Field
    #  0       4     4F 45 74 03 protocol_id  - Luanti magic, identifies the
    #                                           protocol (never changes)
    #  4       2     00 00       sender_peer_id - 0x0000 means "I am a new
    #                                           client, assign me a peer ID"
    #  6       1     00          channel      - traffic channel (0–2); 0 = main
    #  7       1     03          type         - TYPE_RELIABLE (3); tells the
    #                                           server to ACK this packet
    #  8       2     FF FF       seqnum       - sequence number for reliability;
    #                                           0xFFFF is the initial value used
    #                                           by new clients
    #  10      1     01          subtype      - PACKET_TYPE_ORIGINAL (1); not a
    #                                           split/chunked packet
    #
    #  TOSERVER_INIT payload (command 0x0002) 
    #  11      2     00 02       command      - TOSERVER_INIT; first packet a
    #                                           client sends to initiate a session
    #  13      1     1C          max_serialization_ver - highest map/object
    #                                           serialisation format the client
    #                                           understands; 28 (0x1C) =
    #                                           SER_FMT_VER_HIGHEST_READ
    #  14      2     00 00       supp_compr_modes - bitmask of supported
    #                                           compression methods; 0 = none
    #  16      2     00 25       min_net_proto_version - lowest network protocol
    #                                           version the client accepts; 37
    #  18      2     00 25       max_net_proto_version - highest network protocol
    #                                           version the client speaks; 37
    #                                           (LATEST_PROTOCOL_VERSION in
    #                                           src/network/networkprotocol.h)
    #  20      2     00 07       player_name length - big-endian uint16 length
    #                                           prefix of the UTF-8 name string
    #  22      7     trouble     player_name  - the player name sent to the
    #                                           server; server echoes it back in
    #                                           TOCLIENT_HELLO, confirming it
    #                                           accepted the connection attempt
    #
    # Total packet: 29 bytes
    # Refs: 
    #       Luanti network protocol: https://docs.luanti.org/for-engine-devs/network-protocol/
    #       Luanti network protocol source code: 
    #           https://github.com/luanti-org/luanti/blob/master/src/network/networkprotocol.h


    trace "minetest TOSERVER_INIT → ${TARGET}:${MINETEST_PORT} (UDP, player='trouble')"
    local response_tmp response_hex byte_count
    response_tmp=$(mktemp)
    (printf '\x4f\x45\x74\x03\x00\x00\x00\x03\xff\xff\x01\x00\x02\x1c\x00\x00\x00\x25\x00\x25\x00\x07trouble'; \
     sleep 3) \
        | nc -u -w 3 "${TARGET}" "${MINETEST_PORT}" 2>/dev/null \
        > "$response_tmp"
    byte_count=$(wc -c < "$response_tmp")
    response_hex=$(xxd "$response_tmp" 2>/dev/null || echo "")
    rm -f "$response_tmp"
    trace_done; trace_output "ontvangen bytes=${byte_count}"$'\n'"${response_hex}"
    if [[ "$byte_count" -gt 0 ]]; then
        pass "Minetest server reageert op UDP poort ${MINETEST_PORT} (${byte_count} bytes ontvangen)"
    else
        fail "Minetest server reageert niet op UDP poort ${MINETEST_PORT}" \
             "Container draait maar server stuurt geen antwoord - controleer firewall en poort mapping"
    fi
}

check_planka() {
    section "Docker - Planka"

    trace "curl -sk ${PLANKA_URL}"
    local http_code body
    body=$(curl -sk --connect-timeout 5 -w '\n%{http_code}' "${PLANKA_URL}" 2>/dev/null || echo -e "\n000")
    http_code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
    trace_done; trace_output "HTTP ${http_code}"$'\n'"${body}"
    if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
        pass "Planka bereikbaar op ${PLANKA_URL} (HTTP ${http_code})"
    else
        fail "Planka niet bereikbaar op ${PLANKA_URL}" \
             "HTTP status: ${http_code}"
    fi

    trace "curl -sk -X POST ${PLANKA_URL}/api/access-tokens (login als ${PLANKA_USER})"
    local login_response
    login_response=$(curl -sk --connect-timeout 5 \
        -X POST "${PLANKA_URL}/api/access-tokens" \
        -H "Content-Type: application/json" \
        -d "{\"emailOrUsername\":\"${PLANKA_USER}\",\"password\":\"${PLANKA_PASS}\"}" \
        2>/dev/null || echo "")
    trace_done; trace_output "$login_response"

    if echo "$login_response" | jq -e '.item' &>/dev/null; then
        pass "Planka login als ${PLANKA_USER}"
    else
        fail "Planka login als ${PLANKA_USER} mislukt" \
             "Controleer gebruiker/wachtwoord"
    fi
}

check_docker_compose() {
    section "Docker - Compose & Volumes"
    require_ssh "Docker compose check" || return

    trace "ssh ${SSH_USER}@${TARGET} docker ps"
    local containers
    containers=$(ssh_cmd "docker ps --format '{{.Names}}' 2>/dev/null" || echo "")
    trace_done; trace_output "$containers"

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
    trace_done; trace_output "$vw_mount"
    if echo "$vw_mount" | grep -q '"Type":"bind"'; then
        pass "Vaultwarden gebruikt een lokale map voor data"
    else
        fail "Vaultwarden gebruikt geen lokale map (bind mount) voor data"
    fi

    trace "ssh ${SSH_USER}@${TARGET} docker inspect minetest (mounts)"
    local mt_mount
    mt_mount=$(ssh_cmd "docker inspect \$(docker ps -q --filter name=minetest) --format '{{json .Mounts}}' 2>/dev/null" || echo "[]")
    trace_done; trace_output "$mt_mount"
    if echo "$mt_mount" | grep -q '"Type":"bind"'; then
        pass "Minetest gebruikt een lokale map voor data"
    else
        fail "Minetest gebruikt geen lokale map (bind mount) voor data"
    fi

    trace "ssh ${SSH_USER}@${TARGET} docker inspect portainer (mounts)"
    local pt_mount
    pt_mount=$(ssh_cmd "docker inspect \$(docker ps -q --filter name=portainer) --format '{{json .Mounts}}' 2>/dev/null" || echo "[]")
    trace_done; trace_output "$pt_mount"
    if echo "$pt_mount" | grep -q '"Type":"volume"'; then
        pass "Portainer gebruikt een Docker volume voor data"
    else
        fail "Portainer gebruikt geen Docker volume voor data"
    fi

    trace "ssh ${SSH_USER}@${TARGET} test -f ~/docker/docker-compose.yml"
    local shared_compose
    shared_compose=$(ssh_cmd "test -f ~/docker/docker-compose.yml && echo ok || test -f ~/docker/compose.yml && echo ok || echo nok")
    trace_done; trace_output "$shared_compose"
    if [[ "$shared_compose" == *"ok"* ]]; then
        pass "Gedeeld docker-compose bestand aanwezig in ~/docker/"
    else
        fail "Geen docker-compose bestand in ~/docker/" \
             "Verwacht ~/docker/docker-compose.yml of compose.yml"
    fi

    trace "ssh ${SSH_USER}@${TARGET} test -f ~/docker/planka/docker-compose.yml"
    local planka_compose
    planka_compose=$(ssh_cmd "test -f ~/docker/planka/docker-compose.yml && echo ok || test -f ~/docker/planka/compose.yml && echo ok || echo nok")
    trace_done; trace_output "$planka_compose"
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
