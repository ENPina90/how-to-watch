import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["sliderValueDisplay", "slider"];

  connect() {
    this.listID = this.data.get('listId');
    this.tmdbID = this.data.get('tmdbId');
    // Set the initial slider value
    this.updateSliderValue();
  }

  updateSliderValue() {
    // Update the displayed slider value
    this.sliderValueDisplayTarget.innerText = this.sliderTarget.value;
  }

  // Adding top episodes creates entries, so it posts a form with a CSRF token instead of
  // following a link. The modal lives inside a Mustache template, so the token is read
  // from the meta tag rather than rendered by Rails.
  addTopEntries() {
    const form = document.createElement("form");
    form.method = "post";
    form.action = `/lists/${this.listID}/top_entries`;
    form.style.display = "none";

    const fields = {
      tmdb: this.tmdbID,
      top_number: this.sliderTarget.value,
      authenticity_token: document.querySelector('meta[name="csrf-token"]')?.content
    };

    Object.entries(fields).forEach(([name, value]) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = name;
      input.value = value;
      form.appendChild(input);
    });

    document.body.appendChild(form);
    form.submit();
  }
}
