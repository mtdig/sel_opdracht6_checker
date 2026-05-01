# selab_dashboard

Luanti / Minetest mod that polls your `/api/status` endpoint every 30 seconds
and renders each infrastructure check as a coloured wool block in the game world.

```
🟩 Green  = pass
🟥 Red    = fail
🟨 Yellow = skip / unknown
```

When a block **changes state** (pass → fail or vice versa), a particle burst
fires and all online players receive a chat notification.

---

## Installation

1. Copy the `selab_dashboard/` folder into your world's `mods/` directory
   (or the global mods folder):

   ```
   ~/.minetest/mods/selab_dashboard/
   ```

2. Enable the mod for your world in the Luanti / Minetest launcher
   (Content → Mods → selab_dashboard ✓), or add it to `world.mt`:

   ```
   load_mod_selab_dashboard = true
   ```

3. **Allow HTTP access** — add the mod to the trusted HTTP list in `minetest.conf`:

   ```ini
   secure.http_mods = selab_dashboard
   ```

   If you already have other mods there, comma-separate them:

   ```ini
   secure.http_mods = mymod, selab_dashboard
   ```

4. (Optional) Adjust constants at the top of `init.lua`:

   | Constant        | Default                                | Meaning                      |
   |-----------------|----------------------------------------|------------------------------|
   | `ENDPOINT`      | `http://192.168.0.221/api/status`      | Your status API URL          |
   | `POLL_INTERVAL` | `30`                                   | Seconds between auto-refresh |
   | `COL_STRIDE`    | `3`                                    | X spacing between checks     |
   | `ROW_STRIDE`    | `4`                                    | Z spacing between sections   |

---

## In-game usage

All commands require the `interact` privilege (any normal player has this).

| Command               | Effect                                              |
|-----------------------|-----------------------------------------------------|
| `/dashboard build`    | Fetch status, place all blocks, start auto-poll     |
| `/dashboard refresh`  | Immediate incremental update (colours + infotext)   |
| `/dashboard rebuild`  | Full re-lay (use after world edits near the panel)  |
| `/dashboard clear`    | Stop polling (blocks stay, just pauses the loop)    |
| `/dashboard info`     | Show origin coords, poll interval, tracked checks   |

---

## Layout

```
 [MESE beacon] ← summary infotext (look at it)
 ↓  Z axis (sections, one per row)
 ↓
 [meselamp header] [wool] [wool] [wool] …  ← section row
 [meselamp header] [wool] [wool] …
 …

 → X axis (checks within section)
```

- **Stand south of the panel** (negative Z from origin) and **look north**.
- Section names appear on signs just south of each meselamp header.
- Check names appear on signs attached to the glass pillar above each wool block.
- **Hover/punch** any wool block to read its full infotext:
  check name, protocol, port, duration, result count.

---

## Expected JSON shape

```json
{
  "passed": 35,
  "failed": 0,
  "total":  35,
  "skipped": 0,
  "sections": [
    {
      "id":     "network",
      "name":   "Network",
      "status": "pass",
      "checks": [
        {
          "id":          "ping",
          "name":        "VM reachable via ICMP ping",
          "status":      "pass",
          "protocol":    "ICMP",
          "port":        "-",
          "duration_ms": 11,
          "results":     [{ "status": "pass", "message": "…" }]
        }
      ]
    }
  ]
}
```

The mod reads `data.sections[*].checks[*].status` — only `"pass"`, `"fail"`,
and `"skip"` are treated specially; anything else renders as grey.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `HTTP API not available` in chat | Add mod to `secure.http_mods` in `minetest.conf` |
| `HTTP error (code 0)` | Server unreachable — check IP/port and that the server is up |
| `JSON parse failed` | Endpoint returned non-JSON — test with `curl http://192.168.0.221/api/status` |
| Blocks placed but wrong colour | Check `check.status` value in raw JSON; mod only handles lowercase `"pass"`/`"fail"` |
| Signs face wrong direction | Change `param2` values in `init.lua` (2 = faces south, 3 = faces north) |
