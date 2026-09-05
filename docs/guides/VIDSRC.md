# VidSrc — the provider reference

**Purpose:** everything this project knows about VidSrc, the embed provider behind most of
the app's playback. Their official docs cover about half of it; the rest is measured
behaviour, admin statements buried in a forum shoutbox, and things that will break you if
you follow their tutorial literally.

**Read this before changing a `Source` row with `sync_adapter: 'vidsrc'`, before setting up
a custom domain, and before touching `app/javascript/services/vidsrc_player.js`.**

**Last verified:** 2026-09-04. Sources: <https://vidsrcme.ru/vidsrc/docs/> and the
community forum at <https://vidsrc.community/> (login required for the forum). Every
domain status in §1 was measured with a live request on that date.

---

## ⚠️ 1. Domain status — read this first

VidSrc rotates domains constantly, and their provider drops them with little warning. On
**2026-08-30** the `vidsrc` admin account posted in the forum shoutbox:

> Guys our domain provider not responding if you use any of this domains vidsrcme.ru
> vidsrcme.su vidsrc-me.ru vidsrc-me.su vidsrc-embed.ru vidsrc-embed.su vsrc.su
> Change them to **vidsrc2.ru vidsrc.ir** Or it's better if you use custom domains.

Measured 2026-09-04 with `GET /embed/movie?imdb=tt0172495`:

| Domain | Result | Notes |
|---|---|---|
| `framerelay.dev` | `200` | **ours** (§5) — the only one that autoplays |
| `vidsrc2.ru` | `200` | provider's recommended default domain |
| `vidsrc.ir` | `200` | provider's recommended default domain |
| `vidsrcme.ru` | `200` | on the admin's at-risk list |
| `vidsrcme.su` | `200` | on the admin's at-risk list |
| `vidsrc-embed.ru` | `301` → `vsembed.ru` → `200` | kept as a fallback, at-risk list |
| `v2.vidsrc.me` | `301` → `vidsrcme.ru` → `200` | kept as a fallback, resolves to an at-risk domain |
| `vsrc.su` | `301` → `vsembed.ru` → `200` | at-risk list |
| `vidsrc.net` | **no DNS** | dead — and it is the domain in their own 2025 announcement |

Until 2026-09-04 the app's only two vidsrc sources were `vidsrc-embed.ru` and
`v2.vidsrc.me`, both on that at-risk list — one provider timeout from every embed going
dark at once. `vidsrc.net` is what that failure looks like once it lands. They are still
configured, but now as fallbacks behind our own domain.

The provider's own history of this: an October 2025 announcement titled *"Urgent
Announcement: Update Your Embed URLs"* told everyone to move **to** `vidsrc-embed.ru`,
`vidsrc-embed.su`, `vidsrcme.su` and `vsrc.su` — every one of which is now on the 2026
at-risk list. Treat any hardcoded VidSrc domain as a wasting asset.

### 1a. The migration trap

Changing a `Source` template is never the whole job. Two other places key off the same
provider and both fail silently if they are left behind:

| Place | What it does | Failure if not updated |
|---|---|---|
| `VidsrcPlayer.ORIGINS` in [`vidsrc_player.js`](../../app/javascript/services/vidsrc_player.js) | allowlists origins it accepts `postMessage` from | the player loads and plays fine, but every event is rejected, `started` never flips true, so play/pause/seek and **all position tracking silently stop** |
| `Source::SYNC_ADAPTERS` in [`source.rb`](../../app/models/source.rb) | maps slug → player adapter | `sync_adapter` is `nil`, so the source is treated as having no control surface and watch parties fall back to "tell people how far apart they are" |
| `Source::PRECONNECT_ORIGINS` in [`source.rb`](../../app/models/source.rb) | the inner origins the player reaches for, warmed while the wrapper loads (§4a) | a stale host costs one unused socket and the second hop pays its own handshake again — slower, never broken |

