import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="randomize"
export default class extends Controller {
  static targets = ["upnext"];
  static values = { list: Number };

  connect() {
    // console.log(this.upnextTarget);
    this.entries = Array.from(document.querySelectorAll(".grid-card"));
  }

  shuffle(arr, num) {
    return arr.sort(() => 0.5 - Math.random()).slice(0, num);
  }

  upnext() {
    const randomEntries = this.shuffle(this.entries, 3);
    this.upnextTarget.querySelectorAll("a").forEach((link, index) => {
      let entry;
      if (index < 3) {
        entry = randomEntries[index];
        link.innerText = entry.querySelector(".card-header").innerText;
      } else {
        entry = this.shuffle(randomEntries, 1)[0];
      }
      link.href = entry.querySelector("a").href;
    });
  }
}
