# SELab Opdracht 6 Checker

Automated checker for the SELab opdracht6 assignment.  Available as:

- **bash script**
- **Docker container** — dockerized the bash script for Linux/macOS/Windows hosts that already have Docker


### Option A: Bash

```bash
DECRYPT_PASS="letmein!" LOGLEVEL=INFO ./checker.sh
```

### Optional: different target IP

```bash
DECRYPT_PASS="letmein!" LOCAL_USER=$USER TARGET=192.168.128.20 ./checker.sh
```

## Option B: Docker container

Run the checker from your host machine (where VirtualBox / UTM / QEMU/KVM runs):

```bash
docker run --rm \
  -e LOCAL_USER=$USER \
  -e DECRYPT_PASS="<pass>" \
  mtdig/sel-opdracht6-checker
```

If your VM uses a different IP:

```bash
docker run --rm \
  -e LOCAL_USER=$(whoami) \
  -e DECRYPT_PASS="<pass>" \
  -e TARGET=192.168.128.20 \
  mtdig/sel-opdracht6-checker
```

> **Tip:** You can put the variables in a `.env` file and use `docker run --env-file .env ...`
> to avoid pasting the passphrase every time.

### Environment variables

| Variable         | Default                | Description                                                  |
|------------------|------------------------|--------------|
| `DECRYPT_PASS`   | *(required)*           | Passphrase for decrypting the embedded credentials           |
| `TARGET`         | `192.168.56.20`        | IP address of the VM                                         |
| `LOCAL_USER`     | current OS user        | Your host username (use `$USER` / `$env:USERNAME`)           |
| `TRACE_DELAY_MS` | `0`                    | Pause (ms) before clearing trace lines (for debugging)       |
| `SECRETS_FILE`   | auto-detect            | Override path to `secrets.env.enc`                           |
| `LOGLEVEL`       | `ERROR`                | | 



### Secrets & encryption

The checker image contains an encrypted `secrets.env.enc` file with the
credentials needed for the checks (SSH, MySQL, WordPress, …).  At startup the
checker decrypts this file using the `DECRYPT_PASS` environment variable you
provide.

This means the **Docker image is safe to publish publicly** — the secrets can
only be read by someone who has the passphrase.

To re-encrypt the secrets after changing them:

```bash
# Edit secrets.env (not committed to git)
openssl enc -aes-256-cbc -pbkdf2 -pass pass:'letmein!' \
    -in secrets.env -out secrets.env.enc
```


## What it checks

| #  | Category    | Check                                                                                      |
|----|-------------|--------------------------------------------------------------------------------------------|
| 1  | Netwerk     | VM pingbaar op `TARGET`                                                                    |
| 2  | SSH         | Login als `trouble` op poort 22                                                            |
| 3  | Netwerk     | VM heeft internettoegang (ping 8.8.8.8)                                                    |
| 4  | Apache      | HTTPS bereikbaar + verwachte tekst in `index.html`                                         |
| 5  | SFTP        | Upload `opdracht6.html` (met jouw username) naar `/var/www/html/`                          |
| 6  | SFTP        | `opdracht6.html` bereikbaar via HTTPS                                                      |
| 7  | SFTP        | Roundtrip: jouw username teruggevonden in de webpagina                                     |
| 8  | MySQL       | Remote toegang als appusr op poort 3306 (appdb)                                            |
| 9  | MySQL       | Lokale toegang als admin via SSH                                                            |
| 10 | MySQL       | admin is NIET bereikbaar van buitenaf                                                      |
| 11 | WordPress   | Site bereikbaar op poort 8080                                                               |
| 12 | WordPress   | Minstens 3 posts aanwezig                                                                  |
| 13 | WordPress   | Login als wpuser                                                                            |
| 14 | WordPress   | Database wpdb bestaat                                                                      |
| 15 | Portainer   | HTTPS bereikbaar op poort 9443 + login + container lijst via dynamisch endpoint            |
| 16 | Vaultwarden | HTTPS bereikbaar op poort 4123 + login via `bw` CLI + `testsecret` wachtwoord correct     |
| 17 | Minetest    | Container draait + server reageert op Luanti `TOSERVER_INIT` UDP packet op poort 30000    |
| 18 | Planka      | HTTP bereikbaar op poort 3000 + login                                                      |
| 19 | Docker      | Containers `vaultwarden`, `minetest`, `portainer` draaien                                  |
| 20 | Docker      | `planka` container draait                                                                   |
| 21 | Docker      | Vaultwarden & Minetest: lokale bind mounts                                                 |
| 22 | Docker      | Portainer: Docker volume                                                                    |
| 23 | Docker      | Gedeeld compose bestand aanwezig in `~/docker/`                                            |
| 24 | Docker      | Planka compose bestand aanwezig in `~/docker/planka/`                                      |

### Vaultwarden check details

The Vaultwarden check uses the [Bitwarden CLI](https://bitwarden.com/help/cli/) (`bw`) to fully
decrypt the vault — raw HTTP cannot access encrypted vault contents.  The Docker image bundles the
`bw` pre-built binary (downloaded from the Bitwarden GitHub releases during `docker build`).

The check:
1. Points `bw` at the Vaultwarden instance (`bw config server`)
2. Logs in with the configured credentials (`bw login --passwordenv`)
3. Syncs the vault (`bw sync`)
4. Retrieves the `testsecret` item and verifies its password equals `Sup3rS3crP@55`

### Minetest check details

The Minetest check sends a real Luanti/Minetest `TOSERVER_INIT` UDP packet (29 bytes) directly to
port 30000 and verifies that the server sends back any response — proving the server is up and
processing packets, not just that the port is open.  This correctly handles firewall DROP rules that
would fool a simple `nc -z` probe.

## Exit code

The exit code equals the number of failed checks (0 = all passed).


_there are also a few other versions available_