The first two are keyed by hand — a slug or host that is playable but missing from them
looks healthy and behaves broken. **Change all three together.** The third is keyed by
adapter rather than by domain, so a new vidsrc front door needs nothing from it; it only
moves if the *inner* player host does. `framerelay`, `vidsrc2` and
`vidsrc-ir` were added to both on 2026-09-04.

### 1b. Expiry dates

Every provider whose address can lapse carries a `valid_until`, and admins get a warning
30 days out and again once it passes — the notifications page, and orange/red on
`/sources`. Null means the address cannot lapse (Drive, YouTube, the Archive), and those
never warn, which is what keeps the warnings that do appear worth reading.

| Provider | Window | Why |
|---|---|---|
| `framerelay` | 1 year | the real registration date; renew it at Cloudflare *and* here |
| `vidsrc2`, `vidsrc-ir` | 6 months | the provider's current recommendation, and their recommendations do not last a year |
| `vidsrc-embed.ru`, `vidsrcme` | 2 months | already on the at-risk list, working by inertia |

**Renewing here does not renew anything out there.** The date is a reminder to go and
check; `Renew a year` on `/sources` only moves the reminder. For framerelay that means
confirming the registration actually auto-renewed at Cloudflare — in its own account, so
it is not on the same billing as the app's.

`Test` on `/sources` plays a known film through one provider in a new tab, which answers
"is this domain still alive" without hunting for an entry that uses it. It sends
`autoplay=1`, so on framerelay it also demonstrates §4 still holds.

---

## 2. Endpoints

Two interchangeable forms. This app uses the query-string form throughout.

```
# Path form
/embed/movie/{imdb|tmdb}
/embed/tv/{imdb|tmdb}/{season}/{episode}
/embed/tv/{imdb|tmdb}/{season}-{episode}     # alternative separator

# Query-string form — what our Source templates use
/embed/movie?imdb=tt1300854
/embed/tv?imdb=tt0944947&season=1&episode=1
/embed/tv?tmdb=1399&season=1&episode=1
```

`/embed/tv/{id}` with no season or episode opens the series with a built-in picker and
resumes the last-watched episode from their own state. We do not want that — the app owns
episode selection — so always pass season and episode.

No API key, no sign-up. All domains serve identical content.

---

## 3. Query parameters

| Parameter | Values | Notes |
|---|---|---|
| `autoplay` | `0` / `1` | **See §4 — behaves differently on a custom domain.** |
| `autonext` | `0` / `1` | TV only. Auto-plays the next episode with an "Up next" countdown. Off by default. See the caveat in §7. |
| `startAt` | float (seconds) | Resume position, e.g. `startAt=300`. |
| `ds_lang` | ISO 639-1 or 3-letter | Default subtitle language. Accepts a priority list of up to 3: `en,fr,de` — first language that has a subtitle wins. Already in our templates. |
| `sub_url` | https URL | External `.vtt`/`.srt` track. Fetched **by the viewer's browser**, not their servers, so the host must send `Access-Control-Allow-Origin`. |
| `sub_label` | string | Display name for the `sub_url` track. Defaults to "Custom subtitle". |
| `sub_lang` | string | Language code for the `sub_url` track. |

`startAt` is how a part-watched entry resumes. The position is baked into the embed URL
server-side before the frame is written, because a `seek` sent downward is dropped until
the player has spoken (§6) — and by then the viewer has watched the opening again. See
`Source::RESUME_PARAMS`, keyed by adapter rather than by domain: the parameter belongs to
the player, and a provider with no adapter has no player to hand a position to.

**Parameter order matters less than parameter separators.** A forum user broke this with
`…&ds_lang=en?autonext=1` (a second `?`). The admin's own corrected form:

```
/embed/tv?imdb=tt11252254&ds_lang=en&autonext=1&autoplay=1
```

---

## 4. The autoplay click gate

This is the single most important behavioural fact about VidSrc, and the thing most likely
to send someone down a week-long dead end.

> **Direct autoplay** — The player opens immediately and starts playing — no play button.
> This no-click autoplay (`autoplay=1`) works on **custom domains only**; the
> official/default domains always show a play button first.
> — their API docs, §Custom Domain

