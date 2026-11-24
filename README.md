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
- [File checksums](SHA256SUMS): run `sha256sum -c SHA256SUMS` to verify the seven RTL files and three data files. No new simulation, synthesis, or hardware tests were run for this export.

[Apache License 2.0](LICENSE)
