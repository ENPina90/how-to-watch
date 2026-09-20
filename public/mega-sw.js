// Serves a MEGA file to a <video> element of our own, as ordinary same-origin MP4.
//
// Everything a MEGA link needs is in the link: the handle names the file, the fragment
// carries the key that decrypts it. MEGA's API hands out a plain HTTPS URL for the bytes,
// that URL honours `Range`, and both it and the API answer with `Access-Control-Allow-
// Origin: *` -- so the whole transfer can happen in the browser, and the only thing
// missing between those bytes and a picture is the decryption.
//
// That is what this does. It claims `/mega/<handle>/<key>/video.mp4`, turns each request
// the video element makes into a ranged fetch from MEGA, decrypts what comes back and
// answers with it. The element on the page is then playing an ordinary MP4 from its own
// origin: it seeks, it reports its position, it can be paused, and every feature a MEGA
// entry has never had -- resume, the watched mark, the up-next card, the keyboard, a watch
// party -- works because there is no longer anybody else's player in the way.
//
// Why a service worker rather than fetching the file and handing over a blob: the files
// are feature-length, hundreds of megabytes each. A blob means downloading all of it
// before the first frame and holding it in memory. Intercepting ranges means the browser
// asks for what it needs, when it needs it, and seeking costs one request.
//
// Why not MediaSource: MSE takes only fragmented MP4 or WebM, and these are ordinary
// progressive MP4s. Remuxing them in JavaScript is exactly what MEGA's own player does,
// and rebuilding that is how you inherit its faults. A <video> pointed at a URL that
// honours ranges lets the browser demux natively, which it is far better at than we would
// be.
//
// Measurements behind all of the above are in docs/guides/MEGA.md.

const API = "https://g.api.mega.co.nz/cs";

// AES block size. Every counter and every aligned offset below is a multiple of it.
const BLOCK = 16;

// MEGA's download URLs are time-limited. This is well inside what they are good for, and
// an expired one is re-asked for anyway when a fetch comes back refusing -- the TTL is to
// avoid the refusal, not to rely on it.
const URL_TTL = 20 * 60 * 1000;

// How much to read ahead of what was asked for when the request is open-ended. Chrome
// opens a media file with `Range: bytes=0-`, meaning "all of it", and answering that
// literally would stream 600MB through the decryptor for the sake of the first frame.
const OPEN_ENDED_CHUNK = 4 * 1024 * 1024;

// One entry per file, holding the URL its bytes come from and how long the file is.
const nodes = new Map();

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  // Everything else on the origin is the app's own and none of our business. A worker that
  // answered more than it claimed would be a worker that can break the whole site.
  const claim = url.pathname.match(/^\/mega\/([^/]+)\/([^/]+)\/video\.mp4$/);
  if (!claim) return;

  event.respondWith(serve(claim[1], claim[2], event.request));
});

// ---- MEGA -----------------------------------------------------------------------------

// Where this file's bytes are, and how many of them there are.
//
// `g: 1` is what asks for a download URL, and it is the call that spends transfer quota --
// which is why MegaAvailability, which only ever asks whether a file exists, deliberately
// leaves it out. Here we are actually playing the thing, so it is the right call.
//
// `ssl: 2` asks for an HTTPS node. Without it MEGA answers with a plain http:// address,
// which a page served over HTTPS will refuse to load as mixed content -- so the flag is
// not a preference, it is the difference between working in production and not.
async function nodeFor(handle, { fresh = false } = {}) {
  const held = nodes.get(handle);
  if (!fresh && held && Date.now() - held.at < URL_TTL) return held;

  const response = await fetch(`${API}?id=0`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify([{ a: "g", g: 1, ssl: 2, p: handle }]),
  });

  const body = await response.json();
  const file = Array.isArray(body) ? body[0] : body;

  // MEGA answers a bare negative number for everything it refuses: -9 no such file, -16
  // taken down, -2 not a link it recognises. MegaAvailability::GONE has the full list and
  // the reasoning; here any of them is simply "no".
  if (typeof file === "number" || !file || !file.g) {
    throw new Error(`MEGA refused ${handle}: ${JSON.stringify(file)}`);
  }

  const node = { url: file.g, size: file.s, at: Date.now() };
  nodes.set(handle, node);

  return node;
}

// The two things the key gives us: the AES key the file is encrypted with, and the nonce
// that begins every counter block.
//
// MEGA packs both into the 32 bytes in the link. The first sixteen XORed with the second
// sixteen are the key -- the same fold MegaAvailability does in Ruby to check that a key
// opens a file -- and the first eight of the second half are the nonce.
async function openWith(text) {
  const raw = base64(text);
  if (raw.length < 24) throw new Error("the link's key is too short to open anything");

  const aes = new Uint8Array(BLOCK);
  for (let i = 0; i < BLOCK; i += 1) aes[i] = raw[i] ^ raw[i + BLOCK];

  return {
    key: await crypto.subtle.importKey("raw", aes, "AES-CTR", false, ["decrypt"]),
    nonce: raw.slice(BLOCK, BLOCK + 8),
  };
}

// MEGA writes base64 the URL-safe way and without padding, which is also how the key
// arrives in our own path.
function base64(text) {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);

  return bytes;
}