So on any default domain, `autoplay=1` does **not** skip the play button. It only controls
whether playback begins automatically *after* the viewer clicks it.

On a custom domain it opens straight into the player. Browsers may still block *unmuted*
autoplay, in which case the player falls back to muted with an unmute prompt — that is a
browser policy, not a VidSrc one, and applies to any autoplaying video anywhere.

### 4a. Why there is no way around it

An admin-only `/lab` experiment was built to defeat this gate and then deleted on
2026-09-04 when the custom domain turned out to be the supported answer. Its findings are
kept here so nobody spends the week re-deriving them.

**The structure.** A default-domain embed is three nested cross-origin frames:

```
our page
└─ vsembed.ru/embed/movie?imdb=…              wrapper: relays messages, title bar
   └─ cloudorchestranova.com/embed/movie/…    shell:   poster + a play button
      └─ cloudorchestranova.com/embed/player/… player:  the actual <video>
```

The **shell** only builds the player on a click. Its script has exactly two call sites for
the function that does it:

```js
if (bigPlay) bigPlay.addEventListener('click', start);
if (CFG.autoStart) { bigPlay.style.display = 'none'; start(); }
```

`CFG.autoStart` is baked server-side as `false` — and the comment beside it says custom
domains skip the play button, which is what §4 documents. The innermost player *does*
default to `autoplay: true`; `autoplay=1` reaches it correctly. It simply never gets built.

So the only route is a real click on an element in a document at another origin, which is
unreachable: no API returns a cross-origin element handle, `elementFromPoint` returns the
`<iframe>` and never its contents, and a scripted event carries `isTrusted: false`.
**Even with no browser autoplay policy at all this would still fail** — the obstacle is DOM
isolation, not media policy.

**Ruled out against the live service.** Do not re-test these:

| Attempt | Result |
|---|---|
| `autostart`, `auto_start`, `start`, `ap`, `play`, `muted` on the wrapper | only `autoplay` is forwarded; none flip `autoStart` |
| `autostart=1`, `custom=1` on the shell URL | `autoStart: false` |
| A `postMessage` that triggers `start()` | none exists — and the relay only forwards downward *after* `start()` has built the frame, so it is circular |
| Resolving the innermost player URL server-side and framing it | works up to the last step, then **the referer wall** below |
| `referrerpolicy` on the iframe (`origin`, `no-referrer`, unset) | cannot help — a policy only shortens a referer, never forges a different origin |

**The referer wall.** The player document accepts *only* a `Referer` whose origin is
`https://cloudorchestranova.com`; anything else returns HTTP 200 with a 463-byte page
reading `Session expired...`, and no referer at all returns 9 bytes. The path is not
checked (a bare origin passes) but the origin check is real (`cloudorchestranova.com.evil.test`
fails). Since a browser can only ever send *our* origin for a frame on our page, no iframe
attribute satisfies it.

A server-side relay does get past it — the check stops at the player document, while its
scripts and the stream API (`Access-Control-Allow-Origin: *`) are ungated — but that means
re-serving a third party's page from our origin with the app CSP disabled, to win exactly
what a custom domain gives for free. That is why it was deleted rather than merged.

---

## 5. Custom domain

Point a domain you control at VidSrc and it behaves as an official domain, plus:

- **no-click autoplay** (§4) — the reason to do this;
- 50% fewer ads;
- no VidSrc logo — the player looks native.

### Their setup, and the two places it will hurt you

Their tutorial (verified current in a screenshot attachment dated **2026-08-30**):

```
Type:  CNAME
Name:  @ (root domain)
Value: vidsrc-ip.com          # resolves to 2.56.10.47 as of 2026-09-04
Proxy: Proxied (orange cloud ON)
```
Then Cloudflare → SSL/TLS → Overview → Configure → **Flexible**.

> ⚠️ **Do not CNAME the root domain.** Their step 1 says `Name: @ (root domain)`. Our root
> domain serves the Rails app — following that instruction points the whole site at VidSrc
> and takes it down. Use a subdomain. Their own feature blurb shows the sane version:
> `player.yoursite.com`. Nothing about the feature needs the apex.

