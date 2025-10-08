import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["entriesList", "entryItem"];
  static values = {
    currentEntryId: Number
  };

  connect() {
    console.log('Entries sidebar controller connected');
    console.log('Current Entry ID:', this.currentEntryIdValue);
  }
}
