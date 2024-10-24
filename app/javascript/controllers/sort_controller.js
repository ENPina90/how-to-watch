import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

export default class extends Controller {
  connect() {
    // Initialize SortableJS
    this.sortable = Sortable.create(this.element, {
      animation: 150,
      handle: ".fa-grip-vertical", // Handle for dragging the element
      onEnd: this.updatePosition.bind(this) // Callback when the drag ends
    });
  }

  updatePosition(event) {
    const entryId = event.item.dataset.id;  // Get the ID of the dragged entry
    const newPosition = event.newIndex + 1; // SortableJS gives 0-based index, we need 1-based

    // Construct the correct URL for updating the position
    const url = `/entries/${entryId}/update_position`;

    // Send the updated position to the backend
    fetch(url, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
      },
      body: JSON.stringify({ position: newPosition })
    })
      .then(response => {
        if (!response.ok) {
          throw new Error('Failed to update position');
        }
      })
      .catch(error => {
        console.error('Error updating position:', error);
      });
  }
}