> ⚠️ **Cloudflare's SSL mode is zone-wide.** They require **Flexible** because their origin
> is HTTP-only, and Full/strict breaks it. But setting it at zone level applies to *every*
> hostname in the zone, including the app — dropping the Cloudflare→Rails leg to plain
> HTTP. Scope it instead with a **Configuration Rule** targeting only the player hostname,
> or put the player subdomain on a separate zone.

Flexible also means the Cloudflare→VidSrc leg is unencrypted regardless. That is inherent
to their design and cannot be configured away.

**The CNAME target rotates.** Their docs say to check Announcements for the current value
before setting up. As of 2026-09-04 the Announcements forum holds only four threads and
none supersede `vidsrc-ip.com`.

### Ours: framerelay.dev

Live since **2026-09-04**, on a **separate Cloudflare account** from the app. That
separation is deliberate and worth preserving: with the orange cloud on, the zone is
*proxying the stream*, so abuse complaints reach Cloudflare about this domain — and
Cloudflare can act at the account level, not just the zone. Keeping it out of the app's
account means the worst case is losing the player domain, not the app.

The name is deliberately dull and unbranded — it reads as networking infrastructure and
carries nothing of the app's identity, which is the point.

Seeded as the `framerelay` source at position 1, `kind: 'imdb'`, `autoplay_param: 'autoplay'`.
`autonext` is deliberately **not** in the templates: the app drives episode order itself,
and vidsrc's own advance loses track of which episode it is on (§7).

**Renewal is load-bearing.** If the domain lapses every embed dies at once, and the cause
will not be obvious from inside the app. Auto-renew is on.

### How we know it works

The custom-domain flag is observable from outside, which is worth knowing because it means
this can be checked without a browser. Walk the chain to the shell and read `CFG.autoStart`
— the same field whose hardcoded `false` §4a is about:

```
framerelay.dev  →  "autoStart": true      # shell hides the play button and calls start()
vidsrc2.ru      →  "autoStart": false     # default domain, gated
```

Verified 2026-09-04 for both a film and an episode, same title and same minute on both
front doors. If autoplay ever stops working, check this first: `autoStart: false` on
framerelay.dev means the custom-domain arrangement has lapsed at their end, not that
anything in this app changed.

---

## 6. Player events

The player posts state up to the parent window. **This is now officially documented**,
which is worth knowing because the header comment in `vidsrc_player.js` predates that and
says nothing here is documented — that is now only true of the *downward* command protocol.

```json
{
  "type": "PLAYER_EVENT",
  "data": {
    "player_info": {
      "imdb": "tt1300854",   "tmdb": null,
      "mediaType": "movie",  "season": null, "episode": null
    },
    "player_status": "playing",
    "player_progress": 125.4,
    "player_duration": 7200
  }
}
```

| Status | Fired when |
|---|---|
| `playing` | playback starts or resumes, **and every ~5s during playback** |
| `paused` | viewer pauses |
| `completed` | video reaches the end |
| `seeked` | viewer seeks |

**What our client does with them.** `VidsrcPlayer#receive` passes each report on twice
over: `event` is the player's own word, and `status` is that collapsed to
`"playing" | "paused"`. The two callers want different things — a watch party's clock only
cares whether the film is moving, while position tracking has to tell a seek from an ending.
Until 2026-09-04 only the collapsed form existed, so `completed` and `seeked` were
indistinguishable; anything driving our own auto-next wants `event`.

`player_info` carries `season` and `episode`, which is how we can keep our own position
record even when `autonext` advances episodes behind our back (§7).

**The downward protocol is undocumented and reverse-engineered**:
`{ player: true, action: "play" | "pause" | "mute" | "unmute" | "seek<N>" }`. The player
matches `seek([+-]?)([0-9]+)`, so a fractional target silently does nothing. Commands sent
before the first `PLAYER_EVENT` are dropped, which is why `VidsrcPlayer` sends nothing until
the player has spoken.

