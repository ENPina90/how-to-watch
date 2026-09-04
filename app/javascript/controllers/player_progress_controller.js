import { Controller } from "@hotwired/stimulus";
import { playerAdapterFor, isControllable } from "services/player_adapter";

// Keeps a record of where this viewer got to, so the next visit picks up there.
//
// The position comes from the player's own reports (docs/guides/VIDSRC.md §6), which only
// providers with an adapter send -- on Drive, YouTube and the rest this controller finds
// nothing to listen to and does nothing at all, which is the intended behaviour rather
// than a gap. The resume itself happens server-side: the position is baked into the embed
// URL before the frame is written, because the player accepts a start position as a query
// parameter and ignores a seek sent before it has spoken.
//
// What gets saved, and when:
//
//   pause / seek     the viewer stopped or moved deliberately -- the moments the position
//                    is worth anything, and the only ones the player marks out for us
//   leaving the page a redirect home, to a list, to another film. Sent with sendBeacon so
//                    it survives the navigation that triggered it
//   the end          the player's own `completed`
//
// Whether a saved position is far enough through to tick the film off is the server's
// call, on whatever save happens to arrive -- so a viewer who watches to the credits and
// closes the tab is credited by the same rule as one who sits through them.
//
// Playback itself is not saved. The player reports every ~5s while playing, and writing a
// row twelve times a minute per viewer buys nothing: anyone who leaves mid-film leaves the
// page, and leaving the page saves.
const SAVE_INTERVAL = 2000;

export default class extends Controller {
  static values = {
    url: String,
    adapter: String,
    frame: String,
    token: String,
  };

  connect() {
    if (!isControllable(this.adapterValue)) return;

    const iframe = document.getElementById(this.frameValue);
    if (!iframe) return;

    this.lastSaved = 0;
    this.player = playerAdapterFor(this.adapterValue, iframe, {
      onState: (state) => this.playerReported(state),
    });

    // pagehide covers a real navigation, a back button and a closed tab. visibilitychange
    // covers the one it does not: a phone locked or an app switched away from, where the
    // page may be discarded later without ever running another handler.
    this.leaving = () => this.save({ beacon: true });
    this.hiding = () => { if (document.visibilityState === "hidden") this.save({ beacon: true }); };
    window.addEventListener("pagehide", this.leaving);
    document.addEventListener("visibilitychange", this.hiding);
  }

  disconnect() {
    window.removeEventListener("pagehide", this.leaving);
    document.removeEventListener("visibilitychange", this.hiding);
    this.player?.destroy();
  }

  playerReported(state) {
    this.state = state;

    // The player's own word for what happened, not the collapsed status: a seek and an
    // ending both leave the film stopped, and only one of them means it was watched.
    if (state.event === "completed") return this.save({ finished: true, force: true });
    if (state.event === "paused" || state.event === "seeked") this.save();
  }

  // `force` skips the interval, for the saves that must not be dropped -- the ending, and
  // the page going away. Everything else is coalesced: dragging a scrubber fires a seek
  // per frame of the drag, and only where it was let go matters.
  save({ finished = false, beacon = false, force = false } = {}) {
    if (!this.state) return;

    const now = Date.now();
    if (!force && !beacon && now - this.lastSaved < SAVE_INTERVAL) return;
    this.lastSaved = now;

    const body = new FormData();
    body.append("progress", this.state.progress);
    body.append("duration", this.state.duration);
    body.append("finished", String(finished));
    // In the body rather than a header: sendBeacon cannot set one, and Rails reads the
    // token from either.
    body.append("authenticity_token", this.tokenValue);

    // A page that is unloading is not around to await a promise, and a fetch started here
    // is cancelled with the document. sendBeacon hands the request to the browser, which
    // sends it after we are gone.
    if (beacon && navigator.sendBeacon) {
      navigator.sendBeacon(this.urlValue, body);
      return;
    }

    // Nothing comes back and nothing on screen depends on it, so a failure is dropped:
    // the next pause, or leaving the page, will say the same thing again.
    fetch(this.urlValue, { method: "POST", body: body }).catch(() => {});
  }
}
