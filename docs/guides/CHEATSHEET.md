# Cheat sheet

Quick reference for running things by hand. Written 2026-09-19. Where this and the code
disagree, `config/schedule.yml` and `lib/tasks/` win.

---

## Production console (Railway)

Production is Railway project `victorious-compassion`, environment `production`. It has two
services running the same code: `how-to-watch` (web) and `worker` (Sidekiq).

**Interactive console:** use the `railsprod` alias from the dotfiles (`~/code/ENPina90/dotfiles/aliases`):

```sh
railsprod
```

It links the CLI to the web service, opens `railway ssh`, waits for the container prompt and
starts `bin/rails console`. To do the same by hand:

```sh
railway link -p fb3a9bfc-f815-4ca4-b775-1be05c363caf -e production -s how-to-watch
railway ssh              # a real interactive shell
bin/rails console        # typed at the :/app# prompt
```

**One-off command, no console:** use the `worker` service. It has `bin/rails` on its path,
and the web service's non-interactive shell does not.

```sh
railway link -p fb3a9bfc-f815-4ca4-b775-1be05c363caf -e production -s worker
railway ssh -- 'cd /app && bin/rails runner "puts Entry.count"'
```

Single quotes outside, double quotes inside, and no `"`, `$`, backticks or backslashes in the
Ruby. Use `%(...)` for strings: `"puts List.find_by(name: %(Drama)).id"`.

**Commands that don't work:**

- `railway run bin/rails console` reaches no database: `postgres.railway.internal` only
  resolves inside Railway.
- `railway ssh -- "bin/rails console"` falls apart, because the TTY has no window size.
  Use plain `railway ssh`, then start the console.
- `--service` / `--environment` flags fail on CLI 4.7.3. Re-link instead.
- A local `bin/rails console` is always development, whatever is linked.

---

## Scheduled jobs

Defined in `config/schedule.yml`. They run only on the Sidekiq server (the `worker` service),
and cron times are in **UTC**. Toronto time is UTC−4 in summer (EDT) and UTC−5 in winter (EST).

| Job | When (UTC) | Toronto (EDT / EST) | What it does |
|---|---|---|---|
| `CloseAbandonedWatchPartiesJob` | every 15 min | — | Closes watch parties nobody has had open for a while |
| `SourceExpiryScanJob` | daily 05:30 | 01:30 / 00:30 | Warns admins about provider domains about to lapse, or lapsed |
| `CableScheduleJob` | daily 11:00 | 07:00 / 06:00 | Deals tomorrow's schedule for every cable channel; fills today if empty; prunes old slots |
| `LetterboxdWeeklyRefreshJob` | Mon 04:00 | Mon 00:00 / Sun 23:00 | Re-reads every linked member's Letterboxd diary and adds what's new |
| `BrokenPosterScanJob` | Mon 06:00 | 02:00 / 01:00 | Checks every poster URL; notifies admins about images that are gone |
| `EmbedAvailabilityScanJob` | Tue 06:00 | 02:00 / 01:00 | Asks VidSrc which entries it really has a file for; notifies about the rest |
| `MissingRuntimeScanJob` | Wed 06:00 | 02:00 / 01:00 | Fills missing runtimes from TMDB, then notifies about what's still blank (these stay off cable) |
| `NewEpisodeScanJob` | Thu 06:00 | 02:00 / 01:00 | Adds newly aired episodes to each series; notifies the channel's owner |

Results land in **notifications** (the bell), not email.

### Running a job by hand

**From the admin dashboard** (`/admin/dashboard`): the four weekly sweeps have buttons
(posters, streams, runtimes, new episodes). Each enqueues the same job the schedule runs.

**From a production console:**

```ruby
MissingRuntimeScanJob.perform_now    # runs right here, in the console -- you see it finish
MissingRuntimeScanJob.perform_later  # hands it to Sidekiq on the worker
```

Any class in the table works the same way. `perform_now` ties up your console until it
finishes. The embed and poster scans make hundreds of requests and take minutes, so use
`perform_later` for those.

