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
//   the credits      crossing far enough through to count as watched, which also drops the
//                    player out of fullscreen -- see leaveFullscreen
//   the end          the player's own `completed`
//
// The server decides for itself whether a saved position counts as watched, so a viewer
// who closes the tab during the credits is credited by the same rule as one who sits
// through them. The mark is mirrored here only to know when to say so and when to leave
// fullscreen; both sides read the same runtime and the same fraction, passed in below.
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
    // The catalogue's runtime in seconds, 0 when it has none -- the player's own reported
    // duration stands in then, exactly as it does server-side.
    runtime: Number,
    // UserEntry::COMPLETION_FRACTION, passed rather than repeated so there is one of it.
    fraction: Number,
  };

  connect() {
    if (!isControllable(this.adapterValue)) return;

    const iframe = document.getElementById(this.frameValue);
    if (!iframe) return;

    this.iframe = iframe;
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
    const finished = state.event === "completed";
    const credits = finished || this.pastCreditsMark(state);

    // The moment of crossing, not the state of being past it -- the player reports every
    // five seconds through the credits, and this should happen once. Seeking back before
    // the mark re-arms it, so watching the ending twice leaves fullscreen twice.
    const crossed = credits && !this.pastCredits;
    this.pastCredits = credits;

    if (crossed) {
      this.leaveFullscreen();
      return this.save({ finished: finished, force: true });
    }

    if (finished) return this.save({ finished: true, force: true });
    if (state.event === "paused" || state.event === "seeked") this.save();
  }

  // The same rule the server applies, on the same two numbers, so the two agree about when
  // a film has been watched.
  pastCreditsMark({ progress, duration }) {
    const runtime = this.runtimeValue > 0 ? this.runtimeValue : duration;

    return runtime > 0 && progress >= runtime * this.fractionValue;
  }

  // Hand the page back once the credits are rolling, so the ring of controls -- next
  // entry, shuffle, home -- is there to use rather than behind a full-screen player the
  // viewer has to dismiss first.
  //
  // Leaving fullscreen needs no user gesture; only entering does. And the request belongs
  // to the top-level document even when the player inside the frame made it, which is what
  // makes this reachable at all on an embed we cannot otherwise touch.
  //
  // Three cases where nothing happens, all of them correct: nobody is in fullscreen; the
  // viewer is in the *browser's* fullscreen (F11, the green button), which is not this API
  // and leaves fullscreenElement null; or something else on the page is fullscreen and is
  // not ours to close. On an iPhone a video fills the screen through the native player
  // rather than through this API, so it stays as it is.
  leaveFullscreen() {
    const element = document.fullscreenElement || document.webkitFullscreenElement;
    if (!element) return;
    if (element !== this.iframe && !element.contains(this.iframe)) return;

    const exit = document.exitFullscreen || document.webkitExitFullscreen;
    try {
      // Older WebKit returns undefined rather than a promise; a rejection means the
      // browser declined, and nothing on the page depends on it either way.
      exit.call(document)?.catch(() => {});
    } catch {
      // Not available at all. The viewer closes it themselves, as they did before.
    }
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
