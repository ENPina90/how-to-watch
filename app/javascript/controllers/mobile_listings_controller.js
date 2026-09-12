import { Controller } from "@hotwired/stimulus"

// The cable listings on a phone.
//
// The grid is the desktop partial unchanged, and on the desktop the guide's own controller
// is what puts the present on screen when it opens. There is no guide controller here --
// this page is the grid and nothing else -- so this does the one thing that would otherwise
// be missing: a listing that opens at midnight is a listing nobody asked for.
//
// A third of the way in, the same place the full-sized guide settles on, so there is a
// little of what has been and most of the width is what has not happened yet.
const NOW_AT = 1 / 3

export default class extends Controller {
  static targets = ["scroller", "nowLine"]

  connect() {
    // After layout: the grid is sized in ems off a font that may not have arrived yet, and
    // a scroll worked out against the wrong width lands in the wrong hour.
    requestAnimationFrame(() => this.jumpToNow())
  }

  jumpToNow() {
    if (!this.hasScrollerTarget || !this.hasNowLineTarget) return

    const line = this.nowLineTarget.offsetLeft
    const left = Math.max(line - this.scrollerTarget.clientWidth * NOW_AT, 0)

    this.scrollerTarget.scrollTo({ left: left, behavior: "auto" })
  }
}
