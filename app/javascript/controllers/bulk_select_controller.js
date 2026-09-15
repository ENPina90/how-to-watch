import { Controller } from "@hotwired/stimulus";

// Ticking entries in a channel's minimal view and deleting or editing them together.
//
// Lives on the page container rather than the list, because the checkboxes are inside the
// search results -- which the search controller replaces wholesale -- while the bulk edit
// modal sits outside them. Checkbox targets come and go with each search, so the count is
// recomputed whenever one connects or disconnects.
//
// The forms carry no ids of their own. Whatever is ticked is written in as hidden inputs
// at the moment of submitting, after the confirmation, so a box ticked after the modal
// opened is not left out.
export default class extends Controller {
  static targets = ["checkbox", "all", "count", "action"];

  checkboxTargetConnected() {
    this.refresh();
  }

  checkboxTargetDisconnected() {
    this.refresh();
  }

  get selectedIds() {
    return this.checkboxTargets.filter((box) => box.checked).map((box) => box.value);
  }

  refresh() {
    const selected = this.selectedIds.length;
    const total = this.checkboxTargets.length;

    this.countTargets.forEach((el) => { el.textContent = selected; });
    this.actionTargets.forEach((el) => { el.disabled = selected === 0; });

    if (this.hasAllTarget) {
      this.allTarget.checked = total > 0 && selected === total;
      this.allTarget.indeterminate = selected > 0 && selected < total;
    }
  }

  toggleAll(event) {
    const checked = event.currentTarget.checked;
    this.checkboxTargets.forEach((box) => { box.checked = checked; });
    this.refresh();
  }

  // One question for the whole selection, however many rows it is.
  //
  // preventDefault here stops Turbo too: its submit listener is on the document and skips
  // an event that has already been cancelled.
  confirmDelete(event) {
    const ids = this.selectedIds;

    if (ids.length === 0 || !window.confirm(`Delete ${this.entries(ids.length)}? This cannot be undone.`)) {
      event.preventDefault();
      return;
    }

    this.attachIds(event.target, ids);
  }

  confirmEdit(event) {
    const ids = this.selectedIds;
    const changes = this.filledFields(event.target);

    if (ids.length === 0) {
      event.preventDefault();
      return;
    }

    if (changes.length === 0) {
      event.preventDefault();
      window.alert("Fill in at least one field to change.");
      return;
    }

    const settings = changes.map(({ label, value }) => `${label} to "${value}"`);
    const message = `Are you sure you want to set ${this.sentence(settings)} for ${this.entries(ids.length)}?`;

    if (!window.confirm(message)) {
      event.preventDefault();
      return;
    }

    this.attachIds(event.target, ids);
  }

  // The fields that were filled in, named as the form labels them. A select reports the
  // option's text: "Source provider to 7" would say nothing about which one.
  filledFields(form) {
    return Array.from(form.elements)
      .filter((el) => el.name && el.name.startsWith("entry[") && el.value.trim() !== "")
      .map((el) => ({
        label: el.labels && el.labels[0] ? el.labels[0].textContent.trim() : el.name,
        value: el.tagName === "SELECT" ? el.selectedOptions[0].text.trim() : el.value.trim()
      }));
  }

  attachIds(form, ids) {
    form.querySelectorAll('input[name="entry_ids[]"]').forEach((input) => input.remove());

    ids.forEach((id) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "entry_ids[]";
      input.value = id;
      form.appendChild(input);
    });
  }

  entries(count) {
    return `${count} ${count === 1 ? "entry" : "entries"}`;
  }

  sentence(parts) {
    if (parts.length <= 1) return parts.join("");

    return `${parts.slice(0, -1).join(", ")} and ${parts[parts.length - 1]}`;
  }
}