---

## 6a. How long an embed takes to start

Measured 2026-09-05 against `framerelay.dev`, `tt0089003`, loaded top-level so the chain
could be instrumented. Milliseconds from navigation start, warm DNS and warm HTTP cache:

| | ms | what happens |
|---|---|---|
| wrapper TTFB | 55–127 | our front door answers |
| `vs_src.php` returns | ~215 | the wrapper's own XHR, which yields the shell URL |
| shell document done | ~360 | first cross-origin hop, on `cloudorchestranova.com` |
| first `PLAYER_EVENT` | ~720 | the player exists and is talking (§6) |
| picture actually moving | **1300–1600** | stream resolved, first segments in, decoding |

So **about 1.5s warm**, and more cold: the chain touches six origins — `framerelay.dev`,
`cloudorchestranova.com`, `data.vidsrcme.ru`, `cdn.jsdelivr.net` (hls.js), `kudzukernel.site`
(the stream) and `vidapi.cloud` — and a cold name lookup measured ~145ms each. The hops are
strictly sequential: each URL is only discoverable once the document before it has loaded
and run, which is why §9's preconnect exists and why it can only help the hops whose origin
is known in advance.

`data.vidsrcme.ru/api.php` is the slowest single call at 136–211ms TTFB, and it is on the
critical path twice (once for metadata, once for `stream_urls`).

Worth knowing before optimising: roughly ten requests per embed, and several are neither
ours nor the player's — `histats.com`, plus a rotating ad/tracking host. Anything that
loads N embeds at once multiplies those too.

The player page keeps exactly one spare. The channel below is warmed in a second frame
five seconds after the page settles, so pressing down costs 8ms instead of the 1.5s above
— measured 2026-09-05. Two embeds, not six: the cost above is why the other four
directions still pay full price. The spare frame is stacked *behind* the live one rather
than hidden, because a frame the browser thinks nobody can see is one it feels free to stop
buffering.

---

## 7. Known issues and caveats

**Autonext loses track of position.** Reported 2025-05-07: as `autonext` advances, the
season/episode indicator does not update, and leaving the series loses your place. The
admin replied "will be fixed"; there is no confirmation it was, and a 2026-03-03 post asks
whether autonext works at all. This matters less for us than for most — we consume
`PLAYER_EVENT`, whose payload includes `season` and `episode`, so we can keep our own record
regardless of what their UI shows.

**Ad-free plays are disabled platform-wide.** Pinned notice from 2025-11-11, still current:
the feature is off pending a new dashboard. So a custom domain's 50% reduction is currently
the only ad lever that exists. The same notice warns that anyone selling ad-free access or
"special accounts" is a scammer — they do not sell it.

**Fullscreen is ours, not theirs — and it has to be taken away up front.** The player
offers fullscreen by button, by `f` and by double-click, and any of them puts *their*
frame full-screen, which hides everything this app draws around it. Dropping
`allowfullscreen` from the iframe kills all three at once, because what is withheld is the
capability rather than any one way of asking; measured 2026-09-05, playback is unaffected
and the dead button does nothing visible. It has to be withheld rather than corrected
afterwards: once the frame holds fullscreen, moving it to an ancestor is refused
("Permissions check failed") without a fresh gesture in *our* document, which a click
inside theirs never gives us. See `cinema_fullscreen_controller.js`.

Their button still *draws*, though, so ours is positioned on top of it to hide it. Those
offsets are read off `iframe_player/assets/player.css` (`.jw-controls` padding, `--bar-h`,
`.jw-btn` size) rather than guessed, and they are the one place in this app that depends on
their visual layout — if the bar is restyled, ours goes off-centre. Cosmetic only: the
button underneath is inert either way.

**The embed wipes itself when DevTools is open.** It loads `disable-devtool.js` on both
the wrapper and the player, and on detecting an inspector it navigates the document to
`about:blank` — so anyone debugging playback sees an empty frame and will reasonably think
it is our bug. It is not. Measuring or debugging the embed means neutralising that script
first: it installs itself on `window.DisableDevtool`, so defining that property as a
non-writable no-op before the page's own scripts run leaves playback working and the
inspector attached.

