import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="randomize"
export default class extends Controller {
  static targets = ["upnext"];
  static values = { list: Number };

  connect() {
    console.log(this.upnextTarget);
  }

  upnext() {
    const baseUrl = window.location.origin;
    const params = window.location.search;
    const fullUrl = `${baseUrl}/lists/${this.listValue}/randomize/${params}`;
    fetch(fullUrl)
      .then((response) => response.text())
      .then((data) => {
        this.upnextTarget.outerHTML = data;
      });
  }
}
