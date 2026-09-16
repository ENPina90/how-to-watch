import { Controller } from "@hotwired/stimulus";

// The fanedit-only fields on the entry forms. `original`, `faneditor`, `fanedit_link` and
// `fanedit_type` describe a cut, so they mean nothing on a film or an episode and are only
// shown when the media select says fanedit.
//
// Shown and hidden rather than added and removed: they stay in the form either way, so a
// fanedit typed up, switched to `movie` by mistake and switched back still has everything
// that was entered in it. Anything left in them on a non-fanedit is saved and simply not
// drawn -- the card reads them only for a fanedit, and a column nobody can see is a
// cheaper mistake than losing what somebody typed.
//
// The server renders the panel already open for an entry that is a fanedit, so the fields
// are there before this connects. `connect` then syncs to whatever the select actually
// shows, which is what the *new* form needs: the entry has no media yet, and the browser
// selects the first option -- Fanedit -- with nothing on the server having said so.
export default class extends Controller {
  static targets = ["media", "panel"];

  connect() {
    this.toggle();
  }

  toggle() {
    this.panelTarget.hidden = this.mediaTarget.value !== "fanedit";
  }
}