**Adblockers frequently block the player entirely.** Repeated complaints through 2026-08;
the admin's response was to ask which blocker rather than to fix it. Anyone testing playback
with a blocker on will see a dead frame that looks like our bug.

**Subtitles reportedly only load over a VPN** for some users (2026-08-14, 2026-08-15). No
resolution posted.

**`sub_url` was broken** as of 2026-08-09; the admin said it and the quality selector would
be fixed. Unverified since.

---

## 8. Content feeds

Not currently used by the app, but available without a key.

| Endpoint | Returns |
|---|---|
| `/movies/latest/page-{N}.json` | latest added movies |
| `/tvshows/latest/page-{N}.json` | latest added TV shows |
| `/episodes/latest/page-{N}.json` | latest added episodes |

Shape is `{ "result": [...], "pages": <total> }`, 50 per page, newest first, cached ~5
minutes. Movie rows carry `imdb_id`, `tmdb_id`, `title`, `embed_url`, `embed_url_tmdb`,
`quality`, `time_added`.

Full ID dumps live at `/ids/`, one per line, updated daily, CORS enabled:
`movie_imdb.txt`, `movie_tmdb.txt`, `tv_imdb.txt`, `tv_tmdb.txt`, `eps_imdb.txt`
(`tt0944947_1x1`), `eps_tmdb.txt` (`314541_1x3`). Note the filenames are `movie_*`, not
`mov_*` — a community member lost time to that.

These would answer "can VidSrc actually play this entry?" without a request per title, which
is worth remembering if entry validation ever comes up.

---

## 9. Where this app touches VidSrc

| File | Role |
|---|---|
| `Source` rows (`sync_adapter: 'vidsrc'`) | the embed URL templates — see §1 for their current, at-risk domains |
| [`app/javascript/services/vidsrc_player.js`](../../app/javascript/services/vidsrc_player.js) | the origin allowlist (§1a) and both message protocols (§6) |
| `Entry#embed_url` | renders a template into a URL |
| `db/seeds/sources.rb` | the create-only seed those rows come from (`rails sources:seed`) |
| `Source::SYNC_ADAPTERS` | maps a slug to the player adapter — a new vidsrc slug must be added here or it is treated as uncontrollable |
| `Source::RESUME_PARAMS` | maps an adapter to its resume parameter (`startAt`), so only a provider with a player carries one |
| `Source::PRECONNECT_ORIGINS` | the inner player origin, opened while the wrapper is still loading — see §1a for what a stale one costs |
| [`app/javascript/controllers/player_progress_controller.js`](../../app/javascript/controllers/player_progress_controller.js) | saves the position on pause, on seek, at the completion mark and as the page goes away; reads the `event` from §6. Leaves fullscreen at 98%, which works because the exit belongs to the top-level document even though the frame requested it, and needs no user gesture |
| [`app/javascript/controllers/auto_advance_controller.js`](../../app/javascript/controllers/auto_advance_controller.js) | the up-next countdown, raised by coming out of fullscreen past the completion mark — so a rewatch, already marked watched, is not offered the next entry over its opening titles |
| `EntriesController#progress` | records it on the viewer's `UserEntry`, ticking the film off at `UserEntry::COMPLETION_FRACTION` |

---

## 10. Recommended order of work

1. ~~Add `vidsrc2.ru` / `vidsrc.ir`~~ — **done 2026-09-04**, with the `ORIGINS` and
   `SYNC_ADAPTERS` entries alongside.
2. ~~Custom domain for autoplay~~ — **done 2026-09-04**, `framerelay.dev` (§5).
   Still outstanding: existing channels and entries keep whichever provider they are
   linked to, so nothing has moved onto it yet. Repointing them is a data migration.
3. ~~Delete the `/lab` direct-embed experiment~~ — **done 2026-09-04**. Its findings live
   in §4a; the code is gone, and the custom domain is the supported route to the same end.
