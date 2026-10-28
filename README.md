# cadence

A macOS command-line tool for reading and writing Apple Calendar, Reminders, and Notes.

`cadence` reads directly from Apple's SQLite stores (fast, rich queries) and writes through EventKit and AppleScript, giving scriptable access to your calendar events, reminders, and notes from the terminal.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ / Xcode command-line tools

## Build

```sh
swift build -c release
```

The binary lands at `.build/release/cadence`. For a debug build (`swift build`), it is at `.build/debug/cadence`. Copy it somewhere on your `PATH` or invoke it by full path.

If you plan to run `cadence` from launchd (see [Weekly placeholders](#weekly-placeholders--cadence-rem-plan)), build with `deploy/build.sh [debug|release]` instead. It runs `swift build` and then signs the binary with a local certificate so macOS privacy grants survive rebuilds — see [Stable code signature](#stable-code-signature).

## Required permissions

`cadence` needs two separate grants to work fully:

1. **EventKit consent** — the first time you run a calendar or reminder command that writes (create/update/delete/done/flag), macOS prompts for Calendar and Reminders access. Approve it, or the write fails.

2. **Full Disk Access (FDA)** — `cadence` reads Apple's SQLite stores directly under `~/Library/Group Containers/…`. Without FDA on the terminal app (or on the binary itself), those reads fail with a permission error. Grant it under **System Settings → Privacy & Security → Full Disk Access**, adding your terminal (Terminal.app, iTerm, etc.) or the `cadence` binary.

## ⚠️ Use at your own risk

`rem create` and `rem update` write to Apple's **private Reminders SQLite database directly via SQL** (to set the all-day flag), in addition to going through EventKit. This is unsupported by Apple and the schema can change between macOS releases.

- **Keep backups** of your data before bulk operations.
- The Reminders app (or iCloud sync) may run concurrently and conflict with a direct write. Quit Reminders.app during heavy use if you want to be safe.
- All `delete` commands require `--force` and irreversibly remove data.

## Timezone configuration

By default `cadence` uses your system's current time zone (`TimeZone.current`). To pin a specific zone, set the `CADENCE_TZ` environment variable to a valid IANA identifier:

```sh
export CADENCE_TZ="Australia/Melbourne"
cadence rem read --today --json
```

If `CADENCE_TZ` is unset or invalid, the system time zone is used.

## Defaults

- Calendar create defaults to the **Study** calendar; override with `--calendar <name>`.
- Reminder create defaults to the **Inbox** list; override with `--list <name>`.
- Note create defaults to the **Notes** folder; override with `--folder <name>`.
- Date-only input (`YYYY-MM-DD`) makes an all-day item; datetime input (`YYYY-MM-DD HH:MM`) includes the time.

## Usage

### Calendar — `cadence cal`

```sh
# Read events. Positional dates (YYYY-MM-DD); defaults to yesterday/today/tomorrow.
cadence cal read                        # default three-day window, JSON
cadence cal read 2026-07-10 --human     # one day, human-readable
cadence cal read 2026-07-10 2026-07-11  # multiple days

# Create an event
cadence cal create --title "Study block" --start "2026-07-10 09:00" --end "2026-07-10 11:00"
cadence cal create --title "Holiday" --start 2026-07-10 --end 2026-07-11 --all-day \
  --calendar Personal --notes "..." --location "Library" --url "https://…"

# Update by calendarItemIdentifier (from cal read). Pass 'none' to clear notes/location/url.
cadence cal update <id> --title "New title" --start "2026-07-10 10:00"
cadence cal update <id> --notes none

# Delete by UUID (from cal read). Requires --force.
cadence cal delete --id <uuid> --force
```

### Reminders — `cadence rem`

```sh
# Read (filters). Default view is due-today-or-overdue.
cadence rem read --today --json
cadence rem read --overdue
cadence rem read --week
cadence rem read --all
cadence rem read --done                 # completed reminders
cadence rem read --list Inbox --human   # filter by list (case-insensitive contains)
cadence rem read --all --with-location  # also resolve geofence triggers via EventKit (slower)

# List all reminder lists with open counts
cadence rem lists
cadence rem lists --human

# Create
cadence rem create --title "Call clinic" --due "2026-07-10 14:00" --list Inbox
cadence rem create --title "Pay rent" --due 2026-07-10 --priority 1 --flag \
  --repeat "monthly;1" --notes "..." --url "https://…" --location "Home"

# Update by Z_PK id (from rem read). Pass 'none' to clear due/start/notes/location.
cadence rem update <id> --title "New title" --due "2026-07-11 09:00"
cadence rem update <id> --priority 5 --list "Work" --due none

# Complete / uncomplete
cadence rem done <id>
cadence rem done <id> --undone

# Flag / unflag
cadence rem flag <id>
cadence rem flag <id> --unflag

# Delete by Z_PK id. Requires --force.
cadence rem delete --id <id> --force
```

Priority values: `0`=none, `1`=high, `5`=medium, `9`=low.

### Weekly placeholder reminders — `cadence rem plan`

Pre-creates one empty placeholder reminder per day so you can fill in a "top task of the day" ahead of time. Each reminder's title is exactly `--prefix`; you type the rest in the Reminders app.

With `--countdown YYYY-MM-DD` each title becomes `--prefix` plus the number of days left until that target day (Melbourne local days): `--prefix D --countdown 2027-02-26` gives `D122` on 2026-10-27, `D1` on 2027-02-25 and `D0` on the target day. Days after the target are not created.

```sh
cadence rem plan --prefix "Top task: " --list Habit --dry-run
cadence rem plan --prefix "Top task: " --list Habit
cadence rem plan --prefix "Top task: " --start 2026-09-21 --days 5 --human
cadence rem plan --prefix D --countdown 2027-02-26 --list Exam --dry-run --human
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--prefix` | required | Title of each created reminder |
| `--list` | `Inbox` | Target reminder list |
| `--days` | `7` | Number of consecutive days to cover |
| `--start` | Monday of next week | First day, `YYYY-MM-DD` |
| `--countdown` | off | Target day `YYYY-MM-DD`; title = prefix + days left, nothing after the target |
| `--dry-run` | off | Print the plan, create nothing |
| `--human` | off | Readable lines instead of JSON |

Due dates are date-only (all-day, no time shown). A day is skipped when a not-completed reminder with exactly that day's title (`--prefix`, or `--prefix` + days left with `--countdown`) is already due that day — in **any** list, so a placeholder you moved or created by hand is respected. Running it twice creates nothing the second time.

Output is JSON on stdout: `{"start":"2026-09-07","created":["2026-09-07",…],"skipped":[]}`; `--human` also shows each created title. It exits non-zero if the list does not exist or Reminders access is denied.

#### Run it every Friday with launchd

`deploy/com.cadence.rem-plan.plist` is a template with five placeholders. Fill them in, install, and start (without a countdown, delete the `--countdown` and `__COUNTDOWN__` lines from the template first):

```sh
mkdir -p ~/Library/Logs/cadence-rem-plan ~/Library/LaunchAgents

sed -e "s|__CADENCE_BIN__|$PWD/.build/release/cadence|" \
    -e "s|__PREFIX__|Top task: |" \
    -e "s|__COUNTDOWN__|2027-02-26|" \
    -e "s|__LIST__|Habit|" \
    -e "s|__LOG_DIR__|$HOME/Library/Logs|" \
    deploy/com.cadence.rem-plan.plist > ~/Library/LaunchAgents/com.cadence.rem-plan.plist

launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.cadence.rem-plan.plist
launchctl kickstart -k gui/$(id -u)/com.cadence.rem-plan   # run once now
tail ~/Library/Logs/cadence-rem-plan/launchd.log
```

It fires every Friday at 12:00 (`StartCalendarInterval` Weekday 5). To remove it: `launchctl bootout gui/$(id -u)/com.cadence.rem-plan`.

Under launchd the binary runs outside your terminal, so the terminal's permissions do not apply: macOS checks the grants of `cadence` itself. Two things must be true before the job can succeed unattended:

1. **Full Disk Access on the `cadence` binary** (System Settings → Privacy & Security → Full Disk Access → `+` → ⌘⇧G → the real path under `.build/<arch>/debug/`).
2. **Reminders consent for the `cadence` binary**, which macOS asks for the first time the launchd job writes a reminder. Trigger that first run while you are at the Mac (temporarily move `StartCalendarInterval` a few minutes ahead, or `launchctl kickstart`) and click Allow.

Both grants are bound to the binary's code signature, which is why the binary must be built with `deploy/build.sh` — see [Stable code signature](#stable-code-signature). With a plain `swift build` the ad-hoc signature changes on every rebuild, macOS silently switches the FDA toggle off and re-prompts for Reminders, and the job fails or hangs until someone is at the Mac.

### Stable code signature

macOS ties privacy grants (Full Disk Access, Reminders, Calendars) to the *designated requirement* of the signed binary. An ad-hoc signed Swift build's requirement is its content hash, so every rebuild is a different program to TCC. `deploy/build.sh` signs the binary with a self-signed local certificate instead, giving it a fixed identity (`com.cadence.cli` + that certificate) across rebuilds.

One-time setup of the certificate (login keychain, no admin needed):

```sh
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=cadence-local" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -out cadence-local.p12 -inkey key.pem -in cert.pem -passout pass:cadence -legacy
security import cadence-local.p12 -k ~/Library/Keychains/login.keychain-db -P cadence -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
rm key.pem cadence-local.p12
```

Then `deploy/build.sh` (set `CADENCE_SIGN_IDENTITY` if you named the certificate differently). After the first signed build, remove and re-add `cadence` under Full Disk Access once so the grant records the new identity; from then on rebuilds keep every grant.

### Notes — `cadence note`

```sh
# List notes (optionally filtered by folder, case-insensitive contains)
cadence note list
cadence note list --folder Work --json

# Read a note's full body by Z_PK id (from note list)
cadence note read <id>
cadence note read <id> --json

# Create a note
cadence note create --title "Meeting notes" --body "..." --folder Notes

# Overwrite or append to a note body by id
cadence note write <id> --body "New content"
cadence note write <id> --body "…more" --append

# Delete a note by id. Requires --force.
cadence note delete <id> --force
```

## License

MIT — see [LICENSE](LICENSE).
</content>
