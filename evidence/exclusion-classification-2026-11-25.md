# G5.04 — Exclusion classification (Coverage misclassification gap)

**G504-20261125-exclusion-classification · 2026-11-25 · evidence level, NOT gate acceptance.**

This record reclassifies the G5.01 "excluded" coverage holes and the D05 exclusions carried
forward by the [owner-approved reconciliation](traceability-2026-11-21/approved-reconciliation-2026-11-22.md)
into the three dispositions the G5.04 competition card (Notion task; link omitted in this public snapshot)
requires — "excluded/unreachable cases have justification; required scenarios are not silently
untested." It supersedes the flat "excluded, no scenario" framing in
`evidence/G5/g501-adversarial-seeded-2026-11-19/coverage-holes.md` (frozen G5.01 evidence, left unchanged) with a precise per-item disposition.
Checker/analysis-only; no RTL, simulation, new fixtures, or gate change.

## Disposition legend

- **Tested (witnessed scope):** covered by retained evidence at the stated scope.
- **Limited / deferred:** legal or DUT-observable but **untested** — no pinned reference oracle or no
  matched native witness. Reachable; to be addressed under a named later scope, not claimed tested.
- **Provably unreachable:** structurally impossible under the finite contract, with the contract/
  structural justification stated. Not "untested" — it cannot occur.

## Named items (the G5.04 gap)

| Item | Disposition | Justification and evidence |
| --- | --- | --- |
| SPI CS-boundary, transfer level (16-byte, modes 0–3) | **Tested (witnessed scope)** | s3 baseline re-verified in G4.04 and G5.01 S1; `evidence/G5/g504-sensitivity-2026-11-21/spi-timing-2026-11-21/report.md` and `evidence/G5/g504-sensitivity-2026-11-21/spi-timing-2026-11-21/coverage-addendum.md` credit the 16-byte mode 0–3 cases at their witnessed scope only. |
| SPI CS-boundary, **peer-controllable** extremes | **Provably unreachable** | The DUT is the SPI **master**; CSn is a DUT output (`CSn=uio3`, `docs/workloads.md`), so the external peer has no CSn drive path. A peer-driven CS extreme has no physical drive path under the contract. |
| SPI CS assertion/deassertion **timing** extremes (beyond transfer level) | **Limited / deferred** | CSn is DUT-internal and **measurable** ("the DUT's CSn can be measured; untested edge extremes are not unreachable", `evidence/G5/g504-sensitivity-2026-11-21/spi-timing-2026-11-21/coverage-addendum.md`); no pinned peer-extreme reference oracle exists, so these are untested-but-reachable, not unreachable. |
| PHASE-row cost, baseline durations (dur=100/25) | **Tested (witnessed scope)** | Formula `19 + 16*dur` is the G4.05 closure property (per-row cost model matches measured `run_ticks`), `evidence/G4/g405-budgets-2026-11-17/execution-table.json`; `evidence/G5/g501-adversarial-seeded-2026-11-19/design.md` H2. |
| PHASE min/max / **arbitrary** durations | **Limited / deferred** | Legal, but "sweeping arbitrary durations would require pinning oracle semantics for durations never executed in baseline (no reference measurement)" (`evidence/G5/g501-adversarial-seeded-2026-11-19/coverage-holes.md` H2); the oracle must not be invented. Reachable, so deferred, **not** unreachable. |

## Remaining D05 exclusions (reconciliation carry-forward)

| Exclusion | Disposition | Justification and evidence |
| --- | --- | --- |
| Full streaming / modes beyond the finite contract | **Provably unreachable** | Contract is finite: "no streaming beyond declared" size, "1..16 frames", "One active protocol instance" (`docs/workloads.md`). Streaming beyond declared size / unsupported modes cannot occur in a conformant program. |
| Analog board behavior / physical pad extremes | **Limited / deferred** | Outside the digital fixture; physical qualification belongs to G6. Real hardware, so not unreachable — but not testable in the digital scope. |
| Disabled-watchdog / error-priority kill | **Limited / deferred** | Reachable but no matched native witness; "a WAIT-limit timeout is not the global watchdog; reaching a watchdog is not proof a disabled-watchdog mutant fails" (`evidence/G5/g504-sensitivity-2026-11-21/native-faults-2026-11-21/independent-coverage-review.md`). |
| Integrated bounds / entry-validity / buffer limits | **Limited / deferred** | Individual guards are witnessed (F2 incomplete-COMMIT trap, bad image CRC) but the integrated limits are not; `evidence/G5/g504-sensitivity-2026-11-21/traceability-2026-11-21/approved-reconciliation-2026-11-22.md` lists them still-unavailable. |
| Exceptional-control ordering / side effects | **Limited / deferred** | No matched native witness; `evidence/G5/g504-sensitivity-2026-11-21/traceability-2026-11-21/approved-reconciliation-2026-11-22.md` lists them still-unavailable. |

## Boundary

This record **classifies** exclusions with justification; it does **not** close G5.04. G5.04 still
requires the remaining fault-injection gaps (raw boundary-timing / branch-path injection with an
independent pin/row assertion; loader/stop-safety image controls) and owner disposition. The
START/STOP/Sr order-and-count part of the gap is covered by
[start-stop-order-2026-11-25](start-stop-order-2026-11-25/report.md); the Data part by
[read-data-endtoend-2026-11-24](read-data-endtoend-2026-11-24/report.md). No RTL, simulation,
fixture, gate, REQ, or held-out selection changed; the frozen G5.01 `evidence/G5/g501-adversarial-seeded-2026-11-19/coverage-holes.md` is preserved.

## Provenance

- Supersedes (clarifies, does not rewrite): `evidence/G5/g501-adversarial-seeded-2026-11-19/coverage-holes.md` (frozen).
- Grounds: `evidence/G5/g504-sensitivity-2026-11-21/spi-timing-2026-11-21/coverage-addendum.md`; `evidence/G5/g504-sensitivity-2026-11-21/native-faults-2026-11-21/independent-coverage-review.md`; `evidence/G5/g504-sensitivity-2026-11-21/report.md`; `evidence/G5/g504-sensitivity-2026-11-21/traceability-2026-11-21/must-matrix.md`; `evidence/G5/g504-sensitivity-2026-11-21/traceability-2026-11-21/approved-reconciliation-2026-11-22.md`; `docs/workloads.md`; `evidence/G4/g405-budgets-2026-11-17/execution-table.json`; `evidence/G5/g501-adversarial-seeded-2026-11-19/design.md`.
- Generated: 2026-11-25T08:22:54Z.
