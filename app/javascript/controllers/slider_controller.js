import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["sliderValueDisplay", "topEntriesLink", "slider"];

  connect() {
    this.listID = this.data.get('listId');
    this.tmdbID = this.data.get('tmdbId');
    // Set the initial slider value
    this.updateSliderValue(this.sliderTarget.value);
  }

  updateSliderValue() {
    const sliderValue = this.sliderTarget.value; // Get the current slider value
    // Update the displayed slider value
    this.sliderValueDisplayTarget.innerText = sliderValue;

    // Update the href of the link with the slider value and TMDb ID
    this.topEntriesLinkTarget.href = `/lists/${this.listID}/top_entries?tmdb=${this.tmdbID}&top_number=${sliderValue}`;
  }
}
