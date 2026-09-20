# How To Watch — Architecture & Operations Reference

**Purpose:** the map of this codebase. Read this before diagnosing anything; the last
section ("Debugging map") goes from symptom → the file that actually owns the behavior.

**Last verified:** 2026-09-18 against `master` @ `7965536`.

---

## 1. What the app is

A personal/social "channel surfing" app. Users build **lists** (channels) of movies,
series, anime, standalone episodes and fanedits, then play them in an embedded iframe
from third-party streaming providers. Progress (what you've watched, where you are in a
list, which episode you're on) is tracked **per user**, so several users can watch the
same list independently.

Metadata comes from TMDB and OMDB; posters are mirrored into Cloudinary; playback URLs
are generated from provider URL templates.

Built on top of that, and newer: **cable** (§5.9), where a channel plays to a schedule and
you join whatever is already running; **watch parties** (§5.10), where a room watches
together with the host's player as the clock; **voting** (§5.11) on what to put on; and an
**admin dashboard** (§5.14) with the sweeps that tell an admin when a provider, a poster or
an embed has stopped working.

The distinction worth holding on to is that the original app is per-viewer in every
respect, and cable is per-viewer in none of them.

---

## 2. Stack

| Layer | Choice |
|---|---|
| Ruby / Rails | 3.4.5 / Rails 8.1.3.1 (`config.load_defaults` still **8.0** — bumping defaults is a separate, behaviour-changing step; run `bin/rails app:update` to generate `new_framework_defaults_8_1.rb` and work through it) |
| DB | PostgreSQL (`pg_search` for entry search) |
| Auth | Devise (`database_authenticatable, registerable, recoverable, rememberable, validatable`) |
| Views | ERB + Turbo + Stimulus, Bootstrap 5 via importmap, Mustache.js for client-rendered search cards |
| Assets | Sprockets + **`dartsass-rails`** for CSS (compiled to `app/assets/builds`, then digested by Sprockets, with `autoprefixer-rails` as a postprocessor), **importmap-rails** for JS |
| Files | Active Storage → **Cloudinary** (`config.active_storage.service = :cloudinary` in *both* dev and prod) |
| Jobs | Active Job → **Sidekiq** in production (Redis-backed); `:async` in development, `:test` in test (see §8) |
| Redis | Railway `Redis` service on the private network; used by Sidekiq **and by Action Cable**, which watch parties depend on (§5.9) |
| Periodic | `sidekiq-cron`, schedule in `config/schedule.yml`, registered on the Sidekiq **server** only (§8) |
| Hosting | Railway: `how-to-watch` (web) + `worker` (Sidekiq), plus `Postgres` and `Redis` |

---

## 3. Domain model

### 3.1 Core content

**`User`** — Devise account. Flags: `admin` (can edit anything, manage `Source`s, set
default lists, and **view the site as another user** — §5.7), `dark_mode`, `letterboxd_enabled`. On create it
auto-subscribes to default lists and **creates a "<Name>'s Watchlist" list** with
`mobile: true, private: true`, then points `favorite_list_id` at it
(`User#create_default_list`).
- `favorite_list_id` → `List`: **the member's favourite channel** — where
  `/lists/add_to_favorites` files an entry and what the mobile index opens on. One column,
  so there is only ever one; validated to a list the member owns (`favorite_list_is_own`),
  and nullified rather than cascading if that list is deleted. Set from the channel's edit
  page via `PATCH /lists/:id/toggle_favorite`, which checks ownership itself because
  `can_edit_list?` also lets anyone edit a default channel. `User#favorite?`, `#favorite!`
  (moves it), `#unfavorite!`. A channel that **changes hands** takes the previous owner's
  favourite with it (`List#release_stale_favourites`): the row is already written, so the
  validation would otherwise fail that member's *next* save, on an unrelated form.

**`List`** — a channel. Owned by a user; an admin can hand one to another account from its
edit page. `user_id` is permitted in `list_params` for admins only — hiding the field would
not be enough, because `can_edit_list?` is true for *any* member on a default channel.
- `ordered` — true: play in `position` order; false: play a random unwatched entry.
- `private`, `default` (admin-set; everyone auto-subscribes), `mobile` (marks the channel
  created with the account; a record of where it came from, not what it is for — the
  favourite is `users.favorite_list_id`), `reviewable` (prompt for a rating after
  finishing).
- `auto_play` (flows into the embed URL's autoplay param) and `auto_next` (renders the
  up-next card, §5.8). A member's own answer on the profile overrides both.
- `skip_intro_seconds` / `skip_credits_seconds` — where the channel's programmes really
  begin and end. **Nullable, and null is not zero:** null is no opinion. Unlike the two
  above, the channel overrides the member here: a set intro skip (0 included) replaces the
  member's "Start part-way in" randomiser (`List#start_position_for`), though a resume
  position still wins. The credits skip moves the completion mark with it (§5.8).
- `settings` / `sort` — remembered grouping criteria for the show page (`settings` is read
  back as the default grouping; only an explicit `?criteria=`/`?sort=` overwrites them).
- `provider_id` → `Source`: the list's default streaming provider.
- Legacy: `current` (int, list-level "current position" from before per-user tracking),
  `preferred_source` (int 1/2), `parent_list_id`.

**Nesting.** Lists can contain lists. The live mechanism is `ListRelationship`
(`parent_list_id`, `child_list_id`, `position`), many-to-many, with cycle checks in
`List#can_be_added_to?` / `#is_descendant_of?`. `lists.parent_list_id` is the superseded
single-parent version, still declared as a `belongs_to`.

**`Entry`** — one watchable item in a list. `media` is a column of free text, normalized to
lowercase, and drives nearly every branch in the app. `Entry::MEDIA_TYPES` is the set the
app can actually draw — `fanedit`, `movie`, `series`, `anime`, `episode` — since
`entries/_entry_#{media}` is a partial name; every form offers it as a select
(`Entry.media_options`), and the CSV template reads the same constant. It is deliberately
*not* validated: the importers and the OMDB path write `media` from data this app does not
control, and refusing a row over a card it cannot draw would lose the entry entirely.
- Identity: `imdb`, `tmdb`, `series_imdb` (for episodes/series).
- Art: `pic` (remote URL) plus an Active Storage `poster` attachment (Cloudinary).
- Ordering: `position` (integer, within the list).
- Playback: `provider_id` → `Source`, `source_key` (opaque id for "direct" providers).
- `current_id` → `Subentry`: legacy list-level "current episode" pointer.
- Fanedits: `original`, `faneditor`, `fanedit_link` and `fanedit_type` describe a cut —
  what it was made from, who made it, where it was published, and which of
  `Entry::FANEDIT_TYPES` it is (the only one of the four that is validated, since nothing
  but the form writes it). The forms show them only while the media select says `fanedit`,
  and `entries/_entry_fanedit` prints them in place of the year and rating a film's card
  carries, linking the original through `imdb` or `letterboxd_slug` where there is one.

**`Subentry`** — an episode belonging to a series/anime `Entry`. `season` and `episode` are
integers (they were strings until 2026-08-25, which is why old code sorted with
`CAST(NULLIF(...))`). Anime can use an *absolute* episode number via
`Subentry#calculate_absolute_episode_number`, computed only when a template asks for
`%{absolute_episode}`.

**`Source`** (`app/models/source.rb`) — a streaming provider definition. Owns URL
**templates** (jsonb, keyed by media type + `"default"`) with `%{imdb}`,
`%{series_imdb}`, `%{season}`, `%{episode}`, `%{absolute_episode}`, `%{source_key}`
placeholders. `kind` is `imdb` (works for any entry with an IMDb id) or `direct` (needs
the entry's own `source_key`: a Drive file id, mega key, YouTube id, or a full URL).
`autoplay_param` is a query parameter appended as `=1`/`=0` (placed before any `#`
fragment). MEGA is the exception: its player options live in one run of number-letter pairs
behind the key's `!` (`#KEY!900s1a`), so autoplay is a `1a` pair there
(`Source::FRAGMENT_AUTOPLAY_FLAGS`) and the start position is an `Ns` pair in the same run
(`Source::FRAGMENT_RESUME_FLAGS`). **`Source#autoplays?`** is the question to ask, not
`autoplay_param` — it counts both routes, so MEGA reads as capable despite having no
parameter. Three providers cannot be started by the page at all: Google Drive, archive.org
and the custom catch-all. Drive is the one that looks as if it should — its preview is a
YouTube player with `enablejsapi=1` on it that answers the IFrame API in full, but Drive
builds that URL with `origin=https://drive.google.com`, so commands from this app are
dropped (probed from both origins 2026-09-18: 101 replies from Drive's origin, silence from
ours). No query parameter reaches it either, and the file bytes sit behind a virus-scan
interstitial above ~100MB.
Substitution is a plain `gsub`, no eval.

### 3.2 Per-user tracking (the important part)

| Model | Grain | Holds |
|---|---|---|
| `UserEntry` | user × entry | `completed`, `completed_at`, `last_watched_at`, `review` (1–10), `comment`, `player_progress` (seconds, §5.8) |
| `UserListPosition` | user × list | `current_position` (an `entries.position` value) |
| `UserEntryPosition` | user × entry | `current_subentry_id` — which episode you're on |
| `Subscription` | user × list | which channels appear in your sidebar |

**Reads must not write.** `Entry#user_entry_for` / `List#position_for_user` are lookups
returning nil; the `!` variants (`user_entry_for!`, `position_for_user!`) create. Both reads
use the preloaded association when the caller eager-loaded it, so controllers that render
many entries should `includes(:user_entries)` / `includes(:user_list_positions)`.

Rule of thumb: **anything user-specific is in one of these four tables** — and note the
two places that deliberately read none of them: `/cable` (§5.9) and the guide, where what
plays is a question about the clock rather than about you.

The columns `entries.completed`, `lists.current`, and `entries.current_id` are the
pre-multi-user versions and are only touched by legacy paths.

### 3.3 Dead / legacy tables still in the schema

`follows`, `list_user_entries` (superseded by `subscriptions` + `user_list_positions`),
`failed_entries` (write-only error log from CSV/OMDB imports).

### 3.4 Everything else in the schema

Added after the core above, and each one is the subject of its own request flow in §5.

| Model | What it is |
|---|---|
| `CableSlot` | one programme in one channel's day: entry, `starts_at`/`ends_at`, optional `subentry`, optional `break_reel`. **Identical for every viewer** — see §5.9 |
| `CommercialReel` | an advert that fills the gap between programmes on `/cable`. Admin-managed under `/admin/commercial_reels` |
| `WatchParty` + `WatchPartyMembership` | a room watching the same thing at once, addressed by `token`. §5.10 |
| `VoteSession` + `VoteOption` + `Vote` | one round of voting on a channel: a shortlist on a screen, phones voting via QR. §5.11 |
| `Notification` | something the app wants to tell one person. §5.12 |
| `AppSetting` | the site's own switches, **as a single row** — access mode and the up-next threshold. §5.13 |
| `Visit` | deliberately thin traffic counting for the admin dashboard: a cookie token, a day, a page count, an optional user id. No path, no referrer, no address |
| `Current` | `ActiveSupport::CurrentAttributes`; memoises `AppSetting.current` for the length of a request |

---

## 4. Playback: how an embed URL is produced

This is the piece most likely to break, since providers die regularly.

```
Entry#embed_url(subentry:, autoplay:)
  └─ Entry#resolved_source                     app/models/entry.rb
       ├─ entry.provider           (per-entry override)
       ├─ else list.provider       (channel default)
       ├─ if that source is missing/inactive and entry.imdb exists:
       │     first active kind:"imdb" Source by position
       └─ Source#url_for → #build_url → template_for(media) → %{token} substitution
  └─ blank result means nothing can play it; entries#watch redirects with a notice
```

- **Series/anime** pass the user's current `Subentry` so `%{season}/%{episode}` resolve.
- **`entries#set_source`** (the buttons under the player) writes `entry.provider` after
  checking `Entry#eligible_sources`.
- **`pages#watch_now`** has no `Entry` at all — it builds URLs straight from
  `Source#build_url` with a hand-built vars hash, and the switcher swaps `iframe.src`
  client-side (`app/views/pages/_watch_now_source_switcher.html.erb`).
- Seed the providers with `rails sources:seed` (`db/seeds/sources.rb`, create-only so admin
  edits survive). One-time migration from the old columns: `rails sources:backfill APPLY=1`.

**To fix a dead provider: edit that one `Source` row's template** (admin pencil icon under
the player, or `rails console`). No per-entry backfill is needed.

**Nothing constructs a provider URL outside a template.** The legacy `source`,
`source_two`, `preferred_source` and `subentries.source` columns were dropped on
2026-08-23; there is no fallback left, so a blank `embed_url` means the entry genuinely
cannot play. A template whose tokens cannot all be filled yields nil rather than a
truncated URL. `rails sources:audit` reports anything that stops resolving.

**Manual entries**: the form takes a pasted URL (`Entry#source_url`, virtual) and
`Source.classify_url` turns Drive/mega/YouTube/archive links into a direct provider plus
`source_key`; anything unrecognised goes to the catch-all `custom` provider.

**A `Source` also carries, beyond its templates:**
- **Expiry.** `valid_until` makes a source *perishable*; `expired?` / `expiring_soon?` /
  `expiry_state` / `days_until_expiry` read it and `renew!` pushes it out. A daily
  `SourceExpiryScanJob` warns admins through a `Notification` before a domain lapses.
- **Order.** `Source.reorder!` sets the `position` admins drag them into, which is also the
  order `resolved_source` falls back through.
- **Sync adapters.** `SYNC_ADAPTERS[slug]` → `sync_adapter`: `vidsrc` for every vidsrc front
  door, `youtube` for YouTube. `syncable?` is what decides whether a watch party can actually
  drive a provider's player (§5.10), and an adapter is also the only way position tracking,
  the up-next card and the automatic watched mark hear anything (§5.8). MEGA, Drive,
  archive.org and custom have none — MEGA's embed posts nothing to its parent and answers
  nothing sent to it (re-probed 2026-09-18 with the YouTube, player.js, Vimeo and JW Player
  protocols against a playing embed: not one reply), so there is nothing there to drive.
  Alongside
  it: `resume_param` / `resumable?` (`startAt` on vidsrc, `start` on YouTube — start a film
  part-way in, which is how `/cable` joins a programme already running and how up-next
  resumes). **`resumable?` is not the same question as `syncable?`**: MEGA can be told where
  to start even though it will not say a word back, because its start position is a pair in
  the key fragment rather than a query parameter — so it is resumable and not syncable, and
  a provider with no adapter is no longer the same thing as a provider that begins at the
  beginning. Drive and custom still are. Also alongside: `subtitle_param` (cable turns
  subtitles off by default), `player_params` (what a
  player needs on its URL before it will talk at all — YouTube's `enablejsapi=1`, without
  which its embed answers no handshake and the adapter hears silence) and
  `preconnect_origins` (emitted on the player page).
- **`probe_url` / `probe_label`** back `GET /sources/:id/test`: play a known title through
  this provider alone, to answer "is this domain still up" without hunting for an entry.

**Known limitation:** `Subentry#calculate_absolute_episode_number` counts episodes within
one entry, but each season is its own entry here, so it returns the plain episode number.
Nothing active uses `%{absolute_episode}` — only the deactivated vidsrc-cc anime template
does — but reactivating that provider would need this fixed first.

---

## 5. Request flows

### 5.1 Home — `GET /` → `lists#index`
Three buckets: your lists, recently watched (via `user_entries.completed_at`), and
community channels. The community row is for discovery: `List.discoverable_by` leaves out
the viewer's own channels, their subscriptions and the cable dial (`default`), and shows
private ones only to admins. It also leaves out empty ones (`List.non_empty`, the same
recursive count as the card's, so a channel of channels is not empty) — there is nothing to
watch in one, and its creator still sees it in Your Channels. `List.by_recent_activity` orders it by the latest of the
channel's `updated_at`, its newest entry, and anybody's `user_entries` or
`user_list_positions` row in it. `lists.last_watched_at` is never written; don't sort by
it. Each card calls
`list.current_entry(current_user)` for its poster; a channel with nothing of its own falls
back to `List#next_borrowed_entry_for` (what its play button starts, across the channels
inside it) and links with `?channel=` so it is watched from there. The count on each card
is `List.with_entries_count`, a recursive CTE over `list_relationships` that matches
`total_entry_count` — used by the phone channel list too.

### 5.2 Channel page — `GET /lists/:id` → `lists#show`
`load_entries` builds `@entries` as a hash of **section name → entries**, grouped by
`params[:criteria]` — restricted to `ListsController::GROUPING_CRITERIA`
(`Position`, `Genre`, `Year`, `Watched`, `Rating`, `Category`, `Media`, `Length`), anything
else falls back to `Position`. Section order comes from the controller's `@sections`
(`sort_sections` handles the string/number key mix); views must use that local rather than
re-sorting the keys. Child lists are loaded from `child_relationships` and given a
singleton `position` method so they can be interleaved with entries.
`format.text` re-renders just the `lists/_entries` partial (used by the sort/filter JS).

### 5.3 Player — `GET /entries/:id/watch` → `entries#watch`
1. Writes the user's `UserListPosition.current_position` to this entry's position.
2. For series/anime: resolves `@current_subentry` via `UserEntryPosition`, then makes a
   **synchronous TMDB call** for episode details.
3. Computes `@embed_url` (§4); redirects back to the list with an alert if blank.
4. Renders `entries/watch` in `layouts/special_layout` with both sidebars
   (`shared/_sidebar` = channels + now playing, `shared/_entries_sidebar` = the list;
   `shared/_episodes_sidebar` for episodes).

Navigation around the player: `increment_current` / `decrement_current` move **episode**
for series/anime (via `UserEntryPosition`) and **entry** otherwise; `shuffle_current`
jumps to a random unwatched entry.

### 5.3a Player in isolation — `GET /entries/:id/watch_only` → `entries#watch_only`

The same embed with everything else taken away: one iframe, no preloaded second player,
no app JavaScript at all (`layouts/watch_only` deliberately omits the importmap), and no
writes of any kind. It exists to answer "was that the provider or was that us" when a film
restarts, stalls or stutters on the watch page, which carries too much to tell.

Nothing links to it — it is reached by typing the address, and it is signed-in only by
falling through `AccessControl`'s table like anything else unlisted. It is not refused on
a phone as `watch` is; a phone is one of the things worth diagnosing.

How to read a run:

| What you see | What it was |
|---|---|
| `frame-reload` in the console **and** a `[watch_only]` line in the Railway log | the page reloaded — check the `loaded` readout for `reload` or `back_forward` |
| `frame-reload` in the console and **nothing** server-side | the provider re-navigated its own frame |
| neither, and the picture jumped anyway | the player recovered in place; the fault is inside it |

The readout in the corner carries the same log as the console, plus the navigation type,
the joint session history length (it climbs when a frame navigates itself), Chrome's
freeze/resume, visibility, the connection and the JS heap. `Mark` (or `m`) stamps the
moment the picture actually jumped. `copy(watchOnly.log)` lifts the whole run out.

Query parameters: `source=ID` plays the entry on another provider it is eligible for
without editing it (how two providers get compared on the same file), `start=SECONDS`
tests whether a provider honours a resume — and says on the page when it has nowhere to
put one — `autoplay=0`, `subentry=ID`, `hud=0`.

### 5.4 Finishing something
- `entries#complete` — toggles `UserEntry` completion; on completion advances the user's
  list position to the next entry. Renders the `entries/_completion_status` partial.
- `entries#review` / `#complete_without_review` — used by the review modal on reviewable
  lists; both end in `navigate_after_completion`, which redirects to the user's new
  current entry.

### 5.5 Adding content
| Path | Entry point | Notes |
|---|---|---|
| Add a whole season | `episodes_controller.js` → `POST /lists/:id/add_season` | → `SeasonImporter`; one TMDB call (two for anime past season 1) |
| Add a single episode | `entries#create` with `season`/`episode`/`tmdb` | → `EpisodeImporter`, creating a standalone `media: "episode"` entry |
| Global navbar search | `list_search_controller.js` → `POST /lists/:list_id/entries` | `entries#create` re-fetches from OMDB, then `Entry.create_from_source`. Off a channel page it asks the picker which channel first |
| "+ Details" on a search result | `list_search_controller.js#details` → `GET /lists/:id/entries/new?imdb=…` | → `EntryPrefill`. **Creates nothing**: the form opens filled in and the row exists only once Create Entry is pressed |
| By hand | `GET /lists/:id/entries/new` → `entries#create` with `custom` | The custom-entry form: a fanedit, a personal cut, anything the APIs describe badly. No search box of its own |
| A spreadsheet of them | `GET .../entries/csv_template`, `POST .../entries/import_csv` | → `EntryCsvTemplate` / `EntryCsvImporter`; inside the request, capped at `MAX_ROWS` |
| A YouTube playlist | `POST .../entries/import_youtube` with `playlist_url` | → `YoutubePlaylist` (Data API) / `YoutubePlaylistImporter`; inside the request, capped at `YoutubePlaylist::MAX_VIDEOS`. One entry per video on the `youtube` provider, never a series with subentries (they have no `source_key`). Re-running adds only new videos |
| Phone, on a channel | `mobile_shell_controller.js#add` → `POST /lists/:list_id/entries` | the same `entries#create` the navbar uses; the turbo stream reply is ignored |
| Phone, home page heart | `mobile_shell_controller.js#favourite` → `POST /lists/add_to_favorites` (JSON) | → `ImdbEntryImporter` on `current_user.favorite_list`; 404s when there is none |
| Phone, home page + | `mobile_shell_controller.js#addToChannel` → `POST /lists/add_to_list` (JSON) | the picker in `lists/index_mobile` offers only the member's own channels, which is all `add_to_list` accepts |
| Top-rated episodes | `lists#top_entries` → `ImdbScraper` | scrapes IMDb search HTML |
| Watch without saving | `GET /watch_now?imdb=…` → `pages#watch_now` | transient, no DB write |

The `/entries/new` page used to carry a second search of its own (`search_controller.js`,
its own mustache card templates, a Movie/Series/Anime tab row). It does not any more: the
navbar search is on every page, and its "+ Details" button reaches this form with the
metadata already in it. The page is now the manual form plus the two bulk ways in: the CSV
round trip and a pasted YouTube playlist.

`Entry.create_from_source` normalizes OMDB payloads (`OmdbApi.normalize_omdb_data`) and, on
failure, records a `FailedEntry` and returns an error **string** — callers must check
`entry.is_a?(Entry)`.

### 5.6 View as another user (admins)
`app/controllers/concerns/impersonation.rb`, included by `ApplicationController`.
`current_user` is what every permission check reads (`admin?`, `can_edit_list?`, the four
per-user tracking tables), so the concern overrides it to return the impersonated user
and keeps the real account in **`true_user`**. There is no parallel "pretend" code path,
which is the point: what the admin sees is what that user's own session renders.

- Start/stop: `POST /impersonate/:id` / `DELETE /impersonate` (`ImpersonationsController`).
  The admin check reads `true_user`, so switching straight from one user to another works.
- UI: `shared/_impersonation_menu` in both navbars (application + mobile) and
  `shared/_impersonation_banner` in all three layouts — the watch page's
  `special_layout` has no navbar, so the banner is the only way out from there.
- `true_user` is deliberately confined to that concern, the two partials and the
  controller. Anywhere else it would show the admin something the real user's session
  would not, which defeats the whole feature.
- **Writes land on the impersonated user.** Marking something watched, the dark-mode
  toggle, a Letterboxd sync — all of it hits their rows, because that is the same code
  path they run. This is for checking what a page looks like, not a read-only preview.
- `/sidekiq` is mounted through Devise's route-level `authenticate`, which only ever sees
  the Warden user (still the admin). The extra `constraints` lambda in `config/routes.rb`
  on the session key is what actually hides it while impersonating.

### 5.7 Mobile
Detected by user-agent regex duplicated in `ListsController#mobile_request?` and
`EntriesController#mobile_request?`. Mobile requests render `*_mobile` views with
`layouts/mobile`: one bar (home, search field, menu) driven by `mobile_shell_controller.js`,
and a `#mobileResultTemplate` for search results. The phone view plays nothing.

The controller is told `mode` (`search` or `none`; a page that sets neither gets no field)
and `listId`. On a channel a result carries one "+ Movie/Series" button for that channel.
On the home page there is no channel behind the search, so a result carries a heart
(straight into the favourites) and a + that opens a full-screen picker of the member's own
channels, favourite first, with its own filter field. The home page's rows are the channels
the member follows, favourite first (`ListsController#mobile_channels_for`); the picker's
are the ones they own (`#mobile_add_channels_for`) — not the same set.

---

### 5.8 Progress and up next

`UserEntry#player_progress` holds where the viewer got to, in seconds. It is written by
`POST /entries/:id/progress` — **POST rather than PATCH because `navigator.sendBeacon`,
which is how the position is saved as the page goes away, can only send POST.**

All of this rides on a player adapter (§4): `services/vidsrc_player.js` and
`services/youtube_player.js` hand `player_progress_controller` reports of one shape —
`event`, `status`, `progress`, `duration` — so nothing downstream knows which it is hearing.
YouTube reports about four times a second and has no seek event, so its adapter passes steady
playback on once a second and calls a jump in position a seek. On MEGA, Drive and the rest
there is no position, no card and no automatic watched mark.

Completion is a fraction of runtime, not a position: `UserEntry::COMPLETION_FRACTION`
(0.95). The **up-next card** is timed separately, by `AppSetting#up_next_lead_seconds`
(15): the card appears that long before the end and counts down to the end itself. The
event carries `detail.seconds`, what was left of the programme when the crossing report
arrived — up to five seconds after the mark on vidsrc — and
`auto_advance_controller#countdownFor` counts that, capped at the lead. Raised any other way
(coming out of fullscreen, or by the player's own `completed`) it counts the lead. One
number deciding both when and how long, because two of them can disagree and no reading of
"the countdown" wants them to.

**The runtime is the file's, where the player reports one.** `UserEntry.runtime_for` and
`player_progress_controller#lengthOf` take the player's reported duration over
`entries.length`, unless it is under `UserEntry::FILE_SHARE_FLOOR` (half) of it, which is
something other than the film. The catalogue is a claim — TMDB rounds up, providers hold
other cuts, YouTube uploads carry intros — and a mark taken from it is not the end of what is
playing. Too long, and the card only ever came up on the player's own `completed`, after the
film had finished; too short, and it moved the viewer on with minutes still to run. The
resume cutoff has no report to go on and still uses the catalogue.

**The catalogue's figure is `Entry#runtime_minutes`**: the entry's own `length` for a film,
the *episode's* for a show, and never the show's. A series' own `length` is the whole show
end to end (594 minutes for Band of Brothers), and timing by it put the watched mark hours
past the end of an episode. Every caller passes the episode playing: the progress report,
`resume_position`, `List#start_position_for`, `User#random_start_for`, the watch page and the
cable label. `CableSchedule.runtime_minutes` is the same answer plus a five-minute floor.

`AppSetting#up_next_mark_for` applies the floor — never earlier than the completion mark —
and `player_progress_controller` applies the same rule client-side. It has to be a floor at
the point of use rather than a validation: whether 15 seconds is too long a lead is a
question about the film's length, and fifteen seconds before the end of a two-minute clip
is well before it counts as watched. Both routes to the card are gated on the film counting
as watched, so a mark earlier than that is a card that never appears.

**A channel's credits skip shortens the runtime before any of this is worked out.**
`List#skip_credits_seconds` comes off the runtime in `UserEntry.completion_mark_for` and in
`player_progress_controller#runtimeFor`, so the completion mark, the resume cutoff and the
up-next mark all move to where the channel says the programme ends, and the countdown runs
out there. They move together because advancing ticks nothing off: a completion mark left at
the end of the file would never be reached by a viewer the card moved on. The progress URL
carries `?channel=` so the server applies the skip of the channel being watched from
(`watching_channel`, which refuses a channel that does not hold the entry). A skip as long as
the entry is ignored on both sides.

**Fullscreen is not interrupted to show the card.** `entries/_auto_advance_modal` is
rendered inside `.cinema__screen`, which is the element that goes fullscreen, so the card
draws over the picture. `player-progress:up-next` is **cancelable**: the card cancels it
when it takes it, and only when nothing does — auto-next off for the channel, or a viewer
who pressed Stop — does the player hand the screen back, which is what leaves the ring of
controls reachable.

`POST /entries/:id/progress` normally answers `204`. The one report that crosses the
completion mark answers with a **turbo stream redrawing the watched eye**, because the page
it sits on is not going to be rendered again while a film plays on it. Everything else
stays `204`: the report arrives on every pause and seek, and a stream per report would
re-render the card twelve times a minute to say what it already says.

That same crossing also **moves the owning channel's `UserListPosition` on** to the next
unwatched entry (`UserListPosition#move_past!`), so reopening the channel does not replay
what just ended. Only on an ordered channel, only while the position still points at this
entry (the unload report can land after the next page has recorded itself).

A series or anime cannot use that crossing: its single `completed` flag is ticked by the
first episode to finish. Instead the watch page names the episode on screen
(`?subentry=`) in its progress URL, and **every** report that counts as watched
(`UserEntry#watched_by?`) moves the show's `UserEntryPosition` to the next episode, which
also clears `player_progress`. After the last episode it is the channel that moves on.
Reports naming an episode the viewer has since left are dropped whole, so a pause in the
credits cannot plant the old episode's position on the new one. Because the show has
usually moved on before the up-next card fires, the card and the ring's arrows pass the
same `?subentry=` to `increment_current` / `decrement_current`, which step from that
episode rather than the stored one — otherwise the card would skip an episode.

`PATCH /entries/:id/runtime` is the player filling in a runtime the catalogue lacks. It
fills a gap (anything under `CableSchedule::MIN_MINUTES`) and never overwrites. The watch
page (`player_progress_controller#learnRuntime`) and the cable page both send it once, and
only when what is playing has no runtime: for a show that means the episode, never the show.

### 5.9 Cable — `GET /cable`, `GET /cable/:id`, `GET /cable/guide`, `GET /cable/0`, `GET /cable/1980s`

Channels that are **already running** when you turn them on. This is the one part of the
app where nothing is per-viewer, and the module comment in `app/services/cable_schedule.rb`
is emphatic about why: two people opening the same channel at the same second must see the
same frame, so nothing here reads `UserListPosition`, `UserEntryPosition` or
`player_progress` — **and nothing here writes them either.** Marking something watched is
the one exception and it goes out through the ordinary `entries#complete` route, because
that is something the viewer chose rather than a side effect of rendering a page.

- A day is laid out in advance into `cable_slots`, entries shuffled and laid end to end
  from midnight to midnight in `CableSchedule::DEFAULT_ZONE` (`America/Toronto`, overridable
  with `CABLE_TIME_ZONE`) — not UTC, so "tomorrow" means the viewer's tomorrow.
- Slots start and end on a five-minute grid (`BREAK_GRID`), so a listing reads 8:00 and 9:05
  rather than 8:07 and 9:53. Whatever is left between the film ending and the next mark is a
  commercial break, filled by a `CommercialReel`. A break is 0–4 minutes, never more.
  `CommercialReel.for_year` picks the reel when the day is dealt: nearest to the film's
  year, then narrowest span (a 1987 reel beats a 1980s one), then at random, so a year
  with several reels rotates through them from break to break.
- **A programme with no runtime is not scheduled.** A runtime under `MIN_MINUTES` (5) counts
  as none. A series offers only the episodes with a runtime of their own
  (`CableSchedule.runtime_minutes`); the show's own `length` is never read, because for a
  series it is the whole show end to end. Timing episodes by it put 9h54m of Band of Brothers
  on the guide. A flat guess used to fill gaps and was dropped too: short cuts the film off,
  long starts it over. `MissingRuntimeScanJob` fills gaps from TMDB weekly and reports the
  rest. `MAX_SLOTS_PER_DAY` (200) is the backstop.
- **A player that will not play gets the "Please stand by" card** (`cable_standby_controller`,
  `please_stand_by.png`). There are two triggers: YouTube's `onError`, for a reel or a
  YouTube programme; and a fresh vidsrc frame that has posted no `PLAYER_EVENT` within 20s.
  A frame adopted from a warmed spare (`data-adopted`) is never judged by silence, because
  spares can play without reporting (§6a of VIDSRC.md). A break with no reel at all shows the
  "We'll be right back" interlude instead: that is a gap, not a fault.
- Entries on a **direct provider the page cannot start** get no slots (`unschedulable?`).
  A channel is the programme already running when you turn it on, and Drive, archive.org and
  custom all wait for their own play button — and take no start position either, so pressing
  one an hour into a slot begins at the beginning, an hour behind everyone else on that
  channel. Direct providers only, deliberately: on an imdb provider the same signal is
  `autoplay_param`, which the source form calls optional, so reading it here would take the
  whole dial dark for a blank field. A channel left with nothing schedulable goes off air,
  which `plan` already handles.
- `CableScheduleJob` deals tomorrow daily and fills today **only if it is empty**
  (`ensure_day!` leaves an existing schedule alone, so it can never pull a running programme
  out from under anybody). `CableSchedule.prune!` keeps `RETAIN_DAYS` (2).
- `cable#show` and `cable#guide` also lay out a missing day on the way through, so the dial
  never has a dead channel on it after a deploy or a newly-defaulted channel. `show` deals
  the one channel with `ensure_day!`; the guide covers the whole dial across a two-day
  window, so it uses `ensure_days!`, which answers "which of these are already laid out"
  in **one** query rather than an `exists?` per channel per day. A dial whose schedules are
  dealt costs the same whether it holds two channels or six —
  `spec/requests/cable_guide_queries_spec.rb` is what keeps it that way.
  A channel with nothing playable on it produces no slots, so it is re-planned on each
  visit; that is what lets it pick up an entry that becomes playable, and it is the one
  case where the guide's cost grows with the dial.
- **Route order is load-bearing**: `get 'cable/guide'`, `cable/listings` and `cable/0` must
  stay above `get 'cable/:id'`, or "guide" is read as a channel id, cast to nothing, and
  quietly serves channel one -- and `0` serves channel one instead of the trailers.
- The guide renders in the *viewer's* zone (`params[:tz]`) even though the schedule itself
  is a set of fixed instants.
- **The way off a channel** is `watch_entry_path(entry, channel:, subentry:)` — the ordinary
  player, from the beginning, counting towards what the viewer has seen. Three things offer
  it: the banner's headline, the guide panel's, and the "Start from the beginning" button in
  each of those (`cable-hud__start`, `tvguide__start`). The buttons follow whatever is being
  *described* rather than whatever is playing, so the banner's arrows and a pointer moving
  across the grid both re-aim them. None of the three carries `data-cinema-move`, so all
  three are navigations out of cable rather than a change of channel.
- **`CableSchedule.on_air_now`** is the whole dial in one query — every channel with
  something on, paired with its slot and its number, shaped like `guide`'s rows. It exists
  for the sidebar's Now Playing card (§6), which asks it on every page that draws a sidebar.
- **Channel 0, Coming Attractions** (`cable#trailers`, `GET /cable/0`) is the one channel
  that is not a schedule: trailers back to back from `TrailerReel`, the same reel `/trailers`
  plays with a film card in place of the banner. It is not a list and has no slots, and it is
  never in `CableSchedule.channels`, so the schedule, the Now Playing card and `/admin/cable`
  know nothing of it. Where a page has to name it, `CableHelper::COMING_ATTRACTIONS_ID`
  (`"0"`) stands in for a list id.
  - The dial is a ring through 0, built by `CableHelper#cable_sibling_path` rather than
    `CableSchedule.sibling`, which still deals only in lists. Up from channel one is 0, up
    again wraps to the last channel, down from the last comes back to 0. `/cable` still
    opens on channel one.
  - What is on is per-viewer -- a random pick, with the last `TrailerReel::REMEMBERED` videos
    kept in `session[:trailers_seen]` -- and it moves on when the YouTube embed reports the
    trailer ended or refused (`trailer_reel_controller.js`, which needs `enablejsapi=1`), not
    when the clock says. Nothing is written to the per-user tables.
  - **Both kinds of page answer both kinds of move.** A change of channel keeps the screen
    element it started on and swaps only `#cinema-chrome`, so `cable/show`'s screen listens
    for `trailer-reel:next` and `cable/trailers`' listens for `cable-clock:move` / `warm`.
    Drop either and a move after tuning across is a full page load that closes the guide
    and leaves fullscreen.
  - In the guide it is one block across the whole window. While it is the channel on screen
    the panel describes the current trailer's film from the `data-guide-*` attributes on the
    chrome (`cable_guide_controller#withLive`), because the banner -- the other way to the
    film -- is hidden while the guide is up. The phone's listings leave the row out:
    `@coming_attractions` is set only by `cable#guide`.
- **The decades** (`CableEra`) close the dial, always last and always in this order: 20s, 10s,
  00s, 90s, 80s, 70s, 60s, Golden Age (1900-1959). They are channels with no list behind them
  -- a list on the dial has to be `default`, which subscribes every account and fills every
  sidebar -- so they are eight frozen instances defined in code, addressed by key
  (`/cable/1980s`, `/cable/golden-age`).
  - `cable_slots` names its channel by `list_id` **or** `era`, never both and never neither
    (check constraint `cable_slots_one_channel`). `CableSchedule.slots_for`, `slots_for_all`
    and `slot_owner` are the only places that know the difference; `CableSlot#channel_key`
    is what the whole-dial reads group by.
  - **`CableSchedule.dial`** (lists, then decades) is what numbers, steps along, lists and
    lays out the channels -- the guide, Now Playing, the job, the backfill task and Rebuild.
    **`channels`** (lists only) is what `/admin/cable` adds, removes and reorders. Anything
    that deals or reads the whole dial must use `dial`, or the decades quietly go dark.
  - A decade plays `CableEra#entries`: public entries whose `year` falls in range, one per
    film by `catalogue_key`, the copy filed first. Standalone episodes count one by one, so a
    show imported an episode at a time is a large share of its decade.
  - Its programmes lead back to the channel each entry was filed in -- the banner's channel
    name, the guide panel's link (`CableHelper#cable_home_list`, `#cable_channel_label`) and
    the watch link (`#cable_watch_path`). **Never put a decade key in `?channel=`**: the watch
    page reads it as a list id. `CableSchedule.find_channel` asks for the key before the list
    for the same reason, and the keys are spelled as years so none of them reads as a number.

### 5.10 Watch parties — `resources :watch_parties, param: :token`

The only Action Cable feature, and the only reason the `redis` gem is pinned (see the
Gemfile comment: Action Cable's pubsub adapter declares `redis < 6`, so on 6.x every
broadcast raises `Gem::LoadError` while the socket still connects and the subscription still
takes — nothing is ever delivered).

- The **host's player is the clock**: it reports where it is and everyone else is moved to
  match. When the host changes episode the whole room follows.
- Addressed by `token` rather than id, because the token *is* the invitation — `show` is the
  link people paste to each other.
- `WatchPartyContext` keeps the token in the **session**, so a room follows the person
  around the site instead of belonging to one page, and drops a token whose party has closed
  so a dead room does not put a bar on every page.
- Only providers where `Source#syncable?` — vidsrc and YouTube — can actually be driven. On the rest the party
  still holds everyone on the same entry and shows how far apart they are; it just cannot
  close the gap.
- `CloseAbandonedWatchPartiesJob` runs every 15 minutes. `ABANDONED_AFTER` is 2 minutes,
  comfortably longer than the 45-second presence staleness, because a reload is a disconnect
  too; the `created_at` age check keeps a room from being reaped in the seconds between the
  host opening it and their browser opening the socket.

### 5.11 Voting — `resource :vote` nested under a list

A shortlist put on one screen, voted on by the phones in the room via a QR code (`rqrcode`).
`VoteSession.open_for(list, count)` replaces whatever round was open and draws its options
**at random** rather than taking the first few — the point is to decide between things
nobody has already picked out. `standings` breaks ties by ballot order so a tie reads the
same way twice instead of shuffling under whoever refreshes. `VotesController` deliberately
**skips `AccessControl`**: a room scanning a QR code is a different question from who may
browse the site.

### 5.12 Notifications — `resources :notifications`

Deliberately generic, so a second table is never needed: `kind` says what sort of thing it
is, polymorphic `subject` points at what it is about, and anything kind-specific lives in
`data`. The admin-facing kinds are sweep results — `source_expiring`, `broken_poster`,
`unplayable_embed`, `missing_runtime` — and `ADMIN_ONLY_KINDS` is enforced **on write and
again on read**, so an account that loses its admin flag stops seeing them without needing
a sweep.

`dedupe_key` is what makes dismissal safe for a warning that is really a *state* rather than
an event: it carries the date being warned about, so renewing a provider retires the
dismissed row and a later warning about the new date is a new notification.

**`new_episode`** is the first kind that reaches members, and the first that is an event.
`NewEpisodeScanJob` (Thursdays) runs `NewEpisodeNotifier` over every `media: "series"` entry:
`NewEpisodeImporter` adds the episodes after the last one the entry holds, and each one
added is announced to the channel's owner (not its subscribers), keyed by subentry, in the same
transaction as the subentry itself. A whole show takes new seasons; a `SeasonImporter`
season ("<Show> - Season N") only takes more of season N. Entries holding no episodes are
skipped, not filled.

TMDB lists episodes weeks before they air, titled and summarised, so an episode is only
believed when it is at or before the show's `last_episode_to_air`, its `air_date` is
strictly before today, and it carries a real title and a runtime — the last two waived
after 14 days, when what TMDB has is all it is going to have. The TMDB id must also be
**confirmed** to be the entry's show (by TMDB's imdb id, or failing that the imdb lookup
leading back to it), because entries with a wrong TMDB id exist.

### 5.13 Who gets in without an account

`AppSetting#access_mode` is one of `secure` (nothing — sign in first), `moderate` (browse:
the channel index, a channel's page, search) or `open` (browse **and** watch). Writes always
need an account: there is nowhere to record a position, a review or a new channel without
one.

The permitted actions are a table in `app/controllers/concerns/access_control.rb` rather
than declarations scattered across controllers, so the whole answer to "what can a stranger
reach" reads top to bottom. Two rules hold it down whatever the table says: **only GETs are
ever allowed through**, and **anything unlisted falls through to Devise**, so a new
controller is closed until somebody decides otherwise.

What a visitor who is let in sees is meant to look like the site, not a stripped-down
fallback:

- **Dark**, as a new account would (`ApplicationHelper#theme_class`). The vote room keeps
  the light theme it was built against.
- **The sidebar**, on the pages the table opens (`ApplicationController#sidebar_visible?`),
  and not on the sign-in screens or the vote room. It lists the public channels on the cable
  dial in place of subscriptions, with the Now Playing card below as usual.
- **A picture on every home-page card**: one entry drawn at random from what the channel
  holds (`ListsController#sampled_card_entries`). It only picks entries that have a
  picture, from public channels, using a single `DISTINCT ON` query for all channels with
  entries of their own. A channel that holds nothing with a picture still shows stand-by.
- **Links that go somewhere the visitor can reach.** `AccessControl#may_watch?` says whether
  the mode lets them play. Where it does not, the card, the sidebar rows and Now Playing
  open the channel's page, not a watch URL that would bounce to sign-in.

`AppSetting` is a single row, enforced by an `only_row` validation — every reader takes
`first`, so a second row would be settings nobody can see and an edit that appears to do
nothing. It is created on first read, so a fresh database needs no seed, and memoised per
request through `Current`.

### 5.14 Admin dashboard — `/admin`

`Admin::BaseController` turns away everyone else. The dashboard shows `AdminStatistics`
(counts and grouped counts over one seven-day window, gathered so the view holds no
queries), the site switches, and buttons that run the poster, embed and new-episode sweeps
on demand —
the same jobs the weekly schedule runs, so there is one implementation and one set of
results. `POST reset_source` moves every channel onto one provider.
`Visit` backs the traffic figures.

**`/admin/entries`** (`Admin::EntriesController`) is every entry in one table — name,
channel, media, runtime, the provider it plays from, and stream state — sortable by each.
Reached from the dashboard's Entries figure. Built for its length rather than paginated:

- Sorting is server-side on a whitelisted column (`?sort=&direction=`), blanks last. The
  source column sorts in Ruby by `Entry#resolved_source`, not by a SQL copy of that rule.
- Only the displayed columns are selected, channels and sources preloaded — three queries.
- **The row actions are one toolbar**, moved by `entry_table_controller.js` into whichever
  row is hovered or focused and pointed at it by filling `ENTRY_ID` in its link templates.
  Per row they were seven of each row's sixteen elements (56k DOM nodes → 32k).
- The pencil loads that one entry's reduced form into a single modal `<turbo-frame>`; save
  and delete answer with a stream for that row only. The controller holds the toolbar by
  reference because a redrawn or removed row takes it out of the document, and it queues an
  open that arrives while the modal is still fading out — Bootstrap ignores `show()` then.
- **The stream mark is its column's switch.** Pressing it sends `PATCH
  /admin/entries/:id/stream` with the value wanted (never a bare "flip"), written straight
  to the column. Delegated from the table body; the marks are operable through `role` and
  `tabindex` rather than a wrapper element per row.
- **`/admin/subentries`** (`Admin::SubentriesController`) is the same table for every
  episode, sharing the toolbar, modal and sort headings. The toolbar's link templates fill
  `ROW_ID` from the row's own id and `PARENT_ID` from its `data-parent`, since an episode is
  watched through its show (`/entries/:show/watch?subentry=:id`). Two columns differ because
  the data does: the source is the show's (an episode has no provider), and there is no
  stream column (`subentries` has no `stream`). The show is not editable from here — moving
  an episode would strand its old show's `current_id` and members' saved positions.
- A full layout of this page is expensive (~50–140ms a time, more under DevTools), and
  opening a Bootstrap modal forces more than one. Measure it in a **foreground** tab: a
  background one has its timers and animation frames throttled, which reads as multi-second
  stalls that are not the page's.

---

## 6. Front end

- **No JS build step.** `config/importmap.rb` pins everything; controllers are eager-loaded
  by `app/javascript/controllers/index.js`.
- **Mustache templates live in the layouts** (`layouts/application.html.erb`,
  `layouts/mobile.html.erb`) as `<template id="…">` blocks; the search controllers look
  them up by id. If search results render blank, the template id and the controller's
  `document.querySelector` have drifted apart.
- **Stimulus controllers** (`app/javascript/controllers/`):
  `search` (in-list TMDB search), `list_search` (navbar), `mobile_search`,
  `episodes` (season/episode browser), `poster_selector`, `edit` (entry modal),
  `completed`, `sort`, `slider`, `view_toggle`, `randomize`, `trailer`, `hover_play`,
  `link`, `button`, `entry_anchor`, `entries_sidebar`, `auto_advance` (**countdown
  disabled in code**). Unused: `cinema`, `frame_loader`, `omdb`, `hello`.
- **The sidebar's Now Playing card** (`shared/_sidebar`) answers two different questions
  depending on where it is drawn. On the player there is a picture beside it and the card is
  a caption for that picture: it names `@entry`, and `cinema_navigation_controller` swaps
  `#nowPlayingContent` along with the frame and the chrome when the viewer changes channel.
  Everywhere else nothing of theirs is playing, so it shows the **cable dial** — whatever is
  on air this second — and pressing it tunes to that channel. Which channel rotates, one
  step per render, from a position kept in the session
  (`ApplicationController#cable_now_playing`). It falls through to the stand-by card only
  when the whole dial is dark.
- **Modals are page-level, never per card.** The trailer modal, the poster picker and
  the review modal are rendered **once** per list page (`shared/_trailer_modal`,
  `shared/_poster_selector_modal`, `entries/_review_modal_list`). Each is opened by a
  plain Bootstrap trigger on the card, and its controller reads the entry off
  `event.relatedTarget` in `show.bs.modal` -- so the markup holds nothing entry-specific
  and one modal serves every card. They used to be rendered inside the card partials:
  on a 1,203-entry list that was 3,610 modals, 1,203 `<iframe>`s and 1,202 copies of the
  same script, 12.7 MB of HTML and ~3.8s of view rendering with the query count already
  flat. **Do not put a modal, a `form_with`, or an inline `<script>` in an entry card
  partial** (`entries/_entry_movie` and its four siblings) -- each one is paid ~1,200
  times. `spec/requests/list_show_payload_spec.rb` fails if a per-entry modal comes back.
  The watch page is the exception: it shows one entry, so it keeps its own
  `entries/_review_modal` with turbo disabled, answering the same `#reviewModal` id.
- **The card's tabs are built on hover and fetched on open**, for the same budget.
  `card_panes_controller.js` is attached to `.card-details` by a bare `data-controller` --
  the only thing the tabs cost the markup, about thirty bytes -- and builds the Synopsis /
  Details / Notes strip, the scroll-unlock caret and the pane the first time the pointer
  lands on a card. Opening Details or Notes fetches `GET /entries/:id/panes`
  (`entries/_card_panes`), which is why that fragment may hold the `<textarea>` a card may
  not: `entry_card` collapses whitespace between tags, and a textarea is the one element
  where that would change its contents. `EntryPanesHelper::ALREADY_ON_CARD` is what keeps
  the pane from repeating what the card above it already prints, per media type. The note
  saves to `PATCH /entries/:id/note` on blur; it is a column on the entry -- the channel's
  note, not the reader's -- so `check_edit_permissions` covers it, and a member's own
  thoughts remain the review on `UserEntry`.
- **The synopsis does not scroll.** `.card-plot` is clipped and faded; the caret above
  unlocks one card at a time and leaving the card re-locks it. It was `overflow-y: scroll`,
  which made every card with a long plot a scroll trap on a page of 1,200 of them.
- **`services/tmdb_search_behavior.js`** holds the six methods `list_search` and
  `mobile_search` share (`tmdbSearch`, `tmdbShow`, `showOverlay`, `handleClickOutside`,
  `hideResults`, `showToast`), applied to both prototypes with `Object.assign`. If you are
  looking for one of those methods, it is not in the controller file. It lives under
  `services/` because Stimulus eager-loads `controllers/` and would register a mixin as a
  controller. `search_controller` keeps its own copies — its versions differ.
- **`spec/javascript_modules_spec.rb`** is the only test coverage this JavaScript has. It
  is static: it fails on an unpinned bare import, a method defined twice in one file, a
  `data-action` pointing at a method no controller defines, and a `data-*-target` no
  controller declares. All of those otherwise show up only in the browser console — or
  not at all, since Stimulus ignores an undeclared target silently.
- **Font Awesome** is self-hosted (pinned to 6.7.2; v7 renames icons). Its `scss/` is
  vendored in `vendor/sass/`, and the webfonts are committed to `public/webfonts` and
  served straight from there — `$fa-font-path` points at `/webfonts` because Dart Sass
  cannot emit Sprockets' digested filenames.
- **SCSS** is compiled by Dart Sass, *not* Sprockets: `application.scss` →
  `app/assets/builds/application.css`. External imports need explicit load paths in
  `config/initializers/dartsass.rb`, which points at `vendor/sass/` — Bootstrap's and Font
  Awesome's Sass sources, copied from the npm packages of the same versions and committed.
  They are not read from `node_modules` and not taken from the `bootstrap` /
  `font-awesome-sass` gems: node is absent from one Railway builder at precompile time
  (see the deployment guide), and both gems depend on `sassc`, the `ffi` chain #28 removed.
  Run `bin/dev` in development — it starts `dartsass:watch` next to the server;
  `assets:precompile` handles the build on deploy.
- **SCSS** in `app/assets/stylesheets`: `config/` (variables, colors, fonts),
  `components/`, `pages/`, `themes/_light_mode.scss`. Dark mode is the default; the theme
  is a body class driven by `users.dark_mode`, and is dark for a signed-out visitor
  everywhere but the vote room (§5.13).

---

## 7. Services (`app/services/`)

| Service | Role |
|---|---|
| `OmdbApi` | OMDB lookups; rotates across `OMDB_API_KEY_1..3` by `sample`. Also fetches series episodes (TMDB when a `tmdb` id exists, else OMDB). |
| `EpisodeImporter` | one standalone `episode` entry from TMDB |
| `SeasonImporter` | a season: parent entry + a `Subentry` per episode, incl. anime absolute numbering |
| `ImdbEntryImporter` | one movie/series entry from an IMDb id via OMDB |
| `PosterCandidates` | poster options for the picker (TMDB, OMDB, recent list entries) |
| `TmdbService` | the TMDB client: typed endpoints (`fetch_show`, `fetch_season`, `fetch_episode`, `find_by_imdb_id`, …) through one `get_json` with timeouts, raising `TmdbService::RequestError`; plus trailers, posters and image URL validation |
| `ImdbScraper` | scrapes IMDb search results for top-rated episodes (HTTParty + Nokogiri) |
| `UrlCheckerService` | fetches a source URL and checks for a non-empty `<title>` → sets `entries.stream`. **Not used for MEGA**, whose embed page has no `<title>` and so failed every time |
| `MegaAvailability` | asks MEGA's API whether a MEGA link plays: the file exists (`g` without `g: 1`, so no transfer quota is spent) and the link's key decrypts its attributes. `:available` / `:missing` / `:unknown`, fifty links a request; `:unknown` never writes "broken". `Entry#check_source` uses it for MEGA, and `entry:check_mega` re-checks in bulk |
| `ImageRepairService` / `PosterMigrationService` | fix broken `pic` URLs; copy `pic` → Active Storage/Cloudinary. Return `{status: :migrated|:repaired|:valid|:failed|:skipped|:error, message:}` — **status values are symbols** |
| `EntryPrefill` | Builds an **unsaved** Entry from OMDB (or TMDB, for a standalone episode) for the custom-entry form to open filled in |
| `EntryCsvTemplate` / `EntryCsvImporter` | The blank sheet `/entries/new` hands out and reads back. `COLUMNS` is the contract between them; a row with an `imdb` id is looked up and what was typed wins over what the lookup said |
| `CsvImporterService` / `CsvExporterService` | seed/export via `db/seed_data/*.csv` — the *seed* pair, unrelated to the two above |
| `YoutubePlaylist` | Reads a public playlist through the YouTube Data API: title, and per video the id, title, description, runtime, thumbnail, `embeddable` and age restriction. Refuses a playlist over `MAX_VIDEOS` before reading it; raises `YoutubePlaylist::RequestError` with a sentence fit for a flash |
| `YoutubePlaylistImporter` | Files that playlist into a channel. A title numbered `S1 EP1` / `S01E02` / `Season 2 Episode 10` becomes an `episode` of the playlist, anything else a `fanedit`. Skips videos already in the channel (by id, `?si=` suffix and all) and ones with embedding off; adds age-restricted ones and names them |
| `DatabaseBackupService` / `DatabaseMigrationHelper` | `rake db:backup:*`, pg_dump + Active Storage manifest |
| `LetterboxdFeed` | Reads a member's public Letterboxd diary (RSS) |
| `LetterboxdList` | Reconciles that diary into a channel |
| `LetterboxdFilm` | Builds links to a film on Letterboxd |
| `CableSchedule` | Lays out and reads the cable day (§5.9). `module_function`, no per-user state |
| `CableEra` (`app/models`) | The decade channels at the end of the dial -- not a table, eight frozen instances, each dealt from the public catalogue by year (§5.9) |
| `CommercialCatalog` | The reels available to fill a break |
| `TrailerReel` | A random trailer off `entries.trailer`, for `/trailers` and channel 0 (§5.9). Picked by YouTube video rather than by entry, so a film filed twice is not twice as likely; public channels plus the viewer's own private ones; recent picks passed over. Builds the embed on the `youtube` Source template |
| `SourceCatalog` / `ChannelSourceReset` | The provider list; moving every channel onto one provider |
| `VidsrcAvailability` / `VidsrcCatalog` | Asks VidSrc whether it actually holds a file for an entry |
| `EmbedAvailabilityAudit` / `UnplayableEmbedNotifier` | The sweep behind `embed_availability_scan`, and the notifications it raises |
| `PosterAudit` / `BrokenPosterNotifier` | Same shape, for posters whose image has gone |
| `RuntimeBackfill` | Fills missing runtimes from TMDB: episodes a season per request, films by imdb id, standalone episodes through their show. Skips fanedits and episodes with no `series_imdb`; never overwrites |
| `MissingRuntimeAudit` / `MissingRuntimeNotifier` | Same shape as the poster pair, for every entry cable would leave out for want of a runtime; `Row#channel` names the dial channel that reaches one, and is nil for the rest |
| `NewEpisodeImporter` / `NewEpisodeNotifier` | The sweep behind `new_episode_scan`: extends each series with episodes TMDB shows have really aired, and tells the channel's owner (§5.12) |
| `SourceExpiryNotifier` | Warns admins before a provider domain lapses (§4) |
| `AdminStateNotifier` | The base class the four reconciling notifiers above share. Each of them is about a *state*, not an event, so a run works out the warnings that should exist now, creates the missing ones and deletes the ones no longer earned — fixing the thing clears its warning without anyone dismissing it. A subclass supplies its `kind`, a `dedupe_key` for a row, and the subject/data a row becomes; the transaction, the per-admin loop and the sweep of rows belonging to ex-admins live in the base. `NewEpisodeNotifier` is deliberately **not** one of these: an episode appearing is an event, and there is nothing to reconcile |
| `AdminStatistics` | The dashboard's numbers, one seven-day window throughout |
| `DeploymentStatus` | Which build is actually running, recorded by the worker at boot |
| `YoutubeVideoFacts` | Reads a commercial reel's runtime off YouTube |
| `GoogleImageSearch` / `RemoteImage` | Extra poster sources; fetching and validating a remote image |

---

## 8. Background jobs

Two run from `Entry` `after_commit` callbacks: `CheckEntrySourceJob` (validates a new
entry's URL → `entries.stream`) and `AttachPosterFromPicJob` (mirrors `pic` into
Cloudinary). `LetterboxdSyncJob` refreshes one member's Letterboxd channel on demand.

**The rest are periodic**, registered from `config/schedule.yml` by `sidekiq-cron`:

| Job | When (UTC) | What |
|---|---|---|
| `CableScheduleJob` | daily | Deal tomorrow for every channel; fill today if empty (§5.9) |
| `CloseAbandonedWatchPartiesJob` | every 15 min | Close rooms nobody has open (§5.10) |
| `SourceExpiryScanJob` | daily | Warn admins about lapsing provider domains |
| `LetterboxdWeeklyRefreshJob` | Mondays | Re-read every linked member's diary |
| `BrokenPosterScanJob` | Mondays | Poster URLs that no longer answer with an image |
| `EmbedAvailabilityScanJob` | Tuesdays | Entries VidSrc has no file for |
| `MissingRuntimeScanJob` | Wednesdays | Fill missing runtimes from TMDB (`RuntimeBackfill`), then warn about the rest; the ones already on the dial are named with their channel |
| `NewEpisodeScanJob` | Thursdays | Episodes aired since each series was filled in; tells the channel's owner (§5.12) |

The schedule is loaded **on the Sidekiq server only** (`config/initializers/sidekiq.rb`) —
a web process registering them too would have several dynos racing to own the same
schedule. Registration touches Redis and is wrapped in a rescue: a failure there would
otherwise take the whole worker down at boot, and processing queued jobs matters more than
a weekly refresh the next restart will register anyway. The same hook calls
`DeploymentStatus.record_worker!`, so the dashboard can show which build is actually
running rather than which was last deployed.

**TMDB responses are cached** for 12 hours in a bounded per-process `:memory_store` — not
Redis, which is Sidekiq's and runs `noeviction` (cache growth there would fail enqueues).

**Production runs Sidekiq** (`config.active_job.queue_adapter = :sidekiq`) against the
Railway Redis service, in a **separate `worker` service**. Its start command —
`bundle exec sidekiq -C config/sidekiq.yml`, the same as the Procfile's `worker:` line —
is set in that service's Railway settings (Deploy → Custom Start Command), *not* in a
config file: Railway is retiring config-as-code (see §11). Keeping the worker separate
matters: the web start command runs `assets:precompile && db:migrate`, and two services
racing migrations is a real hazard.

- `config/sidekiq.yml` — concurrency 3, queues `default` and `mailers`. Concurrency must
  stay ≤ the Active Record pool (`RAILS_MAX_THREADS`, default 5).
- `config/initializers/sidekiq.rb` — points at `REDIS_URL` when set; otherwise Sidekiq's
  own localhost default.
- `ApplicationJob` sets `discard_on ActiveJob::DeserializationError` — jobs now outlive the
  process that enqueued them, so a record deleted between enqueue and perform is common.
- **Dashboard: `/sidekiq`**, mounted for admins only. Enqueued / retrying / dead jobs.

**Development still uses `:async`** (in-process, no Redis needed) and test uses `:test`, so
neither needs a local Redis.

---

## 9. External dependencies & keys

| Service | Used from | Key |
|---|---|---|
| TMDB | server (`OmdbApi`, `TmdbService`, 3 controllers) **and** browser (4 Stimulus controllers) | `TMDB_API_KEY` — server code goes through `TmdbService.api_key` (`ENV.fetch`, fails loudly); the browser reads `<meta name="tmdb-key">`, emitted by all three layouts |
| OMDB | server only | `OMDB_API_KEY_1..3` |
| Cloudinary | Active Storage | `CLOUDINARY_URL` |
| Letterboxd | Public RSS diary (no auth) | — |
| YouTube Data API v3 | server only (`YoutubePlaylist`) | `YOUTUBE_API_KEY`, falling back to `GOOGLE_SEARCH_API_KEY` — both are keys onto the same Google Cloud project. Free 10,000 units a day; a 109-video playlist is seven calls |
| IMDb | HTML scraping | none |

`docs/guides/ENVIRONMENT_VARIABLES.md` lists the full set.

---

## 10. Routes worth knowing

`config/routes.rb` — non-obvious ones:
- `lists`: member `watch_current` (GET), `top_entries` (POST), `add_season` (POST),
  `move_to_list`, `subscribe`, `unsubscribe`, `mark_all_complete/incomplete`,
  `toggle_default`, `toggle_favorite`; collection `search` (JSON).
- Two non-RESTful posts outside the resource: `/lists/add_to_favorites`, `/lists/add_to_list`.
- `entries` nested under a list: `new` / `create`, plus collection `csv_template` (GET — it
  only generates a file), `import_csv` (POST — it writes a spreadsheet's worth of rows,
  and `check_list_edit_permissions` asks whose channel it is first) and `import_youtube`
  (POST, behind the same check — it writes a playlist's worth). `new` also takes
  `?duplicate=<entry id>`, which is what Duplicate on an entry card opens: the form filled
  in from that entry, with nothing written until it is submitted.
- `entries` member routes are split by side effect: **writes are PATCH/POST**
  (`complete`, `review`, `complete_without_review`, `reportlink`, `repair_image`,
  `migrate_poster`, `shuffle_current`, `increment_current`,
  `decrement_current`, `update_position`, `set_source`, `update_poster`) and only reads
  stay GET (`watch`, `watch_only`, `fetch_posters`). CSRF tokens do not protect GET, so
  nothing that writes may be reachable that way. There is **no `index`** action.
  `watch_only` is the one player route that writes nothing at all (§5.3a); `watch` itself
  is one of the three deliberate GET-writes.
  - `lists#watch_current` and `entries#watch` are the deliberate exceptions: they render
    or redirect to the player and write the user's position as a side effect of "I am
    watching this now". They are navigation targets, not actions. The cable pages are the
    third (see §10): they write no viewer state, but they do deal a day that is missing.
  - The watch page sets `data-turbo="false"`, so its controls are `button_to` forms —
    `data-turbo-method` links would silently fall back to GET there.
- `sources` (admin only) — plus member `renew` / `deactivate` (both PATCH: they change how
  the app plays things) and `test` (GET: it only plays something), and collection `reorder`.
- `/cable`, `/cable/:id` (a list on the dial, or a decade's key), `/cable/guide`, `/cable/0` —
  all GET. They write **nothing about the viewer**, which is the property §5.9 cares about,
  but they are not read-only: both `cable#show` and `cable#guide` lay out a missing day
  through `ensure_day!`/`ensure_days!`, so a GET can insert `cable_slots`. That is the third
  deliberate exception to the verb rule, alongside `entries#watch` and `lists#watch_current`.
  It is safe to repeat and safe to lose — a day already laid out is left alone — which is
  what makes it acceptable on a GET.
  **`cable/guide` and `cable/0` must stay declared above `cable/:id`** (§5.9).
- `/trailers` (GET) — the trailer reel on its own page. Writes only `session[:trailers_seen]`.
- `watch_parties`, keyed by `param: :token` rather than id (§5.10).
- `resource :vote` nested under a list, with `cast` / `close` / `remove_option` (§5.11).
- `notifications` with member `dismiss` and collection `dismiss_all` (§5.12).
- `namespace :admin` — `dashboard` (`show` / `update`, plus `reset_source`,
  `run_poster_scan`, `run_embed_scan`, all POST because they enqueue or rewrite) and
  `commercial_reels` (§5.14).
- `resource :profile` — the account page; email and password stay with Devise.
- `/watch_now`, `/health`, `/letterboxd/*` (`check` is reachable signed out, because the
  sign-up form asks before the account exists).

---

## 11. Deployment & operations

- **Railway.** Start commands live in each service's settings (Deploy → Custom Start
  Command), *not* in a config file — there is no `railway.json`, deliberately: a repo-root
  config applies to **every** service built from this repo and outranks the dashboard, so
  the worker could not override the web command. Config-as-code is also deprecated
  (Railway stops reading those files on 2026-12-01).
  - `how-to-watch`: `rails assets:precompile && rails db:migrate && rails server -b 0.0.0.0 -p $PORT`
  - `worker`: `bundle exec sidekiq -C config/sidekiq.yml`
  - Both are mirrored in the `Procfile` (`web:` / `worker:`), which is what Railway's
    builder falls back to when a service has no custom start command.
- Migrations run on every web boot, so a bad migration takes the app down.
- **Builders differ per service.** The worker builds with Railpack (Nixpacks is deprecated);
  Railpack's final image is minimal, so gems with native extensions need their shared
  libraries declared: `RAILPACK_DEPLOY_APT_PACKAGES=libffi8 libpq5` is set on both services.
  It is ignored by Nixpacks, so it is safe to carry on a service that has not migrated yet.
- Health check: `GET /health` (the only unauthenticated action).
- **Security headers**: `Permissions-Policy` is enforced (`config/initializers/permissions_policy.rb`)
  and denies features the app never uses, which also limits the embedded player.
  `Content-Security-Policy` is **report-only** — see that initializer for what has to change
  before it can be enforced.
- Production forces SSL, allows `*.railway.app` and `RAILS_HOST`.
- The `worker` service shares the app's env via Railway references; it needs
  `DATABASE_URL`, `REDIS_URL`, `RAILS_MASTER_KEY`, `SECRET_KEY_BASE`, `CLOUDINARY_URL`
  and the TMDB/OMDB keys.
- Useful rake tasks: `sources:seed`, `sources:backfill`, `entry:check_sources`,
  `entry:check_mega APPLY=1` (MEGA entries, against MEGA's own API),
  `images:check` / `images:repair`, `positions:fix_invalid`, `db:backup:full`,
  `db:backup:restore[file]`, `export:entries`.
- Task guides live in `docs/guides/` (Railway deploy, backups, image repair, poster
  migration, Letterboxd). Written Sept 2025 — treat as historical.

---

## 11a. Tests

RSpec is the live suite (`bundle exec rspec` — **~1,370 examples, green, under a minute**). `spec/rails_helper.rb` calls
`Rails.application.reload_routes_unless_loaded` because Rails 8 draws routes lazily and
Devise registers its mappings during that draw; without it every `sign_in` fails. The test
env uses the `:test` job adapter, since entry callbacks enqueue network-touching jobs.
The `test/` Minitest tree is leftover generator stubs and does not run clean.
`bundle exec rubocop` works but has never been brought to clean (~5,000 mostly-style
offenses, ~4,550 autocorrectable). Do **not** run a blanket `-a`/`-A`: it would rewrite
nearly every file in the repo and bury whatever real change it was run alongside.

Specs worth knowing about, because they encode decisions rather than behaviour:
`javascript_modules_spec.rb` (§6 — the only coverage the JS has),
`list_show_payload_spec.rb` and the two `*_queries_spec.rb` files (§6, per-card cost and
query counts), and `entry_write_verbs_spec.rb` / `list_write_verbs_spec.rb` (§10, that
nothing which writes is reachable by GET).

---

## 12. Keeping this document honest

Everything above was read out of the code at the verification date in the header. The
sections most likely to drift, in order: §7 (services are added often), §8 (so are periodic
jobs), §4 (providers die and `Source` grows options), and §5.9 (cable is the newest part of
the app and still moving).

If you are reading this well after that date, `git log --stat docs/ARCHITECTURE.md` will
tell you how far behind it is likely to be. Trust the code; update the section you touched.

---

## 13. Debugging map — symptom → where to look

| Symptom | Start here |
|---|---|
| The guide gets slower as the dial grows | `CableSchedule.ensure_days!` — it answers "which of these days are laid out" in one query. If a channel has nothing playable on it, it produces no slots and is re-planned on every visit, which is the one case where cost grows with the dial. `spec/requests/cable_guide_queries_spec.rb` pins the flat case. |
| A page issues the same `sources` query over and over | `Source.active_imdb` memoises them on `Current` for the request; `Entry#resolved_source` and `#eligible_sources` both go through it. Rails' query cache covers some of this, but a page that writes while it renders drops that cache. A write to any `Source` clears the memo. |
| An admin warning will not clear, or comes back | the notifier reconciles rather than appends (`AdminStateNotifier`), so the row survives only while `key_for` still matches something in the current set. A key that encodes changing state (a URL digest, an expiry date) is what makes dismissal safe. |
| List page 500s while grouping | `ListsController#filter_entries` + `sort_sections`; nullable `genre`/`year`/`rating` are the usual cause. |
| Player is blank / "No video source available" | `Entry#embed_url` → `#resolved_source` → the `Source` row's `templates`. Check the source is `active` and its template has a key for that `media`. There is no legacy fallback left, so a blank URL is always the template or what it substitutes — `/entries/:id/watch_only` (§5.3a) renders either way and names which of the two it was. |
| A film restarts itself, stutters or stops for no reason | play it at `/entries/:id/watch_only` (§5.3a) and compare. The watch page warms a second player five seconds in and a third as the credits run, so a decode failure there may be ours; the isolated page has none of that, writes nothing, and prints one line per load on both sides of the connection. |
| Wrong episode plays | `UserEntryPosition` for that user+entry; `Entry#current_subentry_for_user`; for anime, `Subentry#calculate_absolute_episode_number`. |
| Episode numbers off for anime | anime may use absolute numbering (`%{absolute_episode}`); note `calculate_absolute_episode_number` counts within one entry, and each season is its own entry here. |
| "Watched" state wrong or resets | `UserEntry` (not `entries.completed`). Note `Entry#user_entry_for` **creates** a row on read. |
| List starts on the wrong item | `UserListPosition.current_position` vs `entries.position`; `rails positions:fix_invalid`. `lists.current` is legacy and ignored per-user. |
| Entry order looks scrambled | three competing schemes: `Entry.next_position`, `list.entries.count + 1`, `shift_positions`, `List#normalize_entry_positions!`. |
| Poster missing / broken image | `entries.pic` vs the Active Storage `poster`; `AttachPosterFromPicJob` (in-process, easily lost); `ImageRepairService`; `ImageHelper#entry_poster_image_tag` builds Cloudinary URLs by hand. |
| Search returns nothing | client-side TMDB fetch in the Stimulus controller (check the browser console + the `<template>` id in the layout), not the server. For `list_search`/`mobile_search` the fetch itself is in `services/tmdb_search_behavior.js`. |
| A button or input does nothing at all | a `data-action` naming a method that no longer exists — Stimulus reports it only in the console. `bundle exec rspec spec/javascript_modules_spec.rb` catches every instance. |
| Filtering a list returns everything | `ListsController#load_entries` builds `@position_items`; the default `Position` view renders that rather than the grouped `@entries`, so a filter has to be applied there too. |
| Adding a series creates no episodes | `OmdbApi.get_series_episodes` → needs `entry.season` and (ideally) `entry.tmdb`. Failures here surface as the misleading flash "This already exists in your list". |
| A series is not picking up new episodes | `NewEpisodeImporter`: skipped if it holds no episodes, or its TMDB id cannot be confirmed as the show; an aired episode with a stand-in title or no runtime is held back up to 14 days, and nothing after it is added meanwhile. The job logs counts. |
| Sort/group setting doesn't stick | `ListsController#load_entries` — writes are guarded to explicit params, and `settings` is read back as the default. |
| Slow list page, but the query count is flat | it is the views, not the DB. See §6: anything rendered *per card* is multiplied by the list size, and the big lists run past a thousand entries. |
| Slow list page | check the preloads first: `ListsController#with_card_data` + `resolve_card_entries` (index) and the `includes(:user_entries).with_attached_poster` in `load_entries` (show). Losing either turns `completed_by?` / `current_entry` back into a query per row. `find_now_playing_for_sidebar` also runs on every page. **A preload here is easy to defeat without touching it:** anything that reloads the association (`all_items_by_position` did) throws it away silently. `spec/requests/list_show_queries_spec.rb` and `list_index_queries_spec.rb` assert the query counts stay flat. |
| A write succeeds that shouldn't | `EntriesController#check_edit_permissions` — it guards only the actions named in its `before_action`. Actions writing *shared* entry state belong there; the per-user ones (`complete`, `review`, current-position) deliberately do not. |
| Worker crashes at boot with `libffi.so.8: cannot open shared object file` | Railpack's runtime image lacks libffi, which `sassc-rails → sassc → ffi` needs at Rails boot. Fixed with `RAILPACK_DEPLOY_APT_PACKAGES=libffi8 libpq5` on the service. `/mise/installs/...` paths in a trace mean Railpack; `/nix/store/...` means Nixpacks. |
| Job "didn't run" | check `/sidekiq` (admin) for retries/dead jobs, then `railway logs --service worker`. In development jobs run on `:async` in-process, so a dev-only failure is a different animal. |
| Mobile layout differs from desktop | user-agent sniffing in both controllers → `*_mobile` views + `layouts/mobile`. |
| A cable channel is off air / a gap in the guide | nobody laid that day out. `CableSchedule.ensure_day!` runs from `cable#show`, `cable#guide` and `CableScheduleJob`; check the worker ran and that the channel is `default`. |
| Cable shows a different programme to two people | something read a per-user table. Nothing under §5.9 may touch `UserListPosition`, `UserEntryPosition` or `player_progress`. |
| A programme runs far too long or too short | The catalogue runtime is wrong, since a missing one is no longer scheduled. For a series, check the *episode's* `length`. Slots dealt before 2026-09-19 may still carry a show's full length; re-deal from `/admin/cable`. |
| A film or episode never appears on a channel | It has no runtime (`CableSchedule.timed?`). `MissingRuntimeScanJob` fills what TMDB knows and raises a `missing_runtime` notification for the rest. |
| Commercial breaks or `/trailers` sit on a play button | The reel URL carries `autoplay=0` ahead of `autoplay=1` and YouTube obeys the first. Reels must ask `build_url(..., autoplay: true)` rather than append their own flag. |
| `/cable/guide` serves channel one | the `cable/guide` route slipped below `cable/:id` (§5.9). |
| `/cable/0` serves channel one | the `cable/0` route slipped below `cable/:id` (§5.9). |
| A decade channel is off air, or plays films from the wrong years | `CableEra#entries`: only public entries with a `year` in range count. Check `entries.year` and the list's `private` flag, and that whatever deals the dial reads `CableSchedule.dial` rather than `channels` (§5.9). |
| A watch link from a decade opens with the wrong channel around it | something passed the decade's key as `?channel=`, which the watch page reads as a list id -- use `CableHelper#cable_watch_path` (§5.9). |
| Channel 0 or `/trailers` sits on a finished trailer, or reloads the page between trailers | the embed is not reporting back (`enablejsapi=1` in `TrailerReel::PLAYER_OPTIONS`), or a screen element lost its `trailer-reel:next` action -- check both `cable/show` and `cable/trailers` (§5.9). |
| Channel 0 says there are no trailers | no active `youtube` Source, or no entry with a YouTube `trailer` in a channel the viewer can see. `lib/tasks/tmdb_trailer_update.rake` fills trailers in from TMDB. |
| Watch party connects but nothing ever arrives | the `redis` gem resolved to 6.x — Action Cable's adapter declares `< 6` and every broadcast raises `Gem::LoadError` while the socket still looks healthy (§5.10). |
| A watch party will not keep guests in step | `Source#syncable?` is false for that provider; the room can only hold everyone on the same entry. |
| A room vanishes while people are in it | `CloseAbandonedWatchPartiesJob` + `WatchParty::ABANDONED_AFTER`; check `last_seen_at` on the memberships. |
| Up-next card never appears | The lead is longer than what the entry has left after the completion mark. `AppSetting#up_next_mark_for` floors it, so this should not happen — if it does, check the runtime on the entry (§5.8). |
| Watched eye stays hollow after a film ends | `POST /entries/:id/progress` answers the crossing with a turbo stream; check `player_progress_controller` is actually connected — a bad import there fails silently in the browser and the whole controller never registers (§5.8). |
| Progress is not saved when the tab closes | `POST /entries/:id/progress` — `sendBeacon` can only POST; a PATCH route here silently drops the write. |
| A dismissed warning keeps coming back (or never does) | `Notification#dedupe_key` — it carries the date warned about, by design (§5.12). |
| A signed-out visitor sees too much / too little | `AppSetting#access_mode` and the table in `access_control.rb`. Only GETs pass; unlisted actions fall through to Devise (§5.13). |
| Admin-only UI missing | `users.admin`; sources CRUD and default-list toggles are admin-gated. Check the impersonation banner first — an admin viewing as someone else has no admin powers by design (§5.6). |
