// The fallback for providers that hand the page no control at all -- Drive, MEGA, and
// anything behind the custom catch-all.
//
// It reports nothing and obeys nothing, which is the honest answer: the party can still
// keep everyone on the same entry and tell them what the host is doing, but nobody's
// player can be moved for them. The party bar reads `controllable` to decide whether to
// promise sync or ask people to press play themselves.
export default class ManualPlayer {
  constructor() {
    this.started = false;
  }

  destroy() {}

  get ready() { return false; }

  play()  {}
  pause() {}
  seek()  {}
}
