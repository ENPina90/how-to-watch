import { Controller } from "@hotwired/stimulus";
import * as bootstrap from "bootstrap";

// A flash says what just happened; it does not need to stay for the rest of the session.
// This closes it on its own after a while, and connects again whenever a turbo stream
// replaces the flash with a new one.
export default class extends Controller {
  static values = { after: { type: Number, default: 10000 } };

  connect() {
    this.start();

    // A message being read should not vanish mid-sentence.
    this.element.addEventListener("mouseenter", this.hold);
    this.element.addEventListener("mouseleave", this.resume);
  }

  disconnect() {
    clearTimeout(this.timer);
    this.element.removeEventListener("mouseenter", this.hold);
    this.element.removeEventListener("mouseleave", this.resume);
  }

  hold = () => clearTimeout(this.timer);
  resume = () => this.start();

  start() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.close(), this.afterValue);
  }

  close() {
    // Through bootstrap so it fades the way the close button does; if that is not around
    // for any reason, the message still goes.
    const alert = bootstrap.Alert.getOrCreateInstance(this.element);

    alert ? alert.close() : this.element.remove();
  }
}
