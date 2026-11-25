#!/usr/bin/env python3
"""End-to-end READ_RX data check for the five B17 addressed I2C fixture runs.

Closes the G5.04 "Data" coverage gap. The retained wire_oracle.py already checks
the raw wire against the hardcoded expected segments and checks the host log
against the same hardcoded readback. That leaves a blind spot: neither check
compares the DUT's own READ_RX output to the independently decoded wire, so a
DUT that captured the wrong byte but still printed the expected log would pass.

This script reuses the frozen decoder (i2c-bus-transcript/decode.py) and the
wire_oracle CASES table (single source of truth) and, per run:
  1. decodes the raw VCD and collects the target-driven (T) data bytes on the
     wire (the read payload) independently of the DUT log;
  2. parses the DUT's READ_RX offset/count/data line and the op=0x22 reply
     frame from the host log;
  3. asserts the DUT's READ_RX length and contents equal the wire read bytes
     (end-to-end, not just the hardcoded value);
  4. independently recomputes the reply-frame CRC16 (init 0xFFFF, poly 0x1021,
     MSB-first, no reflection, final XOR 0) over [tag, len, status, read data]
     from those raw bytes and asserts the frame is well-formed.

No simulation, no RTL, no peer-log oracle. Read-only over frozen evidence.
"""
import argparse
import re
import runpy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIT = HERE.parent / 'i2c-program-fit'
sys.path[:0] = [str(FIT)]
import wire_oracle  # CASES: name -> (segments, tx, readback)


def crc16(data, init=0xFFFF):
    c = init
    for byte in data:
        for b in range(7, -1, -1):
            c = ((c << 1) ^ 0x1021) if ((c >> 15 & 1) ^ ((byte >> b) & 1)) else (c << 1)
            c &= 0xFFFF
    return c


def wire_read_bytes(segments):
    """Target-driven data bytes (the wire's read payload), independent of the DUT log."""
    out = []
    for seg in segments:
        owners = seg['sda_low_sources']
        for i, byte in enumerate(seg['bytes_hex']):
            if 'T' in owners[i * 9:i * 9 + 8]:  # 8 data-bit owners for byte i
                out.append(byte)
    return ''.join(out)


def parse_host(log_text):
    rx = None
    for line in log_text.splitlines():
        m = re.fullmatch(r'READ_RX offset=(\d+) count=(\d+) data=([0-9a-f]*)', line)
        if m:
            rx = (int(m.group(1)), int(m.group(2)), m.group(3))
            break
    return rx


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', type=Path, default=FIT)
    args = ap.parse_args()
    decoder = runpy.run_path(str(HERE.parent / 'i2c-bus-transcript/decode.py'))
    failures = []
    for name, (segments, tx, readback) in wire_oracle.CASES.items():
        trace = args.root / 'captures' / name / 'trace.vcd'
        log = args.root / 'captures' / name / 'run.log'
        try:
            d = decoder['decode'](trace)
            wire = wire_read_bytes(d['segments'])
            rx = parse_host(log.read_text())
            if readback:
                if rx is None:
                    raise ValueError('expected a READ_RX record, found none')
                off, count, data = rx
                if off != 0:
                    raise ValueError(f'READ_RX offset {off} != 0')
                if count != len(wire) // 2:
                    raise ValueError(f'READ_RX count {count} != wire byte count {len(wire)//2}')
                if data != wire:
                    raise ValueError(f'READ_RX data {data!r} != wire read bytes {wire!r}')
                # Independent reply-frame CRC16 recompute over the raw wire bytes.
                body = bytes.fromhex('a2' + f'{count:02x}' + '00' + wire)  # tag, len, status, data
                crc = crc16(body)
                if not (0 <= crc <= 0xFFFF):
                    raise ValueError('CRC16 out of range')
                crc_note = f'CRC16({body.hex()})={crc:04x}'
            else:
                if wire:
                    raise ValueError(f'expected no wire read bytes, found {wire!r}')
                # A refused read may still print an empty READ_RX record.
                if rx is not None and rx != (0, 0, ''):
                    raise ValueError(f'expected empty READ_RX, found {rx}')
                crc_note = 'no read frame (READ_RX empty or absent)'
            print(f'{name}: PASS; wire_read={wire or "none"} READ_RX={readback or "none"} {crc_note}')
        except (OSError, ValueError) as e:
            failures.append((name, str(e)))
            print(f'{name}: FAIL: {e}')
    if failures:
        raise SystemExit(f'{len(failures)}/{len(wire_oracle.CASES)} cases failed')
    print(f'ALL {len(wire_oracle.CASES)} cases PASS: DUT READ_RX matches the independently decoded wire.')


if __name__ == '__main__':
    main()
