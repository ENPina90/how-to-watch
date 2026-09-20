import VidsrcPlayer from "services/vidsrc_player";
import YoutubePlayer from "services/youtube_player";
import MegaPlayer from "services/mega_player";
import ManualPlayer from "services/manual_player";

// Which adapter drives a given provider. The name comes from the server
// (Source#sync_adapter) so the mapping lives in one place: adding a provider that can be
// driven means naming its adapter there and adding a case here.
const ADAPTERS = {
  vidsrc: VidsrcPlayer,
  youtube: YoutubePlayer,
  // Not an embed. This one drives a <video> in our own document -- same interface, none of
  // the postMessage guesswork, and nothing that can decline to answer.
  mega: MegaPlayer,
};

export function playerAdapterFor(name, iframe, handlers) {
  const Adapter = ADAPTERS[name];
  return Adapter ? new Adapter(iframe, handlers) : new ManualPlayer();
}

export function isControllable(name) {
  return Object.hasOwn(ADAPTERS, name || "");
}
