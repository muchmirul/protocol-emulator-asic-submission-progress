#!/usr/bin/env python3
"""G5.04 coverage-misclassification gap: independently assert the I2C START/STOP/
repeated-start (Sr) ORDER and COUNT on the retained B16 bus transcripts.

The retained G5.01 checker parses the host log but does not fully assert the I2C
transaction structure (START/STOP/Sr ordering, count, and segment/byte consistency).
This checker re-decodes each retained trace from the published archive and asserts
the structure invariants directly, then confirms the fresh decode is faithful to the
published transcript. Checker-only; no RTL, simulation, or fixture mutation.
"""
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from zipfile import ZipFile

HERE = Path(__file__).resolve().parent
IBT = HERE.parent / "i2c-bus-transcript"
sys.path.insert(0, str(IBT))
from decode import decode  # frozen decoder (unchanged)

TRANSCRIPTS = IBT / "transcripts.json"
TRACES = IBT / "retained-traces.zip"

# Documented per-fixture event sequences, from i2c-bus-transcript/report.md
# (frozen B16 fixtures; the report records each one's wire structure).
EXPECTED_EVENTS = {
    "s1-i2c100-w16": ["START", "STOP", "START", "STOP"],
    "s2-i2c400-w16": ["START", "STOP", "START", "STOP"],
    "s8-i2c100-r16": ["START", "STOP", "START", "STOP"],
    "s9-i2c400-r16": ["START", "STOP", "START", "STOP"],
    "s3-i2c-nack":   ["START"],
    "s4-i2c-ack":    ["START", "STOP"],
    "s5-i2c-rs":     ["START", "Sr", "STOP"],
}


def invariants(name, d):
    errs = []
    ev = d["events"]
    if not ev or ev[0][2] != "START":
        errs.append(f"{name}: first event is not START ({ev[:1]})")
    if any(e[2] == "unpaired_SDA_rise" for e in ev):
        errs.append(f"{name}: contains unpaired_SDA_rise event")
    # adjacency: START/Sr -> STOP|Sr ; STOP -> START
    for i in range(len(ev) - 1):
        cur, nxt = ev[i][2], ev[i + 1][2]
        if cur in ("START", "Sr") and nxt not in ("STOP", "Sr"):
            errs.append(f"{name}: event {cur} at {ev[i][0]} followed by {nxt} (expected STOP|Sr)")
        if cur == "STOP" and nxt != "START":
            errs.append(f"{name}: STOP at {ev[i][0]} followed by {nxt} (expected START)")
    # segment count == START/Sr count
    n_open = sum(1 for e in ev if e[2] in ("START", "Sr"))
    if len(d["segments"]) != n_open:
        errs.append(f"{name}: {len(d['segments'])} segments != {n_open} START/Sr events")
    # per-segment byte/ninth + sanity
    for i, s in enumerate(d["segments"]):
        if len(s["bytes_hex"]) != len(s["ninth"]):
            errs.append(f"{name}: segment {i} bytes({len(s['bytes_hex'])}) != ninth({len(s['ninth'])})")
        if len(s["sda_low_sources"]) < 9 * len(s["bytes_hex"]):
            errs.append(f"{name}: segment {i} has {len(s['sda_low_sources'])} SCL edges < 9*{len(s['bytes_hex'])}")
    # monotonic times
    times = [e[0] for e in ev]
    if any(b < a for a, b in zip(times, times[1:])):
        errs.append(f"{name}: event times not monotonic")
    # where field
    where = {e[1] for e in ev}
    if not where <= {"run", "exit", "post"}:
        errs.append(f"{name}: unexpected where field {where - {'run','exit','post'}}")
    # one complete RUN window
    rw = d["run_windows_ps"]
    if len(rw) != 1 or rw[0][1] is None:
        errs.append(f"{name}: expected one complete RUN window, got {rw}")
    return errs


def main():
    published = json.loads(TRANSCRIPTS.read_text())
    failures = 0
    with ZipFile(TRACES) as z, tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for name, ref in published.items():
            data = z.read(f"{name}/trace.vcd")
            path = tmp / "t.vcd"
            path.write_bytes(data)
            d = decode(path)
            errs = []
            if d["sha256"] != ref["sha256"]:
                errs.append(f"{name}: fresh decode sha {d['sha256'][:12]} != published {ref['sha256'][:12]}")
            if d["events"] != ref["events"] or d["segments"] != ref["segments"]:
                errs.append(f"{name}: fresh decode differs from published transcript")
            errs += invariants(name, d)
            got = [e[2] for e in d["events"]]
            if got != EXPECTED_EVENTS[name]:
                errs.append(f"{name}: event sequence {got} != documented {EXPECTED_EVENTS[name]}")
            evk = [e[2] for e in d["events"]]
            n_open = sum(1 for e in evk if e in ("START", "Sr"))
            if errs:
                failures += 1
                print(f"{name}: FAIL")
                for e in errs:
                    print("   ", e)
            else:
                print(f"{name}: PASS; events={evk} START/Sr={n_open} segments={len(d['segments'])}")
    if failures:
        print(f"{failures}/{len(published)} transcripts FAILED the START/STOP order/count invariants")
        return 1
    print(f"ALL {len(published)} transcripts PASS: START/STOP/Sr order and count invariants hold.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
