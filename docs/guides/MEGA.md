# MEGA

How the app plays a MEGA file itself, and the measurements the design rests on. Written
2026-09-20. Where this and the code disagree, `public/mega-sw.js` and `Source::NATIVE_PLAYERS`
win.

---

## 1. Why we do not use MEGA's player

MEGA's embed answers nothing. Probed 2026-09-15 and again 2026-09-18 with the YouTube,
player.js, Vimeo and JW protocols: it registers no `message` listener and posts nothing up.
The only thing it accepts is a run of option pairs in the link fragment — `#KEY!900s1a` starts
fifteen minutes in and autoplays — and it obeys those on every document load rather than
keeping a position of its own.

So for as long as the app framed that player, a MEGA entry could not have a recorded
position, a resume, a watched mark, an up-next card, the keyboard, or a place in a watch
party. All of those ride on a player's reports, and there were none. That is 424 entries,
about an eighth of the library.

It also meant that anything which interrupted playback lost the whole film: with no position
recorded there was nothing to come back to, so a reload started at the beginning. That is
what made the restarts of September 2026 so visible on MEGA and invisible everywhere else.

## 2. What makes playing it ourselves possible

Three things, each measured on 2026-09-20 rather than assumed:

**The API is callable from the browser.** `https://g.api.mega.co.nz/cs` answers
`Access-Control-Allow-Origin: *`. A `g` command returns a file's size and its encrypted
attributes; adding `g: 1` returns a download URL, and *that* is the call that spends transfer
quota — which is why `MegaAvailability`, which only asks whether a file exists, deliberately
leaves it out.

**The bytes come over HTTPS and honour ranges.** Ask with `ssl: 2` and the URL comes back
`https://gfs…userstorage.mega.co.nz/…`; without it MEGA hands out `http://`, which a page
served over HTTPS refuses as mixed content. The node answers `206 Partial Content` to a
`Range` request, with `Access-Control-Allow-Origin: *`.

**The link's key decrypts them.** The fragment is 32 bytes of URL-safe base64. The first
sixteen XORed with the second sixteen are the AES-128 key; the next eight are the counter
nonce. The counter block for any 16-byte block of the file is `nonce || block index`, as a
64-bit big-endian number. Decrypting the first 64 bytes of a real file yields `ftyp mp42`.

Every MEGA file in this library is an MP4, which is the fourth thing and the one we did not
have to measure.

## 3. How it is served

`public/mega-sw.js` is a service worker claiming `/mega/<handle>/<key>/video.mp4`. Each
request the video element makes becomes one ranged fetch to MEGA, decrypted on the way past
and answered as `206`.

AES-CTR is a keystream, so any block decrypts without the ones before it. That is what makes
the file seekable: a seek costs one ranged request rather than a re-download, and it is the
reason this can be a `<video>` with a scrubber at all.

Three details that are not obvious:

- **Decryption starts on a block boundary.** A request for byte 1000 fetches from 992 and
  drops the first eight bytes after decrypting.
- **An open-ended range is answered with a chunk.** Chrome opens a media file with
  `Range: bytes=0-`, and taking that literally would push six hundred megabytes through the
  decryptor to show the first frame. `OPEN_ENDED_CHUNK` is what it gets instead; it comes
  back for more.
- **Download URLs expire.** They are cached for `URL_TTL` and re-asked for once on a fetch
  that comes back refusing.

**Not MediaSource.** MSE takes only fragmented MP4 or WebM, and these are ordinary
progressive MP4s, so it would mean remuxing them in JavaScript — which is exactly what
MEGA's own player does (`Encoder`, `MediaSourceStream` and `Streamer` are its code, and they
are what appears in the console when one of its streams dies). The browser demuxes an MP4
better than we would.

## 4. How it reaches the page

| | |
|---|---|
| `Source::NATIVE_PLAYERS` | which providers the app serves itself. MEGA is the only one. |
| `Source#native_url_for` | builds `/mega/<handle>/<key>/video.mp4`. Not a template — templates substitute into somebody else's address, and this is one of ours. |
| `Source::SYNC_ADAPTERS['mega']` | the switch. `player_progress` and `player_keys` both bail at connect without an adapter, so this is what turns the rest of the app on for MEGA. |
| `services/mega_player.js` | drives the `<video>` through the same interface the embeds use, so nothing downstream needs a case for it. |
| `native_player_controller.js` | registers the worker and hands the element its address. |

**The sequencing in that last one is the whole of it.** The worker must be *in control* of
the page before the element asks for a byte, because `/mega/...` exists nowhere else — the
app does not serve it, the worker invents it. A request made too early goes to the network
and finds nothing. On a first visit `navigator.serviceWorker.ready` is not enough either:
the worker installs, activates, and only then claims the page, and a fetch made before the
claim goes straight past it. So the address is a data attribute, handed over after the claim,
rather than a `src` that would start loading during the parse.

## 5. What this changed elsewhere

- The resume arrives as a value on the element rather than a query parameter, and is applied
  on `loadedmetadata` — there is nothing to seek within until the length is known.
- A move between entries **replaces** the element rather than re-pointing it. An iframe is
  its `src`; a `<video>` is handed its address by a controller that Stimulus only runs for an
  element it has not seen.
- `cinema-navigation` never warms a native player in a frame, though it still fetches its
  page. Warming means starting a second stream and stopping it again, and here that second
  stream is ours to pay for twice — our worker decrypting it, and a second hardware decoder
  on the machine. See `STOP_DEADLINE` and VIDSRC.md §6a for why that matters.

## 6. Known limits

- **Transfer quota.** MEGA throttles unauthenticated transfer per IP. Playing through our
  own worker spends it exactly as the embed did — the bytes reach the same browser either
  way — so this neither helps nor hurts, but running out still stops a film partway.
- **One file, one format.** This assumes MP4. A MEGA entry that is not one will not play,
  and the browser's error is all the diagnosis there is; `/entries/:id/watch_only?player=embed`
  puts MEGA's own player back for comparison.
- **No service worker, no playback.** A browser without them, or a context that refuses to
  register one, gets a message rather than a black rectangle.
