Please file this upstream at https://github.com/promise-language/promise/issues

# No standard-library digest module: content addressing has to be hand-rolled

`promise version 2026.6 (channel stable)` · macOS 26.5.1 (arm64, Apple Silicon)

## What I needed and why

A content-addressed object store — the core of the mini-git task. Every added
file's raw bytes get hashed into a blob id, and each commit is identified by the
hash of its own serialized text. That needs one thing from the platform: a hash
over `u8[]` that is documented to be identical in every run, on every machine.

## What is missing

There is no `hash` / `digest` / `crypto` module in the catalog (`promise doc`
lists none), so the standard library offers no SHA-256, SHA-1, BLAKE3, or even a
documented stable non-cryptographic digest. What exists nearby:

- `gzip.crc32(u8[] data) u32` — a 32-bit integrity checksum, too narrow for
  object ids and not meant for content addressing.
- The `Hashable` structural interface's `get hash int`, used for `Map`/`Set`
  keys. It happened to be stable across two runs here
  (`"hello".hash == -6615550055289275125` both times), but nothing in
  `promise doc std` promises stability across runs, builds, or platforms, so it
  is not safe to persist on disk.
- `schema`'s `Hash128` identity — listed as planned.

## Did it block me?

No. The task explicitly allowed rolling my own, so `hash.pr` is a 19-line FNV-1a
(64-bit) over `u8[]`, rendered as 16 hex digits:

```promise
fnv1a_64(u8[] data) u64 `public {
  u64 hash = 0xcbf29ce484222325u64;
  for byte in data {
    hash = hash ^ (byte as u64);
    hash = hash * 0x100000001b3u64;
  }
  return hash;
}
```

That was pleasant to write — `u64` wrapping multiply behaves, and
`int.to_string(base: 16, width: 16, fill: '0')` renders the id in one call. But a
real tool wants a collision-resistant digest, and every project that stores
content by hash will otherwise ship its own copy of this.

## Sketch of the API that would have made it clean

A `hash` module with one-shot helpers plus a streaming form, mirroring how `io`
and `gzip` are shaped:

```promise
use hash;

main!() {
  // one-shot over bytes
  u8[] digest = hash.sha256(contents);          // 32 bytes
  string id = hash.sha256_hex(contents);        // "e3b0c442..."

  // streaming, for files too large to hold in memory
  hash.Sha256 state = hash.Sha256();
  state.write(chunk);                            // satisfies Writer
  string id2 = state.hex();

  // and a documented-stable fast hash for non-security uses
  u64 fast = hash.fnv1a_64(contents);
}
```

Two properties matter more than the algorithm choice: the digest must be
documented as stable across runs and platforms, and the streaming state should
satisfy the existing `Writer` interface so a file can be hashed while it is read.
