// Drives the player inside a YouTube embed.
//
// YouTube's IFrame API script is a wrapper around exactly this -- postMessage down to the
// frame and back up -- so speaking the protocol directly costs neither a script from
// youtube.com on every watch page nor the second frame the script would build. It is the
// same handshake trailer-reel and cable-standby already rely on.
//
// The embed only talks to a page that has asked it to, and asking takes two things. The URL
// must carry `enablejsapi=1` (Source::PLAYER_PARAMS adds it): without it the frame ignores
// the handshake entirely, measured 2026-09-15. And the page must send `listening`, after
// which the frame posts `infoDelivery` about four times a second while it plays.
//
// Up:   { event: "onReady" | "initialDelivery" | "infoDelivery", info: { ...whatever changed } }
//       { event: "onStateChange", info: <playerState> }
// Down: { event: "command", func: "playVideo" | "pauseVideo" | "mute" | "unMute" | "seekTo", args }
//
// Reports are handed on in the shape VidsrcPlayer uses, so nothing downstream needs to know
// which player it is hearing. Two differences are smoothed over here rather than there.
// YouTube reports far more often than vidsrc's five seconds, so steady playback is passed on
// once a second -- position tracking and the watch party were both written for a heartbeat,
// not a stream. And it has no seek event, so a position that jumps is called one.

// The embed is not listening until it has loaded, and there is no announcing the moment, so
// ask more than once. Asking again once the frame fires `load` covers a slow one.
const HANDSHAKES = [0, 700, 1800, 4000];

// How often steady playback is passed on. Changes of state are passed on at once.
const HEARTBEAT = 1000;

// How far the position may stray from where playing would have put it before it counts as a
// jump. Reports carry their own jitter, and a stall to buffer holds the position still.
const SEEK_SLACK = 2;

// YouTube's playerState. -1 (unstarted) and 5 (cued) are a player that has not begun, which
// is nobody pausing it, and so has no word of its own here.
const ENDED = 0;
const PLAYING = 1;
const WORDS = { 1: "playing", 2: "paused", 3: "buffering" };

export default class YoutubePlayer {
  static ORIGINS = ["www.youtube.com", "www.youtube-nocookie.com"];

  constructor(iframe, { onState }) {
    this.iframe = iframe;
    this.onState = onState;
    this.started = false;
    // What the player has said so far. Each delivery carries only what changed, so the
    // position, the length and the state arrive separately and are kept together here.
    this.info = {};
    this.listener = (event) => this.receive(event);
    this.loaded = () => this.handshake();
    window.addEventListener("message", this.listener);
    iframe.addEventListener("load", this.loaded);
    this.timers = HANDSHAKES.map((delay) => setTimeout(() => this.handshake(), delay));
  }

  destroy() {
    window.removeEventListener("message", this.listener);
    this.iframe.removeEventListener("load", this.loaded);
    this.timers.forEach(clearTimeout);
  }

  get ready() {
    return this.started;
  }

  trusted(origin) {
    try {
      return YoutubePlayer.ORIGINS.includes(new URL(origin).hostname);
    } catch {
      return false;
    }
  }

  handshake() {
    this.post({ event: "listening", id: this.iframe.id });
    this.post({ event: "command", func: "addEventListener", args: ["onStateChange"] });
  }

  receive(event) {
    if (event.source !== this.iframe.contentWindow) return;
    if (!this.trusted(event.origin)) return;

    let message;
    try {
      message = typeof event.data === "string" ? JSON.parse(event.data) : event.data;
    } catch {
      return;
    }
    if (!message || typeof message !== "object") return;

    switch (message.event) {
      case "onReady":
        this.started = true;
        return;
      case "onStateChange":
        return this.heard({ playerState: message.info });
      case "initialDelivery":
      case "infoDelivery":
        return this.heard(message.info || {});
    }
  }

  // Folds a delivery into what is known and passes a report on if it amounts to one. Most
  // deliveries are about volume or quality and change nothing that anybody downstream reads.
  heard(info) {
    const before = { ...this.info };
    const now = Date.now();

    ["currentTime", "duration", "playerState"].forEach((key) => {
      if (typeof info[key] === "number") this.info[key] = info[key];
    });
    if (typeof this.info.playerState !== "number") return;

    this.started = true;

    const jumped = typeof info.currentTime === "number" && this.jumped(before, now);
    if (typeof info.currentTime === "number") this.heardAt = now;

    const event = this.eventFor(jumped, now);
    if (!event) return;

    this.lastEvent = event;
    this.lastReported = now;
    this.onState({
      event: event,
      // A stall to buffer is not anybody stopping the film, and a room that followed it
      // would pause everybody else whenever one connection hiccupped.
      status: event === "playing" || event === "buffering" ? "playing" : "paused",
      progress: this.info.currentTime || 0,
      duration: this.info.duration || 0,
    });
  }

  // The player's own word where it has one, "seeked" where the position jumped, and a
  // repeat of "playing" once a heartbeat while nothing else is happening.
  eventFor(jumped, now) {
    const state = this.info.playerState;

    // Once. It goes on saying the video is ended for as long as it sits there.
    if (state === ENDED) return this.lastEvent === "completed" ? null : "completed";
    if (jumped) return "seeked";

    const word = WORDS[state];
    if (!word) return null;
    if (word !== this.lastEvent) return word;
    if (word === "playing" && now - this.lastReported >= HEARTBEAT) return word;

    return null;
  }

  // Is the position somewhere playing could not have taken it since the last one?
  jumped(before, now) {
    if (typeof before.currentTime !== "number" || !this.heardAt) return false;

    const elapsed = (now - this.heardAt) / 1000;
    const expected = before.playerState === PLAYING ? before.currentTime + elapsed : before.currentTime;

    return Math.abs(this.info.currentTime - expected) > SEEK_SLACK;
  }

  post(message) {
    try {
      this.iframe.contentWindow?.postMessage(JSON.stringify(message), "*");
    } catch {
      // A frame mid-navigation. The next handshake or command will find it.
    }
  }

  // Held until the player has spoken, as VidsrcPlayer holds them: a command to a frame that
  // is not listening yet is dropped without a word.
  command(func, args = []) {
    if (!this.started) return;
    this.post({ event: "command", func: func, args: args });
  }

  play()   { this.command("playVideo"); }
  pause()  { this.command("pauseVideo"); }
  mute()   { this.command("mute"); }
  unmute() { this.command("unMute"); }

  // `true` lets it fetch past what is buffered, which a seek from the page always wants.
  seek(seconds) { this.command("seekTo", [Math.max(0, seconds), true]); }

  // YouTube has no relative seek, so this works one out -- but from a position at most a
  // quarter of a second old, which is exact enough that taps accumulate the way they do on
  // vidsrc's own relative seek.
  seekBy(seconds) {
    if (seconds === 0 || typeof this.info.currentTime !== "number") return;

    const playing = this.info.playerState === PLAYING && this.heardAt;
    const now = playing ? this.info.currentTime + (Date.now() - this.heardAt) / 1000 : this.info.currentTime;

    this.seek(now + seconds);
  }
}
