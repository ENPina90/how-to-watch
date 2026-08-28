import { Controller } from "@hotwired/stimulus";

const STORED = "channelSidebarCollapsed";

// The channel page's right sidebar. It reserves its own room by putting a class on <body>
// -- the same arrangement the watch page's sidebar uses -- so the page container can make
// space for it in CSS rather than every page having to know about it.
export default class extends Controller {
  connect() {
    document.body.classList.add("has-channel-sidebar");

    if (localStorage.getItem(STORED) === "true") this.collapse();
  }

  disconnect() {
    // The class outlives the element otherwise, and the next page would hold a gap open
    // for a sidebar that is not there.
    document.body.classList.remove("has-channel-sidebar", "channel-sidebar-collapsed");
  }

  collapse() {
    document.body.classList.add("channel-sidebar-collapsed");
    this.expandButton()?.classList.remove("d-none");
    this.remember(true);
  }

  expand() {
    document.body.classList.remove("channel-sidebar-collapsed");
    this.expandButton()?.classList.add("d-none");
    this.remember(false);
  }

  expandButton() {
    return document.getElementById("channelSidebarExpand");
  }

  // A preference, not state the page depends on: a browser that refuses storage just gets
  // the sidebar open every time.
  remember(collapsed) {
    try {
      localStorage.setItem(STORED, String(collapsed));
    } catch (error) {
      console.warn("Could not remember the sidebar state:", error);
    }
  }
}
