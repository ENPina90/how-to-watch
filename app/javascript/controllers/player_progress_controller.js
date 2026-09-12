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
//   the up-next mark, later, is when the card is offered by itself -- a fixed lead before
//   the end, so the countdown runs out as the film does.
//
// Playback itself is not saved. The player reports every ~5s while playing, and writing a
// row twelve times a minute per viewer buys nothing: anyone who leaves mid-film leaves the
// page, and leaving the page saves.
const SAVE_INTERVAL = 2000;

// How long before the end the up-next card comes up, if the page did not say. The live
// value is AppSetting#up_next_lead_seconds; this is only the fallback for a page rendered
// without it.
const DEFAULT_UP_NEXT_LEAD = 15;

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
    // AppSetting#up_next_lead_seconds: how long before the end the up-next card appears,
    // and how long it counts down for. Adjustable from the admin dashboard, which is why
    // it arrives from the page rather than living here as a constant.
    upNextLead: Number,
    // This player was warmed in the background before anybody flipped to it, so it has
    // been running with nobody in front of it and may already be past the point that
    // counts as watched. Set by cinema-navigation when it promotes a warmed frame.
    warmed: Boolean,
  };

  connect() {
    if (!isControllable(this.adapterValue)) return;

    const iframe = document.getElementById(this.frameValue);
    if (!iframe) return;

    this.iframe = iframe;
    this.lastSaved = 0;
    // Where this player is may not be anywhere anybody watched it get to. It stops being
    // unattended the moment the film is seen to move while somebody is here for it.
    this.unattended = this.warmedValue;
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

    // The film moved at the speed of the clock with a viewer in front of it: from here on
    // this is somebody watching, whatever the player did before they arrived.
    if (played) this.unattended = false;

    // The moment of crossing, not the state of being past it -- the player reports every
    // five seconds through the credits, and each of these should happen once. Seeking back
    // before a mark re-arms it, so watching the ending twice behaves the same way twice.
    const watched = finished || this.past(state, this.fractionValue);
    const crossedWatched = finished || (watched && !this.watched && played);
    this.watched = watched;

    const nearlyOver = finished || this.pastUpNextMark(state);
    const crossedUpNext = finished || (nearlyOver && !this.nearlyOver && played);
    this.nearlyOver = nearlyOver;

    // The card goes up over the film, in fullscreen and windowed alike. It lives inside
    // the element that goes fullscreen precisely so it can, and taking the screen back to
    // show it threw the viewer out of fullscreen for the last fifteen seconds of every
    // film -- which is the one stretch where being thrown out is most annoying, and where
    // a stinger is most likely to be playing.
    //
    // The screen is still handed back when nothing takes the card: auto-next off for this
    // channel, or a viewer who already pressed Stop. Then the film really is just ending,
    // and the ring of controls behind the player is the only thing to hand them.
    if (crossedUpNext && !this.upNext() && this.fullscreen) this.leaveFullscreen();

    if (crossedWatched) return this.save({ finished: finished, force: true });
    if (state.event === "paused" || state.event === "seeked") this.save();
  }

  // The configured lead, or the built-in one for a page that did not pass a usable value.
  // Guarded rather than trusted: a 0 here would put the mark at the very end of the film,
  // where the player may never report, and a negative one past it.
  get upNextLead() {
    const configured = this.upNextLeadValue;

    return configured > 0 ? configured : DEFAULT_UP_NEXT_LEAD;
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
  past(state, fraction) {
    const runtime = this.runtimeFor(state);

    return runtime > 0 && state.progress >= runtime * fraction;
  }

  // Is it within the lead of the end? The same rule AppSetting#up_next_mark_for applies,
  // floor included: a lead longer than what is left after the completion mark would put
  // the card up before the film counted as watched, and a two-minute clip is short enough
  // for fifteen seconds to do exactly that.
  pastUpNextMark(state) {
    const runtime = this.runtimeFor(state);
    if (!(runtime > 0)) return false;

    return state.progress >= Math.max(runtime - this.upNextLead, runtime * this.fractionValue);
  }

  // The catalogue's runtime where there is one, the player's reported duration otherwise --
  // the same preference the server has, for the same reason: the catalogue is the length of
  // the film and the player is timing whatever file it was handed, adverts and all.
  runtimeFor({ duration }) {
    return this.runtimeValue > 0 ? this.runtimeValue : duration;
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
  //
  // Answers whether anything took it. The card cancels the event when it is showing or
  // already counting, which is how this knows whether there is something on screen to
  // offer the viewer -- and so whether the screen needs handing back instead.
  upNext() {
    return this.dispatch("up-next", { target: document, cancelable: true }).defaultPrevented;
  }

  // Hand the page back when the film has ended with nothing to offer in its place, so the
  // ring of controls -- next entry, shuffle, home -- is there to use rather than behind a
  // full-screen player the viewer has to dismiss first.
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
    body.append("unattended", String(this.unattended));
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
