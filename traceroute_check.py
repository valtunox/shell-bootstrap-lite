#!/usr/bin/env python3
"""
traceroute_check.py

Purpose:
    Run a traceroute (or tracepath) to a target and return the hop list.

Examples:
    python3 traceroute_check.py --target 8.8.8.8
    python3 traceroute_check.py --target example.com --json
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
from typing import List, Dict

RE_WS = re.compile(r"\s+")


def run(cmd: List[str], timeout: int = 30) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, text=True, timeout=timeout)
    except Exception as exc:
        return subprocess.CompletedProcess(cmd, 1, "", str(exc))


def parse_traceroute(out: str) -> List[Dict]:
    hops: List[Dict] = []
    for line in out.splitlines():
        line = line.strip()
        if not line or line.startswith("traceroute"):
            continue
        # Format: 1  192.168.1.1  1.123 ms
        cols = RE_WS.split(line)
        try:
            hop = int(cols[0])
        except Exception:
            continue
        addr = None
        rtt_ms = None
        # numeric mode usually has addr next
        for tok in cols[1:]:
            if tok.replace(".", "").isdigit() or ":" in tok:
                addr = tok
                break
        m = re.search(r"([\d.]+)\s*ms", line)
        if m:
            try:
                rtt_ms = float(m.group(1))
            except Exception:
                pass
        hops.append({"hop": hop, "address": addr, "rtt_ms": rtt_ms})
    return hops


def parse_tracepath(out: str) -> List[Dict]:
    hops: List[Dict] = []
    for line in out.splitlines():
        line = line.strip()
        if not line or line.startswith(" 1?:") or line.startswith("tracepath"):
            continue
        m = re.match(r"(\d+):\s+([\w\-\.:]+)\s+.*?(\d+\.\d+)\s*ms", line)
        if not m:
            m = re.match(r"(\d+):\s+([\w\-\.:]+)", line)
        if m:
            hop = int(m.group(1))
            addr = m.group(2)
            rtt = float(m.group(3)) if len(m.groups()) >= 3 else None
            hops.append({"hop": hop, "address": addr, "rtt_ms": rtt})
    return hops


def main() -> int:
    ap = argparse.ArgumentParser(description="Traceroute or tracepath to a target")
    ap.add_argument("--target", required=True)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    hops: List[Dict] = []
    if shutil.which("traceroute"):
        cp = run(["traceroute", "-n", "-w", "2", "-q", "1", args.target], timeout=45)
        if cp.returncode == 0:
            hops = parse_traceroute(cp.stdout)
    elif shutil.which("tracepath"):
        cp = run(["tracepath", "-n", args.target], timeout=45)
        if cp.returncode == 0:
            hops = parse_tracepath(cp.stdout)

    payload = {"target": args.target, "hops": hops}

    if args.json:
        print(json.dumps(payload, indent=2))
    else:
        if not hops:
            print("No traceroute output (tool missing or network blocked)")
            return 1
        for h in hops:
            print(f"{h['hop']:>2}  {h['address'] or '*':<20} {'' if h['rtt_ms'] is None else str(h['rtt_ms']) + ' ms'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
