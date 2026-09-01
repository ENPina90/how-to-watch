import { Controller } from "@hotwired/stimulus";
import { createConsumer } from "@rails/actioncable";
import { playerAdapterFor, isControllable } from "services/player_adapter";

// The room, from the browser's side.
//
// Two different things travel over the socket, and keeping them apart is what makes this
// work. The host's player is the room's *clock*: it reports where it is, and guests are
// moved to match. Play and pause are an *intent*, carry no position, and may come from
// anyone the host allows -- so someone stopping the film cannot also drag everyone to
// wherever they happen to be sitting.
//
// Three things stop it fighting itself. A correction we asked for echoes back a moment
// later and must not read as the viewer acting; a command we applied must not be
// republished as though the viewer had pressed it; and small drift is left alone, because
// streams buffer independently and reseeking everyone every few seconds is worse to sit
// through than being a second out.
//
// The first two are windows rather than latches, and that distinction is the whole of a
// bug this had: a command the player ignores -- a pause it was already in, one sent while
// it was rebuilding a stream -- produces no echo at all, and a flag left waiting for one
// silently swallows the viewer's next real press. Which is exactly what "it worked for a
// while and then stopped" looks like from the sofa.
const ECHO_WINDOW = 2000;
export default class extends Controller {
  static targets = ["members", "status", "link", "permission"];
  static values = {
    token: String,
    adapter: String,
    host: Boolean,
    frame: String,
    guestsCanControl: Boolean,
    // Past this many seconds away from the host, a guest is pulled back into line.
    tolerance: { type: Number, default: 2.5 },
  };

  connect() {
    const iframe = document.getElementById(this.frameValue);
    if (!iframe) return;

    this.controllable = isControllable(this.adapterValue);
    this.lastSent = 0;
    this.echoes = {};
    this.player = playerAdapterFor(this.adapterValue, iframe, {
      onState: (state) => this.playerReported(state),
    });

    this.consumer = createConsumer();
    this.subscription = this.consumer.subscriptions.create(
      { channel: "WatchPartyChannel", token: this.tokenValue },
      {
        received: (data) => this.received(data),
        // A socket that goes away takes the room with it, silently: the film keeps
        // playing, nothing follows anyone any more, and the bar looks exactly as it did
        // when it was working. These say so. The client reconnects on its own, so
        // "Reconnecting" is a state to wait out rather than act on -- but a room that has
        // been quietly dead for ten minutes should not look identical to a live one.
        connected: () => this.socketUp(),
        disconnected: () => this.socketDown(),
        rejected: () => this.setStatus("Could not rejoin the room — reload the page."),
      },
    );

    if (!this.controllable) this.setStatus("Sync unavailable on this source — press play together.");
    this.renderPermission();
  }

  disconnect() {
    clearTimeout(this.statusTimer);
    this.subscription?.unsubscribe();
    this.consumer?.disconnect();
    this.player?.destroy();
  }

  get mayControl() {
    return this.hostValue || this.guestsCanControlValue;
  }

  // ---- our own player ----------------------------------------------------------------

  playerReported(state) {
    // The same report sometimes arrives twice -- visible in the server log as a pair of
    // identical heartbeats a millisecond apart. Left alone, the first copy consumes the
    // record of a command we issued and the second is then read as the viewer acting, so
    // one duplicated report can publish a press nobody made. A player that is playing
    // never reports the same position twice, so an exact repeat is never real.
    const previous = this.local;
    if (previous && previous.status === state.status && previous.progress === state.progress) return;

    this.local = state;

    // A correction we asked for, echoed back. Acting on it would restart the loop.
    if (this.wasOurs("seek")) return;

    // A play or pause the viewer performed themselves, rather than one we just applied on
    // the room's behalf. That is the whole signal -- a deliberate press.
    const pressed = previous && previous.status !== state.status;
    const ours = this.wasOurs("command");
    if (pressed && !ours && this.mayControl && !this.hostValue) {
      this.subscription?.perform("control", { status: state.status });
      this.assumeRoomStatus(state.status);
    }

    if (this.hostValue) return this.publish(state);

    // Guests report position so presence stays fresh, at the player's own cadence rather
    // than a timer of our own.
    this.subscription?.perform("heartbeat", { progress: state.progress });
    this.reconcile();
  }

  // The host's heartbeat arrives about every five seconds; sending every one of them is
  // the point, but a state change fires its own event immediately and would otherwise
  // double up with the tick either side of it.
  publish(state) {
    if (this.connected === false) return;

    const now = Date.now();
    if (now - this.lastSent < 750) return;
    this.lastSent = now;
    this.subscription?.perform("state", { status: state.status, progress: state.progress });
  }

  socketUp() {
    this.connected = true;
    this.clearStatus();
  }

  socketDown() {
    this.connected = false;
    // Anything we were told about the room stopped being true the moment we stopped
    // hearing from it; acting on it after a reconnect would move people on stale news.
    this.host = null;
    this.setStatus("Reconnecting…");
  }

  // ---- the room ----------------------------------------------------------------------

  received(data) {
    switch (data.action) {
      case "state":    return this.hostMoved(data);
      case "control":  return this.roomPressed(data);
      case "settings": return this.permissionChanged(data);
      case "navigate": return this.followNavigation(data);
      case "presence": return this.renderMembers(data.members);
      case "closed":   return this.partyEnded();
    }
  }

