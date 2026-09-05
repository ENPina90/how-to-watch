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
//   the credits      crossing far enough through to count as watched
//   the end          the player's own `completed`
//
// The server decides for itself whether a saved position counts as watched, so a viewer
// who closes the tab during the credits is credited by the same rule as one who sits
// through them. The mark is mirrored here only to know when to say so; both sides read the
// same runtime and the same fraction, passed in below.
//
// Two marks, and they do different jobs:
//
//   the completion mark (from the server) is when the film counts as watched. Past it,
//   coming out of fullscreen means the film is over rather than interrupted, and the
//   up-next card is offered;
//   the credits mark, later, is when the page takes the screen back by itself -- or, for
//   somebody who never went fullscreen and so has no screen to take back, offers the card
//   where the exit would have.
//
// Playback itself is not saved. The player reports every ~5s while playing, and writing a
// row twelve times a minute per viewer buys nothing: anyone who leaves mid-film leaves the
// page, and leaving the page saves.
const SAVE_INTERVAL = 2000;

// When to hand the screen back. Deliberately later than the completion mark: a film counts
// as watched once the credits start, but a stinger after them is still the film, and
// taking the screen off somebody waiting for one is worse than leaving it a minute longer.
const CREDITS_FRACTION = 0.98;

// How much faster than wall-clock the position may move and still count as playback. The
// player reports about every five seconds and a film advances about a second per second,
// so a couple of times that is generous; a jump of an hour between two reports is not.
const PLAYBACK_TOLERANCE = 2;

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
    this.fullscreenChanged = () => this.fullscreenMoved();
    window.addEventListener("pagehide", this.leaving);
    document.addEventListener("visibilitychange", this.hiding);
    document.addEventListener("fullscreenchange", this.fullscreenChanged);
    document.addEventListener("webkitfullscreenchange", this.fullscreenChanged);
  }

  disconnect() {
    window.removeEventListener("pagehide", this.leaving);
    document.removeEventListener("visibilitychange", this.hiding);
    document.removeEventListener("fullscreenchange", this.fullscreenChanged);
    document.removeEventListener("webkitfullscreenchange", this.fullscreenChanged);
    this.player?.destroy();
  }

  // The page is about to move to another entry in place, so there is no unload coming to
  // catch the position on. Called by cinema-navigation before it changes the frame.
  saveNow() {
    this.save({ force: true })
  }

  playerReported(state) {
    this.state = state;

    // The player's own word for what happened, not the collapsed status: a seek and an
    // ending both leave the film stopped, and only one of them means it was watched.
    const finished = state.event === "completed";

    // Did the film play its way here, or did it arrive? vidsrc remembers its own position
    // and restores it a moment after the page opens -- an entry left in the credits comes
    // back with the credits rolling, which is not somebody watching to the end and must
    // not offer them the next entry before they have seen a frame. Dragging the scrubber
    // into the credits is the same thing by hand.
    //
    // The player's own `completed` is exempt: it is an event rather than a threshold, and
    // it only ever fires because the video ended just now.
    const played = this.playedUpTo(state);

    // The moment of crossing, not the state of being past it -- the player reports every
    // five seconds through the credits, and each of these should happen once. Seeking back
    // before a mark re-arms it, so watching the ending twice behaves the same way twice.
    const watched = finished || this.past(state, this.fractionValue);
    const crossedWatched = finished || (watched && !this.watched && played);
    this.watched = watched;

    const credits = finished || this.past(state, CREDITS_FRACTION);
    const crossedCredits = finished || (credits && !this.credits && played);
    this.credits = credits;

    // In fullscreen, the exit is what raises the up-next card: it fires fullscreenchange
    // like any other, so one path covers the exit below, the player's own control and a
    // viewer pressing escape through the credits. Windowed there is no exit to wait for,
    // and the card is raised here instead -- otherwise somebody who watches in a window
    // never gets offered the next entry at all.
    if (crossedCredits) {
      if (this.fullscreen) this.leaveFullscreen();
      else this.upNext();
    }

    if (crossedWatched) return this.save({ finished: finished, force: true });
    if (state.event === "paused" || state.event === "seeked") this.save();
  }

  // Has the position moved the way playing moves it -- forward, at about the speed of the
  // clock? Anything faster is the player jumping: restoring a remembered position, or a
  // scrubber dragged. Always false for the first report of a visit, which has nothing to
  // compare against and is simply where the player opened.
  playedUpTo({ progress }) {
    const now = Date.now();
    const previous = this.lastReport;
    this.lastReport = { progress: progress, at: now };

    if (!previous) return false;

    const elapsed = (now - previous.at) / 1000;
    const advanced = progress - previous.progress;

    // The constant of 3 covers a report arriving late and the position moving with it.
    return advanced >= 0 && advanced <= elapsed * PLAYBACK_TOLERANCE + 3;
  }

  // Is the film this far through? The same rule the server applies for the completion
  // mark, on the same two numbers, so the two agree about when a film has been watched.
  past({ progress, duration }, fraction) {
    const runtime = this.runtimeValue > 0 ? this.runtimeValue : duration;

    return runtime > 0 && progress >= runtime * fraction;
  }

  // Coming out of fullscreen past the completion mark means the film is over, whoever
  // ended it -- the exit above, the player's own control, or escape. Coming out before the
  // mark is somebody adjusting their screen, and is left alone.
  //
  // Keyed on the position rather than on the entry being marked watched, because a rewatch
  // is already marked and would otherwise offer the next entry from its opening titles.
  fullscreenMoved() {
    const left = this.wasFullscreen && !this.fullscreen;
    this.wasFullscreen = this.fullscreen;

    if (left && this.watched) this.upNext();
  }

  // Is anything on the page filling the screen? Not necessarily ours -- leaveFullscreen
  // checks that -- but enough to know whether there is an exit coming to wait for.
  get fullscreen() {
    return Boolean(document.fullscreenElement || document.webkitFullscreenElement);
  }

  // On the document because the card lives outside the cinema frame, in another corner of
  // the page. Raising it twice is harmless -- it ignores a second call while it is already
  // counting down, or once the viewer has stopped it -- but it is raised once.
  upNext() {
    this.dispatch("up-next", { target: document });
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
