// Drives the player inside a vidsrc embed.
//
// The embed is three nested cross-origin frames -- wrapper, shell, player -- and each one
// relays postMessages verbatim in both directions, so the page around them can talk to the
// real player as though it were a child. The message shapes can change without warning --
// the downward protocol was read off the player's own handler and is documented nowhere --
// which is why every failure path here is "do nothing" rather than "throw".
//
// Up:   { type: "PLAYER_EVENT", data: { player_status, player_progress, player_duration } }
// Down: { player: true, action: "play" | "pause" | "mute" | "unmute" | "seek<N>" }
//
// Reports are handed on with both the raw `event` and a `status` collapsed to
// playing/paused, because the two callers want different things: the room only cares
// whether the film is moving, while position tracking has to tell a seek from an ending.
export default class VidsrcPlayer {
  // The front doors move around (vidsrc-embed.ru -> vsembed.ru, v2.vidsrc.me ->
  // vidsrcme.ru), so an origin is trusted by suffix rather than by exact host.
  //
  // This list has to be kept in step with the vidsrc Source templates: a domain that is
  // playable but missing here fails in the worst way -- the player loads and plays, but
  // every PLAYER_EVENT is rejected, so `started` never flips and play/pause/seek and all
  // position tracking silently stop. See docs/guides/VIDSRC.md.
  static ORIGINS = [
    // Ours, CNAMEd to vidsrc -- the frame is on our host but the player inside it is theirs.
    "framerelay.dev",
    "vidsrc2.ru", "vidsrc.ir",
    "vsembed.ru", "vidsrcme.ru", "vidsrc-embed.ru", "vidsrc.me",
    "cloudorchestranova.com",
  ];

  constructor(iframe, { onState }) {
    this.iframe = iframe;
    this.onState = onState;
    // Each relay level only forwards downward once it has built its child frame, and the
    // shell does not build one until the viewer clicks its play button. Commands sent
    // before that are dropped in silence, so nothing is sent until the player speaks.
    this.started = false;
    this.listener = (event) => this.receive(event);
    window.addEventListener("message", this.listener);
  }

  destroy() {
    window.removeEventListener("message", this.listener);
  }

  get ready() {
    return this.started;
  }

  trusted(origin) {
    try {
      const host = new URL(origin).hostname;
      return VidsrcPlayer.ORIGINS.some((o) => host === o || host.endsWith(`.${o}`));
    } catch {
      return false;
    }
  }

  receive(event) {
    if (event.source !== this.iframe.contentWindow) return;
    if (!this.trusted(event.origin)) return;

    const message = event.data;
    if (!message || message.type !== "PLAYER_EVENT" || !message.data) return;

    this.started = true;
    const { player_status: status, player_progress: progress, player_duration: duration } = message.data;
    this.onState({
      // The player's own word: "playing", "paused", "seeked" or "completed". Anything
      // that wants to know a film *finished*, rather than merely stopped, needs this.
      event: status,
      // Collapsed to what the film is doing now, which is all a watch party's clock is
      // about -- a seek and an ending both leave it stopped.
      status: status === "playing" ? "playing" : "paused",
      progress: Number(progress) || 0,
      duration: Number(duration) || 0,
    });
  }

  send(action) {
    if (!this.started) return;
    try {
      this.iframe.contentWindow.postMessage({ player: true, action }, "*");
    } catch {
      // A frame mid-navigation; the next heartbeat will try again.
    }
  }

  play()  { this.send("play"); }
  pause() { this.send("pause"); }

  // The player matches `seek([+-]?)([0-9]+)`, so a fractional target silently does
  // nothing. Whole seconds are finer than the 5s heartbeat can justify anyway.
  seek(seconds) { this.send(`seek${Math.max(0, Math.round(seconds))}`); }
}
