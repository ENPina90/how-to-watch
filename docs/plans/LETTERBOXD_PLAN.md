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

- [x] 1. Add `brands` to the Font Awesome imports so `fa-square-letterboxd` renders
- [x] 2. `letterboxd_enabled:boolean` on users; `letterboxd_score:float` on entries
- [x] 3. `LetterboxdFeed` service — fetch + parse the RSS feed
- [x] 4. Letterboxd button on movie cards and the watch view
- [x] 5. Username validation endpoint + Stimulus controller (green tick / warning)
- [x] 6. Signup callout and checkbox
- [x] 7. Profile page (edit account, toggle Letterboxd, stats)
- [x] 8. List sync: build/refresh/destroy `[Username]'s Letterbox`
- [x] 9. Jobs: weekly refresh + 10-minutes-after-review-click
- [x] 10. Remove the dead OAuth implementation

## Decisions worth knowing

**Review URL needs the canonical slug.** `/imdb/<id>/review/` is a dead URL: the shortcut
redirects the *film*, not a path hanging off it. Only `/film/<slug>/review/` opens the
prompt. So the button points at the app, which resolves the slug at click time and
redirects out — resolution costs a request, which is fine once per film and impossible
per card on a channel of several hundred. Diary imports get the slug free from the feed's
own links; anything else resolves once and stores it on the entry. Where it cannot be
resolved the link falls back to `/imdb/<id>/`, one further click to the same place.

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

## Things found along the way

**Devise was dropping `username` on sign-up.** It permits only the keys it is told about,
and no sanitizer had ever been configured, so the field on the sign-up form had been
discarded since the day it was added. Fixed in `ApplicationController`; without it none of
this could work, as the username is the handle.

**`lists.letterboxd`** was added so disabling can find exactly the right channel. Matching
on the name would strand a channel the member had renamed.

**A queued sync could rebuild a deleted channel.** Syncs run later than they are queued,
so one can land after the member unticks the box. The flag is now re-read at the point it
matters rather than trusted from when the job started.

**Deleting an account raised `InvalidForeignKey`.** `has_many :lists` had no `dependent:`,
and lists carry a foreign key. Pre-existing, but the profile page's delete button walks
straight into it, so it is fixed here.

**Sync outcomes are recorded on the user.** Ticking the box queues a job; if that queue is
not running there was no signal at all beyond a channel that never appeared. The profile
page now distinguishes working / failed / never-ran, and offers a manual sync.

## Open questions for Nic

1. The list name — you wrote "[Username]'s Letterbox", not "Letterboxd". Followed
   literally; say the word and it becomes "Letterboxd".
2. `letterboxd_score` is on `Entry` as requested, so it is "whoever imported this film's
   score", not per-user. Fine while the channel is private and per-user; it would read
   wrong if one of these entries were copied into a shared channel.
3. Reviews are parsed out of the feed but not stored anywhere. `user_entries.comment`
   would be the obvious home if you want them.
