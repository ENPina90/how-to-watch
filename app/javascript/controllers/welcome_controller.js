import { Controller } from "@hotwired/stimulus";
import * as bootstrap from "bootstrap";

// The first-visit welcome. The server only renders it for a signed-out visitor without the
// `welcomed` cookie, so connecting is the signal to open it -- and to leave that cookie at
// once, so the next page does not open it again whichever way this one is left.
const YEAR = 60 * 60 * 24 * 365;

// Bootstrap's `lg` breakpoint, below which the navbar collapses and the sidebar is gone --
// most of what the welcome points at. The server already leaves the modal out for a phone
// it can recognise; this catches a tablet or a narrow window it cannot.
const WIDE_ENOUGH = "(min-width: 992px)";

export default class extends Controller {
  static targets = ["adblock", "adblockLink"];
  static values = { chromeUrl: String, firefoxUrl: String, safariUrl: String };

  connect() {
    // Too narrow: leave without the cookie, so the same visitor on a bigger screen is still
    // welcomed there.
    if (!window.matchMedia(WIDE_ENOUGH).matches) return this.element.remove();

    document.cookie = `welcomed=1; max-age=${YEAR}; path=/; samesite=lax`;

    const url = this.adblockUrl();
    if (url) {
      this.adblockLinkTarget.href = url;
      this.adblockTarget.hidden = false;
    }

    this.modal = bootstrap.Modal.getOrCreateInstance(this.element);
    this.modal.show();

    document.addEventListener("turbo:before-cache", this.forget);
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.forget);
    this.modal?.dispose();
  }

  // Leaving by a Turbo link snapshots the page for the back button with the modal still
  // up. The modal itself is data-turbo-temporary and drops out of the snapshot, but the
  // backdrop Bootstrap put on <body> does not, and going back would restore a page dimmed
  // behind nothing.
  forget = () => {
    document.querySelectorAll(".modal-backdrop").forEach((el) => el.remove());
    document.body.classList.remove("modal-open");
    document.body.style.removeProperty("overflow");
    document.body.style.removeProperty("padding-right");
  };

  // Closes the modal and puts the cursor in the navbar search, which opens its results
  // overlay on focus. Focus has to wait for the modal to be gone: Bootstrap hands focus
  // back to whatever had it before the modal opened, and would take it straight off the
  // field otherwise.
  search() {
    this.element.addEventListener("hidden.bs.modal", () => {
      document.getElementById("navbar-search")?.focus();
    }, { once: true });
    this.modal.hide();
  }

  // Which store to send them to, or nothing if the browser either blocks ads already
  // (Brave) or cannot take the extension. The order matters because user agents borrow
  // from each other: Edge and Opera both claim to be Chrome, and Chrome claims to be
  // Safari. On iOS every browser is Safari underneath and only Safari takes content
  // blockers, so Chrome and Firefox there (CriOS, FxiOS) get no link; Chrome on Android
  // takes no extensions at all, while Firefox on Android does.
  adblockUrl() {
    if (navigator.brave) return null;

    const ua = navigator.userAgent;
    if (/Edg|OPR|SamsungBrowser|CriOS|FxiOS/.test(ua)) return null;
    if (/Firefox\//.test(ua)) return this.firefoxUrlValue;
    if (/Chrome\//.test(ua)) return /Android/.test(ua) ? null : this.chromeUrlValue;
    if (/Safari\//.test(ua)) return this.safariUrlValue;
    return null;
  }
}
