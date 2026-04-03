# SELab Opdracht 6 Checker

Automated checker for the SELab VM assignment.

## Usage

Run the checker from your host machine (where VirtualBox / UTM / QEMU/KVM runs):

```bash
docker run --rm --network host mtdig/sel-opdracht6-checker:latest
```

If your VM uses a different IP:

```bash
docker run --rm --network host -e TARGET=192.168.128.20 mtdig/sel-opdracht6-checker:latest
```


## What it checks

| #  | Category   | Check                                              |
|----|------------|-----------------------------------------------------|
| 1  | Netwerk    | VM pingbaar op 192.168.56.20                        |
| 2  | SSH        | Login als trouble/shoot op poort 22                 |
| 3  | Netwerk    | VM heeft internettoegang                            |
| 4  | Apache     | HTTPS bereikbaar                                    |
| 5  | Apache     | SFTP upload naar /var/www                            |
| 6  | MySQL      | Remote toegang als appusr op poort 3306 (appdb)      |
| 7  | MySQL      | Lokale toegang als admin via SSH                     |
| 8  | MySQL      | admin is NIET bereikbaar van buitenaf                |
| 9  | WordPress  | Site bereikbaar op poort 8080                        |
| 10 | WordPress  | Minstens 1 extra post aanwezig                       |
| 11 | WordPress  | Login als wpuser                                     |
| 12 | WordPress  | Database appdb bestaat                                |
| 13 | Portainer  | HTTPS bereikbaar op poort 9443                       |
| 14 | Vaultwarden| HTTPS bereikbaar op poort 4123                       |
| 15 | Minetest   | UDP poort 30000 open                                 |
| 16 | Planka     | HTTP bereikbaar op poort 3000                        |
| 17 | Planka     | Login als troubleshoot@selab.hogent.be               |
| 18 | Docker     | Containers vaultwarden, minetest, portainer draaien  |
| 19 | Docker     | Planka container draait                              |
| 20 | Docker     | Vaultwarden & Minetest: lokale bind mounts           |
| 21 | Docker     | Portainer: Docker volume                             |
| 22 | Docker     | Planka compose in ~/docker/planka/                   |

## Exit code

The exit code equals the number of failed checks (0 = all passed).
