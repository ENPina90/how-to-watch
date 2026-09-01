import { playerAdapterFor } from "services/player_adapter";
import { Controller } from "@hotwired/stimulus";

// vidsrc's middle frame will not build the real player until someone clicks the play
// button sitting in it, and that frame is cross-origin, so the click cannot come from
// here. `autoplay=1` reaches the innermost player -- which already defaults to autoplay --
// but that player is never created until the click happens.
//
// Since the click cannot be removed, this at least says so: a black frame that is waiting
// for you looks identical to one that has failed to load.
export default class extends Controller {
  static values = { adapter: String, frame: String };

  connect() {
    const iframe = document.getElementById(this.frameValue);
    if (!iframe) return;

    // The hint must never eat the click it is asking for, so it is pointer-events: none in
    // CSS and the adapter tells us when to take it away.
    this.player = playerAdapterFor(this.adapterValue, iframe, {
      onState: () => this.dismiss(),
    });
  }

  disconnect() {
    this.player?.destroy();
  }

  dismiss() {
    this.element.hidden = true;
    this.player?.destroy();
    this.player = null;
  }
}