  hostMoved(data) {
    if (data.guests_can_control !== undefined) {
      this.guestsCanControlValue = data.guests_can_control;
      this.renderPermission();
    }
    // Being in the room is the normal state and needs no commentary, so the placeholder
    // goes as soon as there is something behind it.
    this.clearStatus();

    // The host is the clock, so their own copy has nothing to learn from its own echo.
    if (this.hostValue) return;

    // The host is a clock, not a snapshot. It reports every five seconds or so, and
    // reconcile runs on our own player's reports in between -- so what matters is not
    // where the host was when it spoke, but where it is now. Freezing the number it sent
    // and comparing against that meant a viewer who was correctly in step got dragged
    // backwards by however far into the gap between messages they happened to report.
    //
    // The trip time is folded in here because it has already elapsed; everything after
    // this is measured from when we heard it.
    const latency = data.at ? Math.max(0, Date.now() / 1000 - data.at) : 0;
    this.host = {
      status: data.status,
      progress: data.progress + (data.status === "playing" ? latency : 0),
      heardAt: Date.now(),
    };
    this.reconcile();
  }

  // Someone in the room hit play or pause. Everyone follows, including the host -- that is
  // the point of letting guests do it at all.
  roomPressed(data) {
    // Our own press, already applied when we made it.
    if (data.by === this.currentUserId) return;

    this.assumeRoomStatus(data.status);

    if (!this.controllable || !this.player.ready) return;
    if (this.local?.status === data.status) return;

    this.expectEcho("command");
    if (data.status === "playing") this.player.play();
    else this.player.pause();
  }

  // A press changes what the room is doing, and only the host's `state` was ever recording
  // that. Reconcile runs against this within milliseconds -- on our own player's very next
  // report -- so leaving it on the previous status meant the press was undone before the
  // room had even answered: the host pauses, you hit play, and something pauses you
  // straight back. Rebasing the position first keeps a resume counting from where the
  // room stopped rather than from wherever the clock had reached.
  assumeRoomStatus(status) {
    if (!this.host || this.host.status === status) return;

    this.host = { status: status, progress: this.hostProgressNow(), heardAt: Date.now() };
  }

  // Where the host's player is right now, rather than where it was when it last said so.
  hostProgressNow() {
    if (this.host.status !== "playing") return this.host.progress;

    return this.host.progress + (Date.now() - this.host.heardAt) / 1000;
  }

  reconcile() {
    if (this.hostValue || !this.host || !this.controllable || !this.player.ready) return;
    if (!this.local) return;

    const drift = this.local.progress - this.hostProgressNow();

    // Being a little out is the normal condition of two independent streams, and saying so
    // every five seconds is noise. Only a correction is worth a word.
    if (Math.abs(drift) > this.toleranceValue) {
      this.expectEcho("seek");
      this.player.seek(this.hostProgressNow());
      this.setStatus(`Resynced ${this.format(Math.abs(drift))}`, { transient: true });
    }

    if (this.host.status === "playing" && this.local.status !== "playing") {
      this.expectEcho("command");
      this.player.play();
    }
    if (this.host.status === "paused" && this.local.status === "playing") {
      this.expectEcho("command");
      this.player.pause();
    }
  }

  followNavigation(data) {
    if (this.hostValue || !data.url) return;
    // Turbo is switched off on the player page (`data-turbo="false"` in special_layout),
    // so this is a real navigation rather than a visit.
    window.location.assign(data.url);
  }

  partyEnded() {
    this.setStatus("The host ended the watch party.");
    this.subscription?.unsubscribe();
  }

  // ---- who may stop the film ---------------------------------------------------------

  togglePermission() {
    if (!this.hostValue) return;
    this.subscription?.perform("permission", { allowed: !this.guestsCanControlValue });
  }

  permissionChanged(data) {
    this.guestsCanControlValue = data.guests_can_control;
    this.renderPermission();
  }

  renderPermission() {
    if (!this.hasPermissionTarget) return;

    const open = this.guestsCanControlValue;
    this.permissionTarget.textContent = open ? "Anyone can pause" : "Only you can pause";
    this.permissionTarget.setAttribute("aria-pressed", String(open));
  }

  // ---- the bar -----------------------------------------------------------------------

  renderMembers(members) {
    if (!this.hasMembersTarget) return;

    this.membersTarget.replaceChildren(
      ...members.map((member) => {
        const chip = document.createElement("span");
        chip.className = `watch-party__member${member.host ? " watch-party__member--host" : ""}`;
        chip.textContent = member.name;
        return chip;
      }),
    );
  }

  // We just told the player to do something and expect it to say so back.
  expectEcho(kind) {
    this.echoes[kind] = Date.now();
  }

  // Was this report the echo of something we asked for? Reading consumes it either way, so
  // a command that never produced one cannot go on suppressing later reports.
  wasOurs(kind) {
    const at = this.echoes[kind];
    if (at === undefined) return false;

    delete this.echoes[kind];
    return Date.now() - at < ECHO_WINDOW;
  }

  get currentUserId() {
    return Number(this.element.dataset.watchPartyUserId);
  }

  setStatus(text, { transient = false } = {}) {
    if (!this.hasStatusTarget) return;

    clearTimeout(this.statusTimer);
    this.statusTarget.textContent = text;
    if (transient) this.statusTimer = setTimeout(() => this.clearStatus(), 4000);
  }

  clearStatus() {
    if (!this.hasStatusTarget) return;
    clearTimeout(this.statusTimer);
    this.statusTarget.textContent = "";
  }

  format(seconds) {
    return seconds < 60 ? `${seconds.toFixed(1)}s` : `${Math.round(seconds / 60)}m`;
  }

  // Copy the invitation. The link is the room.
  copy() {
    if (!this.hasLinkTarget) return;
    navigator.clipboard.writeText(this.linkTarget.dataset.url).then(() => {
      this.setStatus("Invite link copied.", { transient: true });
    });
  }
}
