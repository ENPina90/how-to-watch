import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"
// The vendored turbo build exports the namespace and nothing else -- there is no named
// renderStreamMessage to import (see player_progress_controller.js).
import { Turbo } from "@hotwired/turbo-rails"

// The admin tables -- /admin/entries and /admin/subentries: the row actions and the edit
// modal, each of which exists once for a table thousands of rows long.
//
// The actions are one toolbar, moved into whichever row is pointed at or focused, with its
// links rewritten to that row's record. Its links are templates: ROW_ID is the number on the
// end of the row's own id (`entry_12`, `subentry_34`), and PARENT_ID is the row's
// `data-parent` -- an episode is watched through its show, so its watch link needs both. Drawn per row they were seven of every row's sixteen
// elements -- some 24,000 nodes for controls only ever visible on one row at a time.
//
// The pencil is then an ordinary link aimed at the frame inside the modal, so pressing it
// fetches that one entry's form and nothing else. What is left to do for the modal is its
// own behaviour: open when a form arrives, close when a save goes through. Opened on the
// frame's load rather than on the click, because Bootstrap's `data-bs-toggle` on a link
// cancels the click -- and a cancelled click is one Turbo declines to follow into a frame.
export default class extends Controller {
  static targets = ["modal", "frame", "actions", "delete"]
  // Where a pressed stream mark is sent, with ROW_ID for the entry. Only the entries table
  // has one: episodes have no stream to flip.
  static values = { streamUrl: String }

  connect() {
    // Held rather than looked up each time. The toolbar lives inside a row once placed, and a
    // save or a delete replaces or removes that row -- which takes the toolbar out of the
    // document with it. A target lookup would then find nothing; the element itself is
    // still here to be put into the next row.
    this.actions = this.actionsTarget
    this.deleteLink = this.deleteTarget

    this.frameTarget.addEventListener("turbo:frame-load", this.open)
    this.frameTarget.addEventListener("turbo:submit-end", this.submitted)
    this.modalTarget.addEventListener("hide.bs.modal", this.closing)
    this.modalTarget.addEventListener("hidden.bs.modal", this.closed)
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:frame-load", this.open)
    this.frameTarget.removeEventListener("turbo:submit-end", this.submitted)
    this.modalTarget.removeEventListener("hide.bs.modal", this.closing)
    this.modalTarget.removeEventListener("hidden.bs.modal", this.closed)
  }

  // Move the toolbar into the row under the pointer or the focus, and aim it at that entry.
  // Fired by every mouseover in the table, so the same row twice running is the common case
  // and costs one comparison.
  reveal({ target }) {
    const row = target.closest("tbody > tr[id]")
    if (!row || (row === this.row && row.contains(this.actions))) return

    const id = row.id.match(/_(\d+)$/)?.[1]
    if (!id) return

    for (const link of this.actions.querySelectorAll("a[data-template]")) {
      link.href = link.dataset.template
        .replace("ROW_ID", id)
        .replace("PARENT_ID", row.dataset.parent ?? "")
    }

    // Named, so the prompt says which entry is about to go rather than "this one" -- the
    // toolbar has just moved, and a delete is not something to take on trust.
    const name = row.querySelector(".et-name > a")?.textContent.trim()
    this.deleteLink.dataset.turboConfirm = name
      ? `Delete “${name}”? This cannot be undone.`
      : "Delete this row? This cannot be undone."

    row.querySelector(".et-name")?.append(this.actions)
    this.row = row
  }

  // Bootstrap ignores show() while the modal is still fading out, and a form fetches in
  // tens of milliseconds -- faster than the fade. So a pencil pressed just after closing
  // used to load its form into a modal that then finished closing over it. Asked mid-close,
  // the open waits for the close to finish instead.
  // The stream mark, pressed: working becomes broken, and broken or never-checked becomes
  // working. Delegated from the table like the toolbar, so the several thousand marks carry
  // no listener each. The value wanted is read off the mark and sent as a value rather than
  // as "flip", so a double press sets the same thing twice rather than undoing itself.
  async flip(event) {
    const mark = event.target.closest(".et-flip")
    if (!mark || !this.hasStreamUrlValue) return
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return

    event.preventDefault()
    if (mark.dataset.pending) return

    const row = mark.closest("tbody > tr[id]")
    const id = row?.id.match(/_(\d+)$/)?.[1]
    if (!id) return

    const hadFocus = document.activeElement === mark
    mark.dataset.pending = "true"
    mark.classList.remove("et-flip--failed")

    const body = new FormData()
    body.append("value", mark.classList.contains("et-ok") ? "false" : "true")

    try {
      const response = await fetch(this.streamUrlValue.replace("ROW_ID", id), {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
          Accept: "text/vnd.turbo-stream.html"
        },
        body
      })
      if (!response.ok) throw new Error(`stream flip answered ${response.status}`)

      // Redraws the row -- and the flash saying what changed. The mark pressed goes with the
      // old row, so a keyboard user's focus is put back on the new one.
      Turbo.renderStreamMessage(await response.text())
      if (hadFocus) this.refocus(row.id)
    } catch (error) {
      console.error(error)
      delete mark.dataset.pending
      mark.classList.add("et-flip--failed")
    }
  }

  // The stream renders on the next frame or two rather than on the spot, so wait for the
  // replacement row rather than focusing the one about to be thrown away.
  async refocus(rowId) {
    for (let frame = 0; frame < 10; frame++) {
      await new Promise((resolve) => requestAnimationFrame(resolve))
      const mark = document.getElementById(rowId)?.querySelector(".et-flip")
      if (mark && !mark.dataset.pending) return mark.focus()
    }
  }

  open = () => {
    if (this.isClosing) {
      this.reopen = true
      return
    }

    Modal.getOrCreateInstance(this.modalTarget).show()
  }

  closing = () => {
    this.isClosing = true
  }

  // A save answers with a stream that redraws the row, and a refusal answers 422 with the
  // form again, errors and all -- which Turbo draws back into the frame. Only the first is
  // a reason to close.
  submitted = (event) => {
    if (event.detail.success) Modal.getOrCreateInstance(this.modalTarget).hide()
  }

  // The src is dropped on a clean close, so pressing the same pencil again finds the frame
  // at no address and loads it afresh -- a frame already at the link's address would not
  // load at all. The form itself is left: the modal only opens once a new one has arrived,
  // so the old one is never on screen. Not dropped when a new form arrived during the close,
  // because that src is the one about to be shown.
  closed = () => {
    this.isClosing = false

    if (this.reopen) {
      this.reopen = false
      Modal.getOrCreateInstance(this.modalTarget).show()
      return
    }

    this.frameTarget.removeAttribute("src")
  }
}
