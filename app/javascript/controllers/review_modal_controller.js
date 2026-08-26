// app/javascript/controllers/review_modal_controller.js
import { Controller } from "@hotwired/stimulus";

// Drives the single shared review modal (entries/_review_modal_list). One modal serves
// every card on the page, so everything entry-specific -- the title, the form action and
// the two footer links -- is written on open from the trigger's data attributes.
export default class extends Controller {
  static targets = [
    "modal", "title", "form", "rating", "ratingDisplay",
    "comment", "submit", "skip", "dontAsk", "star"
  ];

  connect() {
    this.modalTarget.addEventListener("show.bs.modal", this.open);
  }

  disconnect() {
    this.modalTarget.removeEventListener("show.bs.modal", this.open);
  }

  // The three URLs are built here rather than shipped as attributes on every card: the
  // trigger renders once per entry, so 147 bytes of hrefs is 177 KB on a 1,200-entry
  // list. The cost is that these paths are duplicated from config/routes.rb -- the same
  // trade poster_selector_controller.js already makes for fetch_posters/update_poster.
  open = (event) => {
    const trigger = event.relatedTarget;
    if (!trigger) return;

    const { entryId, entryName, entryMedia } = trigger.dataset;

    this.titleTarget.innerHTML =
      `<i class="fa-solid fa-star text-warning me-2"></i>How was "${escapeHtml(entryName)}"?`;
    this.formTarget.action = `/entries/${entryId}/review`;
    this.skipTarget.href = `/entries/${entryId}/complete_without_review`;
    this.dontAskTarget.href = `/entries/${entryId}/complete_without_review?disable_reviews=true`;
    this.commentTarget.placeholder = `Share your thoughts about this ${entryMedia}...`;

    this.reset();
  };

  // The modal outlives each entry now, so last time's rating and comment have to be
  // cleared or they carry over to the next film that opens it.
  reset() {
    this.ratingTarget.value = "";
    this.commentTarget.value = "";
    this.submitTarget.disabled = true;
    this.ratingDisplayTarget.textContent = "No rating selected";
    this.ratingDisplayTarget.className = "badge bg-secondary";
    this.paint(0);
  }

  selectRating(event) {
    const rating = Number(event.currentTarget.dataset.rating);

    this.paint(rating);
    this.ratingTarget.value = rating;
    this.ratingDisplayTarget.textContent = `${rating}/10`;
    this.ratingDisplayTarget.className =
      rating >= 7 ? "badge bg-success" : rating >= 5 ? "badge bg-warning" : "badge bg-danger";
    this.submitTarget.disabled = false;
  }

  paint(rating) {
    this.starTargets.forEach((star, index) => {
      const filled = index < rating;
      star.classList.toggle("fa-solid", filled);
      star.classList.toggle("fa-regular", !filled);
      star.style.color = filled ? "#ffc107" : "#ddd";
    });
  }
}

function escapeHtml(value) {
  const div = document.createElement("div");
  div.textContent = value ?? "";
  return div.innerHTML;
}