// The counter block for a given 16-byte block of the file: the nonce, then the block's
// index as a 64-bit big-endian number. This is what makes the file seekable -- any block
// can be decrypted on its own, without the ones before it, which is the whole reason
// ranges work at all.
function counterAt(nonce, block) {
  const counter = new Uint8Array(BLOCK);
  counter.set(nonce, 0);
  new DataView(counter.buffer).setBigUint64(8, BigInt(block), false);

  return counter;
}

// ---- serving --------------------------------------------------------------------------

// What the element asked for, in absolute byte offsets, or null when it asked for the lot.
//
// Only the one form is honoured. `bytes=N-` and `bytes=N-M` are what a media element sends;
// suffix ranges (`bytes=-N`) and multi-part ranges are in the spec and are not sent by any
// player, so rather than half-implement them this treats them as no range at all.
function asked(header, size) {
  const match = /^bytes=(\d+)-(\d*)$/.exec(header || "");
  if (!match) return null;

  const start = Number(match[1]);
  const end = match[2] === "" ? size - 1 : Math.min(Number(match[2]), size - 1);

  return start > end || start >= size ? null : { start, end, open: match[2] === "" };
}

async function serve(handle, key, request) {
  try {
    const node = await nodeFor(handle);
    const range = asked(request.headers.get("Range"), node.size);

    const start = range ? range.start : 0;
    // An open-ended ask is answered with a chunk rather than the rest of the film. The
    // element comes back for more the moment it needs it, and 206 is the honest status for
    // "here is part of it" -- which is also what it asked for.
    const end = range && !range.open
      ? range.end
      : Math.min(start + OPEN_ENDED_CHUNK - 1, node.size - 1);

    // Decryption has to begin on a block boundary, so the fetch starts at or before what
    // was asked for and the surplus is dropped after decrypting.
    const from = start - (start % BLOCK);
    const body = await decrypted(node, key, from, end, start - from, request.signal);

    return new Response(body, {
      status: 206,
      headers: {
        "Content-Type": "video/mp4",
        "Content-Length": String(end - start + 1),
        "Content-Range": `bytes ${start}-${end}/${node.size}`,
        "Accept-Ranges": "bytes",
        // The bytes are the same every time and are expensive to fetch again, but they are
        // also somebody's private file: held by this browser, never by a shared cache.
        "Cache-Control": "private, max-age=3600",
      },
    });
  } catch (error) {
    // A media element reads any error response as "this file is broken" and stops, which
    // is the right outcome; the message is here so the page's own log can say why.
    return new Response(`MEGA playback failed: ${error.message}`, {
      status: 502,
      headers: { "Content-Type": "text/plain" },
    });
  }
}

// The decrypted bytes for one range, as a stream.
//
// Streamed rather than assembled, because even a single request can be several megabytes
// and the element wants the front of it immediately. `skip` is how much of the first block
// belongs to somebody else -- the surplus from aligning the start -- and is dropped before
// anything is handed on.
async function decrypted(node, keyText, from, to, skip, signal) {
  const { key, nonce } = await openWith(keyText);
  const source = await fetchRange(node, from, to, signal);
  const reader = source.getReader();

  let block = from / BLOCK;
  let carry = new Uint8Array(0);
  let dropped = 0;

  return new ReadableStream({
    async pull(controller) {
      const { done, value } = await reader.read();

      if (done) {
        // A final partial block is still decryptable -- CTR is a keystream, so the tail
        // needs no padding and no special case beyond being shorter than sixteen bytes.
        if (carry.length) controller.enqueue(await open(carry));
        controller.close();
        return;
      }

      const merged = join(carry, value);
      const whole = merged.length - (merged.length % BLOCK);
      carry = merged.subarray(whole);

      if (whole > 0) controller.enqueue(await open(merged.subarray(0, whole)));
    },
    cancel(reason) {
      reader.cancel(reason);
    },
  });

  async function open(bytes) {
    const plain = new Uint8Array(await crypto.subtle.decrypt(
      { name: "AES-CTR", counter: counterAt(nonce, block), length: 64 }, key, bytes
    ));
    block += Math.ceil(bytes.length / BLOCK);

    if (dropped >= skip) return plain;

    const cut = Math.min(skip - dropped, plain.length);
    dropped += cut;

    return plain.subarray(cut);
  }
}

// The encrypted bytes, with one retry on a URL that has gone stale.
//
// MEGA's download URLs expire, and an expired one does not announce itself in advance -- it
// simply stops answering. Asking again produces a fresh one, and the second failure is a
// real one worth reporting.
async function fetchRange(node, from, to, signal) {
  const pull = (url) => fetch(url, { headers: { Range: `bytes=${from}-${to}` }, signal });

  let response = await pull(node.url);
  if (!response.ok) {
    const fresh = await nodeFor(handleOf(node), { fresh: true });
    response = await pull(fresh.url);
  }

  if (!response.ok) throw new Error(`MEGA answered ${response.status} for the file's bytes`);
  if (!response.body) throw new Error("MEGA answered without a body");

  return response.body;
}

// Which file a cached node belongs to. Kept as a lookup rather than stored on the node so
// there is one copy of the mapping, and it is only ever needed on the retry path above.
function handleOf(node) {
  for (const [handle, held] of nodes) if (held === node) return handle;

  throw new Error("lost track of which MEGA file this was");
}

function join(head, tail) {
  if (!head.length) return tail;

  const merged = new Uint8Array(head.length + tail.length);
  merged.set(head, 0);
  merged.set(tail, head.length);

  return merged;
}
