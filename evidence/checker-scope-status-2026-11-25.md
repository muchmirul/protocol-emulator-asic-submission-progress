# G5.04 — Checker-scope status (disposition summary)

**G504-20261125-checker-scope-status · 2026-11-25T08:36:00Z · evidence level, NOT gate acceptance.**

Synthesis of the G5.04 checker-only work against the four gaps in the initial
[report](report.md) "Remaining coverage and closure boundary." This is a disposition summary
for owner review, not a gate pass. It does not re-run anything and does not change any gate,
REQ, or the frozen B17 baseline.

## G5.04 scope (unchanged)

Checker-only evidence and requalification of the three retained G5.01 fault-injection pairs
against the frozen B17 baseline. **No fresh DUT mutation, no HDL simulation, no held-out
selection, no release decision.** A gap that needs a new fault-injection scenario or a new
image fixture therefore falls **outside** this checker-only scope and is carried to a
new-simulation scope that requires an explicit owner grant.

## Gap-by-gap status

| Gap (from report) | Status in checker scope | Evidence / reason |
|---|---|---|
| **Data** — exact READ_RX length/contents, capture counts, independent CRC from raw bytes | **Closed (checker scope)** | [read-data-endtoend-2026-11-24](read-data-endtoend-2026-11-24/report.md): compares DUT READ_RX to the independently decoded wire read payload (5/5 pass) and independently recomputes the reply-frame CRC16 over raw bytes; 2 isolated log mutations detected. |
| **Coverage misclassification** — SPI CS / PHASE as limited/deferred; assert START/STOP(/stretch) order/count | **Closed (checker scope)** | [start-stop-order-2026-11-25](start-stop-order-2026-11-25/report.md): START/STOP/Sr order-and-count invariants on the seven retained B16 traces (7/7 pass; 8 mutations detected). [exclusion-classification-2026-11-25](exclusion-classification-2026-11-25.md): SPI CS / PHASE (and carry-forward exclusions) classified as tested / limited-deferred / provably-unreachable with justification. Note: clock-**stretch** is not modeled as a distinct event by the decoder, so it is carried as *limited/deferred* in the exclusion classification, not asserted by a check. |
| **Raw timing and branch path** — a real boundary-timing injection and a branch-outcome/path injection with an independent pin/row assertion | **Carried (needs new-simulation scope)** | Needs a new controlled fault-injection scenario (real boundary-timing or branch-outcome mutant) with a restored clean source — i.e. new HDL simulation / peer or RTL mutant, outside the checker-only scope. The START/STOP/Sr check asserts wire transaction structure but does not inject a timing/branch fault. |
| **Loader / stop safety** — clean/invalid image controls across invalidation, reset/deselect, illegal start | **Carried (needs new-simulation scope)** | Needs new clean/invalid image fixtures across the named invalidation paths — new HDL simulation, outside the checker-only scope. The [exclusion classification](exclusion-classification-2026-11-25.md) documents the loader-valid guards already witnessed (F2 incomplete-COMMIT trap, bad image CRC) and classifies the rest as limited/deferred, but does not add the new image controls. The G5.03 reset/STOP discrepancy stays open separately. |

## Disposition for the owner

- **Checker-scope G5.04 work is complete for the two in-scope gaps** (Data; coverage
  misclassification). No further checker-only gap in the table remains unaddressed.
- **Two gaps are carried to a new-simulation scope** (raw timing/branch path; loader/stop
  safety). Closing them requires new fault-injection scenarios / new image fixtures and an
  explicit owner grant for new HDL simulation.
- **G5.03** (host receiver study vs UART TX16) remains a separate owner decision and the
  critical path. **G5.05** held-out selection is downstream of G5.04 closure and belongs to
  the owner post-freeze.

## Boundary

No RTL, simulation, fixture, gate, REQ, or held-out selection changed. The frozen
`report.md`, `G5.01 coverage-holes.md`, and all prior evidence are preserved. This note
supersedes nothing; it summarizes the current checker-scope state for disposition.

## Provenance

- Cites: [read-data-endtoend-2026-11-24](read-data-endtoend-2026-11-24/report.md);
  [start-stop-order-2026-11-25](start-stop-order-2026-11-25/report.md);
  [exclusion-classification-2026-11-25](exclusion-classification-2026-11-25.md); [report](report.md).
- Generated: 2026-11-25T08:36:00Z.
