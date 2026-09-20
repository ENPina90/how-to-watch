// Drives a <video> of our own, for a provider the app plays itself.
//
// Every other adapter here talks to somebody else's player across an iframe boundary, by
// postMessage, in a protocol that is undocumented and can change without warning -- which
// is why each of them is written so that every failure path does nothing. This one has no
// boundary to cross. The element is in our document, so `play()` plays and `currentTime`
// is the position, and none of it can be refused, dropped or ignored.
//
// It reports the same four things the others do, in the same shape, so everything
// downstream -- position tracking, the up-next card, the keyboard, a watch party's clock --
// cannot tell the difference and needs no case for it.

// How often to report while playing. `timeupdate` fires four times a second, which is far
// more than anything here wants: player_progress judges whether a film "played its way"
// somewhere by comparing how far it moved against how long it has been, and it is written
// around reports about five seconds apart. Matching that keeps one rule for every provider.
const REPORT_EVERY = 5000;

export default class MegaPlayer {
  constructor(video, { onState }) {
    this.video = video;
    this.onState = onState;
    this.reportedAt = 0;

    this.handlers = {
      // The element's own word for what happened, which is what the collapsed status
      // cannot carry: a seek and an ending both leave a film stopped, and only one of them
      // means it was watched.
      playing: () => this.report("playing"),
      pause: () => this.report("paused"),
      seeked: () => this.report("seeked"),
      ended: () => this.report("completed"),
      // The heartbeat, throttled. Everything that tracks a position rides on this.
      timeupdate: () => this.tick(),
      // Not a state anybody listens for, but the moment the film's length is known, and
      // the first report is what tells the page it has a player at all.
      loadedmetadata: () => this.report("playing"),
    };

    Object.entries(this.handlers).forEach(([event, handler]) =>
      this.video.addEventListener(event, handler));
  }

  destroy() {
    Object.entries(this.handlers).forEach(([event, handler]) =>
      this.video.removeEventListener(event, handler));
  }

  // Ready the moment the element knows how long the film is. Unlike the embeds, there is
  // no handshake to wait for and no window in which commands are silently dropped -- but
  // seeking before the metadata arrives still does nothing, so the question is worth asking.
  get ready() {
    return this.video.readyState >= 1;
  }

  tick() {
    const now = Date.now();
    if (now - this.reportedAt < REPORT_EVERY) return;

    this.report(this.video.paused ? "paused" : "playing");
  }

  report(event) {
    this.reportedAt = Date.now();

    this.onState({
      event: event,
      status: event === "playing" ? "playing" : "paused",
      progress: Number(this.video.currentTime) || 0,
      // NaN before the metadata lands, and 0 is what every caller already treats as
      // "unknown length" -- see player_progress's lengthOf.
      duration: Number.isFinite(this.video.duration) ? this.video.duration : 0,
    });
  }

  // A play() that the browser refuses -- no gesture yet, or the tab in the background --
  // rejects rather than throwing, and is not a fault worth reporting: the viewer presses
  // play and it plays.
  play() { this.video.play()?.catch(() => {}); }
  pause() { this.video.pause(); }
  mute() { this.video.muted = true; }
  unmute() { this.video.muted = false; }

  seek(seconds) {
    if (!this.ready) return;

    this.video.currentTime = Math.max(0, seconds);
  }

  // Against where the film actually is, not against the last report -- the reports are five
  // seconds apart and a seek computed from one of them would be up to five seconds out.
  seekBy(seconds) {
    if (!this.ready) return;

    this.video.currentTime = Math.max(0, this.video.currentTime + seconds);
  }
}
