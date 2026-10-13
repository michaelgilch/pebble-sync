# pebble-sync

Pulls voice notes from a Pebble Index 01 into a plain text file on your computer via a Cloudflare Worker.

You press and hold the ring and talk. Later, you run `./sync.sh` and every note since the last sync is appended to `~/notes.txt`:

```
[2026-10-12 08:14] buy milk on the way home
[2026-10-12 12:40] call mom about sunday
```

## How it works

The ring can't be read directly. It sends recordings to the Pebble phone app over Bluetooth, and the app transcribes them. The app can then POST each transcript to a webhook URL.

That webhook is a small Cloudflare Worker (`worker.js`). It stores each note in a Cloudflare D1 database, which is hosted SQLite. Because the Worker is always reachable over HTTPS, notes are caught no matter what network your phone is on, and nothing has to be running at home.

```
Ring ──Bluetooth──> Pebble app ──HTTPS POST──> Worker ──> D1 database

Your PC: ./sync.sh ──HTTPS GET /notes?after=N──> Worker ──> appended to ~/notes.txt
```

Every note gets an increasing id. `sync.sh` remembers the last id it pulled in `~/.local/state/pebble-sync-last-id` and asks only for newer ones, so a note is never pulled twice. Notes stay in the database after syncing.

A secret token protects both directions. The phone sends it with each webhook, `sync.sh` sends it when pulling, and the Worker rejects any request without it.

## Files

| File | What it is |
|---|---|
| `worker.js` | The Worker. `POST /` receives webhooks, `GET /notes` serves notes to `sync.sh`. |
| `schema.sql` | The database table. |
| `wrangler.toml` | Worker config: name, entry file, database binding. |
| `sync.sh` | Run on your computer to pull new notes. |

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

Add these to your `~/.bashrc` (or your shell's equivalent), then open a new terminal:

```sh
export PEBBLE_URL="https://pebble-notes.<your-subdomain>.workers.dev"
export PEBBLE_TOKEN="<your token>"
```

Make a recording with the ring, wait a few seconds, then run:

```sh
./sync.sh
```

It prints how many notes it pulled and appends them to `~/notes.txt`. To write somewhere else, set `NOTES_FILE`, for example `NOTES_FILE=~/Documents/pebble.txt ./sync.sh`.

## Troubleshooting

**`curl: (22) ... 401`**: the token in `PEBBLE_TOKEN` doesn't match the one you gave `wrangler secret put`.

**The app shows a failed run**: check the URL and the `Authorization` header value. To watch requests arrive live, run `wrangler tail` from this directory and make a recording.

**A note never shows up**: if a webhook fails, the Pebble app retries it on your next recording, not on its own. Make another recording and sync again.

**Starting over**: delete `~/.local/state/pebble-sync-last-id` and the next sync pulls every stored note again.
