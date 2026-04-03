# SELab Opdracht 6 Checker

Automated checker for the SELab opdracht6 assignment.  Builds a docker container for arm64 (linux, macos silicon, win ) and amd64 (linux, windows).

## Usage

Run the checker from your host machine (where VirtualBox / UTM / QEMU/KVM runs):

```bash
docker run --rm -e LOCAL_USER=$(whoami) mtdig/sel-opdracht6-checker
```

If your VM uses a different IP:

```bash
docker run --rm -e LOCAL_USER=$(whoami) -e TARGET=192.168.128.20 mtdig/sel-opdracht6-checker
```

### Environment variables

| Variable     | Default          | Description                                      |
|--------------|------------------|--------------------------------------------------|
| `TARGET`     | `192.168.56.20`  | IP-adres van de VM                               |
| `LOCAL_USER` | default is root uit de container    | Jouw gebruikersnaam (gebruik `$(whoami)` of `$USER` of ...)         |


## What it checks

| #  | Category   | Check                                                              |
|----|------------|--------------------------------------------------------------------|
| 1  | Netwerk    | VM pingbaar op `TARGET`                                            |
| 2  | SSH        | Login als trouble/shoot op poort 22                                |
| 3  | Netwerk    | VM heeft internettoegang                                           |
| 4  | Apache     | HTTPS bereikbaar + verwachte tekst in index.html                   |
| 5  | SFTP       | Upload `opdracht6.html` (met jouw username) naar `/var/www/html/`  |
| 6  | SFTP       | `opdracht6.html` bereikbaar via HTTPS                              |
| 7  | SFTP       | Roundtrip: jouw username teruggevonden in de webpagina             |
| 8  | MySQL      | Remote toegang als appusr op poort 3306 (appdb)                    |
| 9  | MySQL      | Lokale toegang als admin via SSH                                   |
| 10 | MySQL      | admin is NIET bereikbaar van buitenaf                              |
| 11 | WordPress  | Site bereikbaar op poort 8080                                      |
| 12 | WordPress  | Minstens 3 posts aanwezig                                          |
| 13 | WordPress  | Login als wpuser                                                   |
| 14 | WordPress  | Database wpdb bestaat                                             |
| 15 | Portainer  | HTTPS bereikbaar op poort 9443                                     |
| 16 | Vaultwarden| HTTPS bereikbaar op poort 4123                                     |
| 17 | Minetest   | UDP poort 30000 open                                               |
| 18 | Planka     | HTTP bereikbaar op poort 3000                                      |
| 19 | Planka     | Login als troubleshoot@selab.hogent.be                             |
| 20 | Docker     | Containers vaultwarden, minetest, portainer draaien                |
| 21 | Docker     | Planka container draait                                            |
| 22 | Docker     | Vaultwarden & Minetest: lokale bind mounts                         |
| 23 | Docker     | Portainer: Docker volume                                           |
| 24 | Docker     | Planka compose in ~/docker/planka/                                 |

## Exit code

The exit code equals the number of failed checks (0 = all passed).
