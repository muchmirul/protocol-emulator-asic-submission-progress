# Jane Street ASIC — submission progress

This repository is a progress snapshot for the Jane Street protocol-emulator ASIC competition. It is **not the final submission**. It contains selected source files and engineering results, not the complete verification or physical-design package.

| Area | Recorded progress |
| --- | --- |
| Digital verification | 176 selected operation cases passed. A separate seeded regression recorded 149/149 passes. These runs are not exhaustive and do not verify installed hardware. |
| Hardware baseline | The seven [B17 RTL source files](frozen-b17/rtl) are byte-for-byte copies of the frozen baseline files. This is a source reference, not a runnable Tiny Tapeout flow. No candidate RTL or layout is included. |
| Formal and timing | Formal evidence is inconclusive. Directed simulation and inspection cover only their documented cases. Macro enable delays and example bus calculations below are not measurements at installed pins. |
| Final package | This snapshot does not include the full test suite, passing GDS and precheck tied to the submission revision, architecture and instruction-set documentation, the toolchain with example programs, or a complete verification write-up. |

## Selected engineering evidence

- [I²C macro output-enable timing](engineering/i2c-macro-oe-arcs.json): 84 saved model points. The largest modeled delays were 7.15428 ns to request low and 6.79081 ns to release, both on SDA. Both end at the macro enable terminal, not the wire. The [ideal release example](engineering/i2c-macro-oe-release-example.json) does not qualify the installed 100 ns first-threshold budget.
- [I²C pull-up calculation](engineering/i2c-pullup-rise.json): at 2,310 Ω and 100 pF, the modeled 30–70% rise is 195.726 ns with no leakage and 202.446 ns with a constant 20 µA sink. These examples are not hardware measurements or evidence of a standards violation.
- [G5.04 end-to-end READ_RX data check](evidence/g504-read-data-endtoend-2026-11-24/report.md): checker-only evidence comparing the DUT's READ_RX output to the independently decoded wire read payload (5/5 pass) and recomputing the reply-frame CRC16. The bundled script needs the full local evidence tree to run; this snapshot records the result, not the full reproduction.

- [G5.04 I2C START/STOP/Sr order-and-count check](evidence/start-stop-order-2026-11-25/report.md): checker-only invariants over the seven retained B16 I2C traces (event ordering, START/Sr-to-segment count, byte/ninth consistency, documented per-fixture signatures), 7/7 pass. The bundled script needs the full local evidence tree to run; this snapshot records the result, not the full reproduction.

- [G5.04 exclusion classification](evidence/exclusion-classification-2026-11-25.md): coverage-gap review that reclassifies the D05 exclusions (SPI CS boundary, PHASE durations, streaming, analog, watchdog, bounds) into tested / limited-deferred / provably-unreachable, with contract and evidence justification. This copy is public-sanitized (the competition Notion link is omitted).
- [File checksums](SHA256SUMS): run `sha256sum -c SHA256SUMS` to verify the seven RTL files, three data files, and the G5.04 evidence. No new simulation, synthesis, or hardware tests were run for this export.

[Apache License 2.0](LICENSE)
