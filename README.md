# pebble-sync

Pulls voice notes from a Pebble Index 01 into a plain text file on your computer via a Cloudflare Worker.

You press and hold the ring and talk. Later, you run `pebble-sync.sh` and every note since the last sync is appended to your notes file:

```
[2026-10-12 08:14] buy milk on the way home
[2026-10-12 12:40] call mom about sunday
```

## How it works

The ring can't be read directly. It sends recordings to the Pebble phone app over Bluetooth, and the app transcribes them. The app can then POST each transcript to a webhook URL.

That webhook is a small Cloudflare Worker (`worker.js`). It stores each note in a Cloudflare D1 database, which is hosted SQLite. Because the Worker is always reachable over HTTPS, notes are caught no matter what network your phone is on, and nothing has to be running at home.

```
Ring ──Bluetooth──> Pebble app ──HTTPS POST──> Worker ──> D1 database

Your PC: pebble-sync.sh ──HTTPS GET /notes?after=N──> Worker ──> appended to your notes file
```

Every note gets an increasing id. `pebble-sync.sh` remembers the last id it pulled in `~/.local/state/pebble-sync-last-id` and asks only for newer ones, so a note is never pulled twice. Notes stay in the database after syncing.

A secret token protects both directions. The phone sends it with each webhook, `pebble-sync.sh` sends it when pulling, and the Worker rejects any request without it.

## Files

| File | What it is |
|---|---|
| `worker.js` | The Worker. `POST /` receives webhooks, `GET /notes` serves notes to `pebble-sync.sh`. |
| `schema.sql` | The database table. |
| `wrangler.toml` | Worker config: name, entry file, database binding. |
| `pebble-sync.sh` | Run on your computer to pull new notes. |
| `install.sh` | Links `pebble-sync.sh` into `~/.local/bin` and creates the config file. |
| `config.example` | Template for `~/.config/pebble-sync/config`. |

## Setup

You need a Cloudflare account, plus Node.js, `curl` and `bash` on your computer. The free Cloudflare tier is far more than this needs.

### 1. Install Wrangler and log in

Wrangler is Cloudflare's command line tool.

```sh
npm install -g --allow-scripts=esbuild,workerd wrangler
wrangler login
```

The `--allow-scripts` flag lets two of Wrangler's dependencies run their install scripts, which newer npm versions block by default. Wrangler needs them to bundle and run Workers.

`wrangler login` opens a browser window to authorize your account.

### 2. Create the database

From this repo's directory:

```sh
wrangler d1 create pebble-notes
```

This prints a block containing a `database_id`. Open `wrangler.toml` and replace `REPLACE_WITH_ID_FROM_wrangler_d1_create` with that id. If Wrangler offers to add the binding to your config for you, make sure the result still says `binding = "DB"`.

Then create the table:

```sh
wrangler d1 execute pebble-notes --remote --file=schema.sql
```

### 3. Make a token and store it

Generate a long random secret:

```sh
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

Keep it somewhere safe, such as a password manager. You'll use it in three places.

Give it to the Worker:

```sh
wrangler secret put AUTH_TOKEN
```

Paste the token when prompted. If Wrangler says the Worker doesn't exist yet and offers to create it, say yes.

### 4. Deploy

```sh
wrangler deploy
```

This prints your Worker's URL, something like `https://pebble-notes.<your-subdomain>.workers.dev`. That's the webhook address.

### 5. Point the Pebble app at it

In the Pebble app's Index 01 webhook settings:

| Setting        | Value                                                |
|:---------------|:-----------------------------------------------------|
| Gesture        | Single-click-hold, your normal press and hold        |
| URL            | The Worker URL from step 4                           |
| Content        | Transcription only                                   |
| Header name    | `Authorization`                                      |
| Header value   | `Bearer <your token>`, with one space after `Bearer` |
| Signing secret | Leave blank                                          |

Send a test event from the app. A 200 in the app's recent runs means the Worker accepted it. Test events aren't saved as notes.

### 6. Set up sync on your computer

From this repo's directory:

```sh
./install.sh
```

This symlinks `pebble-sync.sh` into `~/.local/bin` and creates `~/.config/pebble-sync/config`. Running it again is safe, because it never overwrites an existing config. Because it's a symlink, edits to the script in this repo take effect immediately, so don't move or delete the repo.

Open `~/.config/pebble-sync/config` and fill in two values:

```sh
PEBBLE_URL="https://pebble-notes.<your-subdomain>.workers.dev"
NOTES_FILE="$HOME/notes.txt"
```

`NOTES_FILE` is the full path of your notes file, so it sets both the name and the location. Use `$HOME` rather than `~`. The folder is created if it doesn't exist.

The token doesn't go in the config, so the config is safe to keep in a dotfiles repo. Export it from a private file your shell profile sources, such as `~/.env.secrets`:

```sh
export PEBBLE_TOKEN="<your token>"
```

It needs `export`, not just `PEBBLE_TOKEN=...`, or `pebble-sync.sh` won't see it. Open a new terminal after adding it.

Because the token comes from your shell environment, run `pebble-sync.sh` from a terminal. A cron job or systemd timer won't have it.

Make a recording with the ring, wait a few seconds, then run:

```sh
pebble-sync.sh
```

It prints how many notes it pulled and appends them to your notes file.

## Troubleshooting

**`PEBBLE_TOKEN: export PEBBLE_TOKEN in your environment`**: the token isn't exported. Check that `~/.env.secrets` has `export PEBBLE_TOKEN=...` and that you opened a new terminal since adding it.

**`curl: (22) ... 401`**: `PEBBLE_TOKEN` doesn't match the token you gave `wrangler secret put`.

**`pebble-sync.sh: command not found`**: `~/.local/bin` isn't on your PATH. `install.sh` warns about this. Add `export PATH="$HOME/.local/bin:$PATH"` to your `~/.bashrc`.

**The app shows a failed run**: check the URL and the `Authorization` header value. To watch requests arrive live, run `wrangler tail` from this directory and make a recording.

**A note never shows up**: if a webhook fails, the Pebble app retries it on your next recording, not on its own. Make another recording and sync again.

**Starting over**: delete `~/.local/state/pebble-sync-last-id` and the next sync pulls every stored note again.
