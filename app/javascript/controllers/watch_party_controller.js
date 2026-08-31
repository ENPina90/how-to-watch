import { Controller } from "@hotwired/stimulus";
import { createConsumer } from "@rails/actioncable";
import { playerAdapterFor, isControllable } from "services/player_adapter";

// The room, from the browser's side. The host's player is the clock: it reports where it
// is, the server passes that on, and every guest's player is moved to match.
//
// Two things keep this from fighting itself. A guest that has just been seeked reports the
// new position a moment later, which must not read as the guest having moved on their own,
// so corrections are marked and ignored on the way back. And drift is only worth correcting
// past a threshold -- streams buffer independently and a party that reseeks everyone every
// few seconds is worse to sit through than one that is a second out.
export default class extends Controller {
  static targets = ["members", "status", "link"];
  static values = {
    token: String,
    adapter: String,
    host: Boolean,
    frame: String,
    // Past this many seconds behind or ahead of the host, a guest is pulled back into line.
    tolerance: { type: Number, default: 2.5 },
  };

  connect() {
    const iframe = document.getElementById(this.frameValue);
    if (!iframe) return;

    this.controllable = isControllable(this.adapterValue);
    this.lastSent = 0;
    this.correcting = false;
    this.player = playerAdapterFor(this.adapterValue, iframe, {
      onState: (state) => this.playerReported(state),
    });

    this.consumer = createConsumer();
    this.subscription = this.consumer.subscriptions.create(
      { channel: "WatchPartyChannel", token: this.tokenValue },
      { received: (data) => this.received(data) },
    );

    if (!this.controllable) this.setStatus("Sync unavailable on this source — press play together.");
  }

  disconnect() {
    clearTimeout(this.statusTimer);
    this.subscription?.unsubscribe();
    this.consumer?.disconnect();
    this.player?.destroy();
  }

  // ---- our own player ----------------------------------------------------------------

  playerReported(state) {
    this.local = state;

    // A correction we asked for, echoed back. Acting on it would restart the loop.
    if (this.correcting) {
      this.correcting = false;
      return;
    }

    if (this.hostValue) return this.publish(state);

    // Guests report position so the bar can show the gap, at the player's own cadence
    // rather than a timer of our own.
    this.subscription?.perform("heartbeat", { progress: state.progress });
    this.reconcile();
  }

  // The host's heartbeat arrives about every five seconds; sending every one of them is
  // the point, but a state change fires its own event immediately and would otherwise
  // double up with the tick either side of it.
  publish(state) {
    const now = Date.now();
    if (now - this.lastSent < 750) return;
    this.lastSent = now;
    this.subscription?.perform("state", { status: state.status, progress: state.progress });
  }

  // ---- the room ----------------------------------------------------------------------

  received(data) {
    switch (data.action) {
      case "state":    return this.hostMoved(data);
      case "navigate": return this.followNavigation(data);
      case "presence": return this.renderMembers(data.members);
      case "closed":   return this.partyEnded();
    }
  }

  hostMoved(data) {
    // Being in the room is the normal state and needs no commentary, so the placeholder
    // goes as soon as there is something behind it.
    this.clearStatus();

    // The projection the server sends was true when it sent it; by the time it arrives the
    // host has moved on by however long the trip took.
    const latency = data.at ? Math.max(0, Date.now() / 1000 - data.at) : 0;
    this.host = {
      status: data.status,
      progress: data.progress + (data.status === "playing" ? latency : 0),
    };
    this.reconcile();
  }

  reconcile() {
    if (this.hostValue || !this.host || !this.controllable || !this.player.ready) return;
    if (!this.local) return;

    const drift = this.local.progress - this.host.progress;

    // Being a little out is the normal condition of two independent streams, and saying so
    // every five seconds is noise. Only a correction is worth a word.
    if (Math.abs(drift) > this.toleranceValue) {
      this.correcting = true;
      this.player.seek(this.host.progress);
      this.setStatus(`Resynced ${this.format(Math.abs(drift))}`, { transient: true });
    }

    if (this.host.status === "playing" && this.local.status !== "playing") this.player.play();
    if (this.host.status === "paused" && this.local.status === "playing") this.player.pause();
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
