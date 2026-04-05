# sel-opdracht6-checker-gui

JavaFX GUI for validating SELab Opdracht 6 VM configurations. Runs 17 checks
against a target VM covering network, SSH, Apache, WordPress, MySQL, Docker,
Portainer, Vaultwarden, Planka, Minetest and SFTP.

## Requirements

- Java 21
- Maven 3.9+

On NixOS the included `flake.nix` in the repo root provides a dev shell with
JDK 21, Maven and the required native libraries (X11, GTK, Mesa).

## Build and run

```
mvn clean compile
mvn javafx:run
```

## Tests

```
mvn test
```

## Project structure

```
src/main/java/
  main/           StartUp (Application entry point)
  domain/         Domain model, controller, secrets decryptor, exceptions
  checks/         17 check implementations + HTTP helper
  gui/            JavaFX UI (MainPane, SidePanel, CheckGridPane, CheckDetailDialog)
src/main/resources/
  style.css       Dark theme stylesheet
  secrets.env.enc Encrypted secrets (AES-256-CBC + PBKDF2)
src/test/java/    JUnit 5 tests
```

## Dependencies

- JavaFX 21 -- UI
- Apache MINA SSHD 2.14.0 -- pure-Java SSH and SFTP
- BouncyCastle 1.80 -- TLS provider (handles broken self-signed certs)
- JUnit 5 + Mockito -- tests

## How it works

1. Enter the VM IP, your local username, and the secrets passphrase.
2. Secrets are decrypted from the embedded `secrets.env.enc` resource.
3. All 17 checks run in parallel (respecting dependency order -- SSH-dependent
   checks wait for the SSH check to complete first).
4. Results are shown in a grid of section tiles. Click a section to see
   individual check details and re-run checks.
5. A summary popup shows pass/fail/skip counts when all checks finish.
