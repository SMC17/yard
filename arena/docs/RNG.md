# `blake3-counter-v1`

Yard Arena random draws are pure functions of:

```text
seed: u64 little-endian
stream_id: u8
draw_index: u64 little-endian
```

Hash input bytes are:

```text
"yard-arena/blake3-counter-v1" || 0x00 || seed || stream_id || draw_index
```

Apply unkeyed BLAKE3 and interpret digest bytes `0..8` as little-endian `u64`.
For a unit double, discard the low 11 bits and divide the remaining 53-bit
integer by `2^53`. The result is in `[0, 1)`.

Stream IDs in Arena v0 are fixed by `RngStream` declaration order:

| ID | Stream |
|---:|---|
| 0 | weather |
| 1 | demand |
| 2 | damage |
| 3 | traffic |
| 4 | sensor noise |

Published conformance vector:

```json
{"algorithm":"blake3-counter-v1","seed":"42","stream_id":0,"draw_index":"7","u64_hex":"99bc0b490101ad93","unit_f64":0.60052557499239490}
```

Generate vectors with:

```sh
zig build rng-vector -- 42 0 7
```

The decimal `unit_f64` is diagnostic. Cross-language conformance is decided by
the exact `u64_hex` value; downstream floating-point simulation equivalence is
a separate proof gate.

