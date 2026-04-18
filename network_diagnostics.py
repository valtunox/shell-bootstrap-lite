#!/usr/bin/env python3
"""
network_diagnostics.py

Purpose:
    Quick network troubleshooting: ping/latency/packet loss to one or more targets,
    interface info, default route, and basic DNS servers listing.

Examples:
    python3 network_diagnostics.py --targets 8.8.8.8,1.1.1.1 --count 5 --json
    python3 network_diagnostics.py --targets example.com --iface
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
from dataclasses import asdict, dataclass
from typing import Dict, List, Optional


RE_WS = re.compile(r"\s+")


def run(cmd: List[str], timeout: int = 15) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, text=True, timeout=timeout)
    except Exception as exc:
        return subprocess.CompletedProcess(cmd, 1, "", str(exc))


@dataclass
class PingResult:
    target: str
    transmitted: Optional[int]
    received: Optional[int]
    loss_percent: Optional[float]
    min_ms: Optional[float]
    avg_ms: Optional[float]
    max_ms: Optional[float]


@dataclass
class IfaceInfo:
    name: str
    state: Optional[str]
    ipv4: List[str]
    ipv6: List[str]


@dataclass
class RouteInfo:
    default_v4: Optional[str]
    default_v6: Optional[str]


def parse_ping_output(out: str, target: str) -> PingResult:
    tx = rx = None
    loss = None
    min_ms = avg_ms = max_ms = None
    # BusyBox and iputils have slightly different formats; handle common cases
    for line in out.splitlines():
        if "packets transmitted" in line:
            m = re.search(r"(\d+) packets transmitted, (\d+) received, (\d+)% packet loss", line)
            if m:
                tx, rx, loss = int(m.group(1)), int(m.group(2)), float(m.group(3))
            else:
                m = re.search(r"transmitted\s*=\s*(\d+),\s*received\s*=\s*(\d+),\s*loss\s*=\s*(\d+)%", line)
                if m:
                    tx, rx, loss = int(m.group(1)), int(m.group(2)), float(m.group(3))
        elif "min/avg/max" in line or "min/avg/max/mdev" in line:
            # rtt min/avg/max/mdev = 14.820/15.008/15.285/0.188 ms
            m = re.search(r"=\s*([\d.]+)/([\d.]+)/([\d.]+)", line)
            if m:
                min_ms, avg_ms, max_ms = float(m.group(1)), float(m.group(2)), float(m.group(3))
    return PingResult(target, tx, rx, loss, min_ms, avg_ms, max_ms)


def ping_target(target: str, count: int = 4, interval: float = 0.2) -> PingResult:
    ping = shutil.which("ping")
    if not ping:
        return PingResult(target, None, None, None, None, None, None)
    cp = run([ping, "-c", str(count), "-i", str(interval), target])
    return parse_ping_output(cp.stdout or cp.stderr, target)


def get_iface_info() -> List[IfaceInfo]:
    ip = shutil.which("ip")
    infos: List[IfaceInfo] = []
    if not ip:
        return infos
    cp = run([ip, "-o", "addr", "show"])
    if cp.returncode != 0:
        return infos
    tmp: Dict[str, IfaceInfo] = {}
    for line in cp.stdout.splitlines():
        # 2: eth0    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0\tvalid_lft forever preferred_lft forever
        cols = RE_WS.split(line.strip())
        if len(cols) < 4:
            continue
        name = cols[1]
        fam = cols[2]
        addr = cols[3]
        info = tmp.get(name) or IfaceInfo(name=name, state=None, ipv4=[], ipv6=[])
        if fam == "inet":
            info.ipv4.append(addr)
        elif fam == "inet6":
            info.ipv6.append(addr)
        tmp[name] = info
    # get link state
    cp2 = run([ip, "-o", "link", "show"])
    if cp2.returncode == 0:
        for line in cp2.stdout.splitlines():
            # 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ... state UP
            m = re.search(r":\s*([^:]+):.*state\s+(\S+)", line)
            if m:
                name, state = m.group(1), m.group(2)
                if name in tmp:
                    tmp[name].state = state
    return list(tmp.values())


def get_routes() -> RouteInfo:
    ip = shutil.which("ip")
    v4 = v6 = None
    if ip:
        cp = run([ip, "route", "show", "default"])
        if cp.returncode == 0 and cp.stdout.strip():
            # default via 172.17.0.1 dev eth0
            m = re.search(r"default\s+via\s+(\S+)", cp.stdout)
            if m:
                v4 = m.group(1)
        cp6 = run([ip, "-6", "route", "show", "default"])
        if cp6.returncode == 0 and cp6.stdout.strip():
            m = re.search(r"default\s+via\s+(\S+)", cp6.stdout)
            if m:
                v6 = m.group(1)
    return RouteInfo(default_v4=v4, default_v6=v6)


def main() -> int:
    ap = argparse.ArgumentParser(description="Network diagnostics: ping, interfaces, routes.")
    ap.add_argument("--targets", help="Comma-separated targets (hostnames or IPs)")
    ap.add_argument("--count", type=int, default=4, help="ICMP echo count per target")
    ap.add_argument("--json", action="store_true", help="Output JSON")
    ap.add_argument("--iface", action="store_true", help="Include interface and route info")
    args = ap.parse_args()

    targets = [t.strip() for t in (args.targets or "8.8.8.8").split(",") if t.strip()]

    results = [asdict(ping_target(t, count=args.count)) for t in targets]
    payload = {"results": results}

    if args.iface:
        payload["interfaces"] = [asdict(i) for i in get_iface_info()]
        r = get_routes()
        payload["routes"] = asdict(r)

    if args.json:
        print(json.dumps(payload, indent=2))
        return 0

    for r in results:
        print(f"Target {r['target']}: tx={r['transmitted']} rx={r['received']} loss%={r['loss_percent']} rtt ms min/avg/max={r['min_ms']}/{r['avg_ms']}/{r['max_ms']}")
    if args.iface:
        print("\nInterfaces:")
        for i in payload.get("interfaces", []):
            print(f"- {i['name']} state={i['state']} ipv4={','.join(i['ipv4'])} ipv6={','.join(i['ipv6'])}")
        print("\nRoutes:")
        print(payload.get("routes", {}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
