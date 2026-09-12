import { Controller } from "@hotwired/stimulus";

// The Upload CSV button on the custom-entry page. The file input behind it is hidden and
// the button opens it, so the three controls in that row read as three buttons rather than
// two buttons and a file widget -- and picking a file is the whole gesture, with no second
// click on a submit nobody was looking for.
export default class extends Controller {
  static targets = ["input", "form"];

  choose() {
    this.inputTarget.click();
  }

  // Only on an actual pick. A cancelled dialog fires nothing in most browsers but change
  // with an empty list in some, and submitting that posts a file-less form for the server
  // to complain about.
  submit() {
    if (this.inputTarget.files.length === 0) return;

    this.formTarget.requestSubmit();
  }
}
