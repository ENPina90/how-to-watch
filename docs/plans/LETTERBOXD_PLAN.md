# Letterboxd integration — plan

Working document for the RSS-based Letterboxd integration on
`feat/letterboxd-rss-integration`. Tick items as they land.

## Why this shape

The Letterboxd **API is request-only** and they explicitly decline access "for private or
personal projects". The OAuth code in the first implementation (`LetterboxdService`,
`LetterboxdController`, `LetterboxdBulkSyncJob`, the five `letterboxd_*` OAuth columns)
was written against real, correctly-documented endpoints but could never obtain
credentials. It is removed in step 9.

What *is* available without any authentication:

- `https://letterboxd.com/<username>/rss/` — public, unauthenticated, `200 application/rss+xml`.
  Carries `letterboxd:watchedDate`, `letterboxd:memberRating` (0.5–5.0),
  `letterboxd:filmTitle`, `letterboxd:filmYear`, `letterboxd:rewatch`, `tmdb:movieId`,
  and a stable `guid` (`letterboxd-watch-<id>`). Capped at **100 items** — a rolling
  window, not full history.
- `https://letterboxd.com/imdb/<imdb_id>/` and `/tmdb/<tmdb_id>/` — both `302` to the
  canonical film page. Verified.

So: **linking is just a username**. No OAuth, no token, no handshake.

## Steps

- [ ] 1. Add `brands` to the Font Awesome imports so `fa-square-letterboxd` renders
- [ ] 2. `letterboxd_enabled:boolean` on users; `letterboxd_score:float` on entries
- [ ] 3. `LetterboxdFeed` service — fetch + parse the RSS feed
- [ ] 4. Letterboxd button on movie cards and the watch view
- [ ] 5. Username validation endpoint + Stimulus controller (green tick / warning)
- [ ] 6. Signup callout and checkbox
- [ ] 7. Profile page (edit account, toggle Letterboxd, stats)
- [ ] 8. List sync: build/refresh/destroy `[Username]'s Letterbox`
- [ ] 9. Jobs: weekly refresh + 10-minutes-after-review-click
- [ ] 10. Remove the dead OAuth implementation

## Decisions worth knowing

**Review URL suffix.** The button targets `…/review/`. Checked signed-out: `/review/`
returns `403`, identically to a bogus path, while the bare film page returns `200`. That
is consistent with an authenticated-only route, and inconclusive either way. Kept as a
single constant (`LetterboxdFilm::REVIEW_SUFFIX`) so it is a one-line change if wrong.

**IMDb vs TMDB.** The feed carries only `tmdb:movieId`. Entries need `imdb` for playback
under most source templates, so the sync backfills it via `TmdbService#fetch_imdb_id`,
which is already cached for 12h. One TMDB call per *new* film only.

**`letterboxd_score` lives on Entry**, as requested. Worth noting it is therefore "the
score of whoever imported this film", not a per-user value. That is coherent because the
Letterboxd list is private and per-user, but a score would be wrong if one of these
entries were ever copied into a shared channel.

**The 100-item cap** means "an entry for every movie in the feed" is at most the ~100 most
recent diary entries, not a full Letterboxd history. Backfilling further would need the
user's data-export ZIP, which is out of scope here.

**Feed items include lists as well as watches.** Only `letterboxd-watch-*` guids are
imported; `letterboxd-list-*` are skipped.

**Unrated watches are normal.** `memberRating` is absent for them, so `letterboxd_score`
stays `nil` and the card simply shows no score.

## Open questions for Nic

1. The list name — you wrote "[Username]'s Letterbox", not "Letterboxd". Following you
   literally; say the word and it becomes "Letterboxd".
2. Weekly scheduling needs a scheduler; Sidekiq OSS has no periodic jobs. Adding
   `sidekiq-cron`, which is the standard pairing. Shout if you would rather drive it from
   an external scheduler instead.
