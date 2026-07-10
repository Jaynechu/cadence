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