**Watching Sidekiq:** `/sidekiq` (admins only) shows what is enqueued, retrying or dead.

### Cable schedule by hand

- **Re-deal today and tomorrow for every channel:** use the button on `/admin/cable`. It
  replaces what everyone is watching right now.
- **One channel from a console:**

  ```ruby
  ch = List.find(ID)                                  # or CableEra.find('1980s')
  CableSchedule.redeal!(ch, [CableSchedule.today, CableSchedule.today + 1])
  ```

- **Fill the guide's past:** `bin/rails cable:backfill[2]`

---

## Rake tasks worth knowing

Run on production with `bin/rails <task>` inside `railway ssh`. Tasks marked "dry run" change
nothing unless you add `APPLY=1`.

| Task | What it does |
|---|---|
| `sources:status` | Where the database's providers disagree with the ones the app ships |
| `sources:seed` | Create any shipped provider that is missing |
| `sources:audit` | How many entries still lean on the legacy source columns |
| `sources:repoint_inactive` | Move lists/entries off a deactivated provider (dry run) |
| `embeds:audit` | List entries VidSrc has no file for (`LIST=<id>`, `CSV=<path>`) |
| `entry:check_mega` | Check MEGA entries against MEGA's API, set `stream` (dry run) |
| `entry:check_sources` | Check the source of every entry |
| `entries:backfill_episode_runtimes` | Episode runtimes from TMDB for episodes with none |
| `entries:normalize_positions` | Renumber positions 1..N where they have drifted |
| `positions:fix_invalid` | Fix `UserListPosition`s pointing at deleted entries |
| `posters:audit` | List entries whose poster doesn't load (`LIST=`, `CSV=`, `CONCURRENCY=`) |
| `images:check` / `images:repair` | Find / repair broken entry images via TMDB |
| `commercials:seed` | Create any shipped commercial reel that is missing |
| `commercials:durations` | Fill in how long each reel runs |
| `commercials:check` | Ask YouTube whether each reel is still there and embeddable |
| `tmdb:update_tmdb_ids` | Fetch TMDB ids for entries from their IMDb id |
| `tmdb:update_trailers` | Fetch trailers for entries from TMDB |
| `db:backup:full` / `db:backup:list` / `db:backup:restore[file]` | Backups (see `DATABASE_BACKUP_GUIDE.md`) |
| `export:entries` | Entries to CSV |

`bundle exec rake -T` lists everything.

---

## Diagnosing playback

When a film restarts itself, stalls or stops and it is not clear whether the provider
dropped it or the app did, play it in isolation:

```
/entries/<id>/watch_only
```

One iframe, no preloaded second player, no app JavaScript, nothing written. The watch page
cannot answer the question because it warms a second player five seconds after landing and
a third as the credits run; this one has none of that. See ARCHITECTURE.md §5.3a.

| Query parameter | What it does |
|---|---|
| `?source=<id>` | Play on another provider the entry is eligible for, without editing it |
| `?start=<seconds>` | Test whether the provider honours a resume; the page says when it cannot |
| `?autoplay=0` | Load the frame without starting a film |
| `?subentry=<id>` | A particular episode |
| `?hud=0` | Hide the on-screen readout, leaving the console log |

Reading a run: the browser console prints `frame-reload` whenever the frame's document is
replaced, and the server prints one `[watch_only]` line per page load. Both together mean
the page reloaded; the console line alone means the provider re-navigated its own frame;
neither, with the picture jumping anyway, means the player recovered in place.

The server side is in Railway's logs for the `how-to-watch` service — filter on
`[watch_only]`. The MEGA decryption key is replaced with `#[key]` before the URL is logged;
the whole URL is on the page itself.

---

## Local

```sh
bin/dev                              # server + Sass watcher; not plain `rails server`
bundle exec rspec                    # the suite
bundle exec rspec spec/javascript_modules_spec.rb   # after touching app/javascript
```

Restart `bin/dev` after a migration: the running server silently drops new columns.
