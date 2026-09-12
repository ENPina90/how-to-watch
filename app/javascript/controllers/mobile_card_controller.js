import { Controller } from "@hotwired/stimulus"

// A card on the phone grid, turning over to show what it is.
//
// The class goes on the card rather than on the faces: the turn is one transform on the
// pair, and putting it on either face would turn them independently and show both edge-on
// at the same moment.
export default class extends Controller {
  flip() {
    this.element.classList.toggle("m-card--flipped")
  }
}
