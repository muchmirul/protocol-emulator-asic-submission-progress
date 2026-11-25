# G5.04 — End-to-end READ_RX data check (Data gap)

**G504-20261124-read-data-endtoend · 2026-11-24 · evidence level, NOT gate acceptance.**

## Why this check

The retained [wire_oracle](../i2c-program-fit/wire_oracle.py) checks the raw wire against
the **hardcoded** expected segments and the host log against the **same hardcoded**
readback. Both agree by construction, so a DUT that captured the wrong byte (or wrong
count) but still printed the expected log would pass both. That is the G5.04 **Data**
coverage gap: "A substituted CAP byte tests the comparator, not an end-to-end DUT data
mutation."

This check closes that blind spot. It reuses the frozen decoder
([decode.py](../i2c-bus-transcript/decode.py)) and the wire_oracle CASES table (single
source of truth) and, per run, compares the DUT's own `READ_RX` output to the **independently
decoded wire**:

1. decode the raw VCD and collect the target-driven (T) data bytes — the wire's read payload,
   independent of the DUT log;
2. parse the DUT's `READ_RX offset/count/data` line and the `op=0x22` reply frame;
3. assert `READ_RX` length and contents equal the wire read bytes (end-to-end);
4. independently recompute the reply-frame CRC16 (init `0xFFFF`, poly `0x1021`, MSB-first,
   no reflection, final XOR 0) over `[tag, len, status, read data]` from those raw bytes.

## Result

All five fixture runs pass: the DUT's `READ_RX` length and contents match the independently
decoded wire read payload, and the reply frame is well-formed.

```
nominal: PASS; wire_read=c369 READ_RX=c369 CRC16(a20200c369)=2c0b
changed-read: PASS; wire_read=3c96 READ_RX=3c96 CRC16(a202003c96)=3104
nack-write-address: PASS; wire_read=none READ_RX=none no read frame (READ_RX empty or absent)
nack-payload: PASS; wire_read=none READ_RX=none no read frame (READ_RX empty or absent)
nack-read-address: PASS; wire_read=none READ_RX=none no read frame (READ_RX empty or absent)
ALL 5 cases PASS: DUT READ_RX matches the independently decoded wire.
```

## Negative control (the check has teeth)

Two isolated log mutations, run against a copy (frozen evidence untouched), were each
detected with a non-zero exit:

| Mutation (isolated copy) | Detected as |
| --- | --- |
| nominal `READ_RX` data `c369` → `0069` (wire stays `c369`) | `READ_RX data '0069' != wire read bytes 'c369'` |
| changed-read `READ_RX` count `2` → `3` (wire stays 2 bytes) | `READ_RX count 3 != wire byte count 2` |

The retained wire_oracle would **not** detect either, because it compares only to the
hardcoded expected value. This check compares the DUT's output to the independently decoded
wire, so a wrong capture or wrong count fails.

## Boundary

Checker-only; no RTL, no simulation, no peer-log oracle, no frozen-evidence mutation.
Confirms the retained read data is internally and end-to-end consistent with the wire. It
does not close REQ-011, re-open the timing finding, or change any gate. The three refusal
paths correctly report an empty `READ_RX` record and no wire read bytes.

## Reproduction

```
python3.12 -B evidence/G5/g504-sensitivity-2026-11-21/read-data-endtoend-2026-11-24/check_read_endtoend.py
```

## Inputs and bundle hashes

- Inputs (frozen evidence, unchanged): {
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/wire_oracle.py": "75eea8906ce4fcf049dfa4d8ea51686995cc7b68991e11dce8b706c2fd04128e",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/run.py": "cb07853c1961812bdd2bb12ef612f44c0492426b68b60b4fe761865fa6edd0d3",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-bus-transcript/decode.py": "7121420c875ef7478bed36f4375060d5e34b63a10fb436ce4cb0f90d1bfac505",
  "evidence/G5/g504-sensitivity-2026-11-21/read-data-endtoend-2026-11-24/check_read_endtoend.py": "a8b367cf977fc037c6f70ca5038df480aaba5c1d9010ddad37c8df48e947c055"
}
- Trace VCD hashes: {
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/captures/nominal/trace.vcd": "c94ed42fd025f46f53674f13be8dfbcd654b6e0b8acc9afcbb0b8d078b279e12",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/captures/changed-read/trace.vcd": "c478dae35bc1189d442cf4594d656d437914e748efb952dca09d2e72aa1504ef",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/captures/nack-write-address/trace.vcd": "682b8624bd2f1189eaa09e2d3250895df9b1af59049b5aabda452005fd411f4c",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/captures/nack-payload/trace.vcd": "ab797801c3fa0ae9fda5d2bc5ce9839a17908c2c14ecd86785c1279c5da79d36",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/captures/nack-read-address/trace.vcd": "fde36b0a046d95e011c985ce42e1aac6de366d5aeb205a05345383faea991e97"
}
- Host log hashes: {
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/captures/nominal/run.log": "52ec5fd07eac66c4750127b9ff0fd59c167222b68b1e60b56da18d6b8718dc1a",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/captures/changed-read/run.log": "39de828fd36d74f46056365e74882b65f7f8e27af6ce9e1f64076ef0053a322b",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/captures/nack-write-address/run.log": "59db410d471c07a78f586b8dbbd029bd76814a54249398a67b049ddae97478fc",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/captures/nack-payload/run.log": "52ba80a94b808d04218b715b9737b12c3a7cc2f61ec43734b717d7f6bc7c4b1b",
  "evidence/G5/g504-sensitivity-2026-11-21/i2c-program-fit/captures/nack-read-address/run.log": "f80fa4437670b7472abb147934d8cecb947b5ec4e8ecfc3d961dedfd4e1fb5a0"
}
