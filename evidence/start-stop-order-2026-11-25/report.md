# G5.04 — I2C START/STOP/Sr order and count invariants (Coverage misclassification gap)

**G504-20261125-start-stop-order · 2026-11-25 · evidence level, NOT gate acceptance.**

## Why this check

The G5.04 [coverage-misclassification gap](../report.md) notes that the retained G5.01
checker "parses but does not fully assert START/STOP/stretch order/count." The I2C
transaction structure (START, repeated START `Sr`, STOP) is decoded by the frozen
[decoder](../i2c-bus-transcript/decode.py) into an ordered `events` list and a per-START/Sr
`segments` list, but no retained checker asserted those invariants. This check closes that
part: it re-decodes each of the seven retained B16 traces from the published archive and
asserts the START/STOP/Sr **order** and **count** invariants directly.

## What it asserts

Per transcript, on a **fresh re-decode** (not just the published JSON):

1. Faithful to the published transcript (events, segments, SHA-256 all match).
2. First event is `START`.
3. No `unpaired_SDA_rise` event.
4. **Order** adjacency: after `START`/`Sr` the next event is `STOP` or `Sr`; after `STOP` the next
   event is `START`. (A `STOP` or a `START`/`Sr` may be the final event.)
5. **Count**: number of segments == number of `START`/`Sr` events.
6. Per segment: `len(bytes_hex) == len(ninth)` and `len(sda_low_sources) >= 9*len(bytes_hex)`.
7. Event times are monotonic; all `where` fields are in {run, exit, post}; exactly one complete RUN window.
8. **Fixture structure regression**: the event sequence equals the documented structure in
   [i2c-bus-transcript/report.md](../i2c-bus-transcript/report.md) (frozen B16 fixtures):
   s1/s2/s8/s9 `START STOP START STOP`, s3 (NACK) `START`, s4 (ACK) `START STOP`,
   s5 (repeated START) `START Sr STOP`.

## Result

```
s1-i2c100-w16: PASS; events=['START', 'STOP', 'START', 'STOP'] START/Sr=2 segments=2
s2-i2c400-w16: PASS; events=['START', 'STOP', 'START', 'STOP'] START/Sr=2 segments=2
s8-i2c100-r16: PASS; events=['START', 'STOP', 'START', 'STOP'] START/Sr=2 segments=2
s9-i2c400-r16: PASS; events=['START', 'STOP', 'START', 'STOP'] START/Sr=2 segments=2
s3-i2c-nack: PASS; events=['START'] START/Sr=1 segments=1
s4-i2c-ack: PASS; events=['START', 'STOP'] START/Sr=1 segments=1
s5-i2c-rs: PASS; events=['START', 'Sr', 'STOP'] START/Sr=2 segments=2
ALL 7 transcripts PASS: START/STOP/Sr order and count invariants hold.
```

## Negative control (the check has teeth)

Eight isolated event-structure mutations, each run against a decoded copy (frozen evidence
untouched), were all detected with a non-zero exit:

| Mutation | Detected as |
| --- | --- |
| s4 drop the `STOP` (`START STOP` → `START`) | event sequence `['START']` != documented `['START','STOP']` |
| s4 swap `START`/`STOP` order | first event not `START`; sequence != documented |
| s4 insert `unpaired_SDA_rise` | contains `unpaired_SDA_rise`; `START` followed by `unpaired_SDA_rise` |
| s4 remove the segment | `0 segments != 1 START/Sr events` |
| s1 shorten a segment's ninth list | `bytes(16) != ninth(15)` |
| s5 two plain `START`s (`START START STOP`) | `START` followed by `START`; sequence != documented |
| s5 extra trailing `STOP` | `STOP` followed by `STOP`; sequence != documented |
| s4 non-monotonic event times | first event not `START`; times not monotonic |

The general invariants (1–7) catch misordering, unpaired events, and count/byte mismatches.
The documented-signature regression (8) additionally catches a dropped/extra `STOP` or a
mis-typed repeated start on these specific frozen fixtures.

## Boundary / limitations

Checker-only; no RTL, simulation, fixture mutation, or peer-log oracle. It asserts the
**wire** START/STOP/Sr order and count on the frozen B16 transcripts. It does **not**
independently assert clock-**stretch** behavior — the decoder does not model stretch as a
distinct event, and the report explicitly treats stretch as a separate requirement. The
documented-signature layer is a regression check on the frozen, documented fixtures, not a
general protocol-conformance proof. It does not close REQ-011, re-open the timing finding,
change any gate, or assert host-log↔wire agreement (a separate cross-check).

## Reproduction

```
python3.12 -B evidence/G5/g504-sensitivity-2026-11-21/start-stop-order-2026-11-25/check_start_stop_order.py
```

## Inputs and bundle hashes

- Inputs (frozen, unchanged): {
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-bus-transcript/decode.py": "7121420c875ef7478bed36f4375060d5e34b63a10fb436ce4cb0f90d1bfac505",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-bus-transcript/transcripts.json": "1fa17b63fcbf4ac46abe8e9e5d85339ee6923809ab10acde32da17b9a7685bba",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-bus-transcript/retained-traces.zip": "e1a4f02ddd33208d1fd5f1c1e8f062c172a798a015ccd529263ba9a291520210",
  "evidence/G5/g504-sensitivity-2026-11-21/start-stop-order-2026-11-25/check_start_stop_order.py": "95bc6c699edefe4d2fa0744e42b61e8eace588a6f2f860f4b21e004bbff0e79b"
}
