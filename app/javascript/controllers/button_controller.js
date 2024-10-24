import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"];

  connect() {
    this.ellipsisIndex = 0;
    this.ellipsisCycle = ["", ".", "..", "..."]; // Cycles for ellipsis
    this.ellipsisElement = this.element.querySelector('.ellipsis'); // Target for the ellipsis span
  }

  start() {
    // Change button class
    this.element.classList.remove("btn-primary");
    this.element.classList.add("btn-secondary");
    this.element.querySelector('.static-text').innerText = "adding";


    // Start the ellipsis animation
    this.interval = setInterval(() => {
      this.updateEllipsis();
    }, 500); // Update every 500ms
  }

  updateEllipsis() {
    // Add the ellipsis based on the current cycle to the span
    this.ellipsisElement.innerText = this.ellipsisCycle[this.ellipsisIndex];

    // Cycle through the ellipsis steps
    this.ellipsisIndex = (this.ellipsisIndex + 1) % this.ellipsisCycle.length;
  }

  stop() {
    // Reset the button when necessary (if you need to stop the animation)
    clearInterval(this.interval);
    this.element.classList.remove("btn-secondary");
    this.element.classList.add("btn-primary");
    this.element.querySelector('.static-text').innerText = "adding";
    this.ellipsisElement.innerText = ""; // Clear the ellipsis
  }
}
