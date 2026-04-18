#!/usr/bin/env python3
"""
dns_http_check.py

Purpose:
    Diagnose DNS resolution and HTTP/HTTPS reachability for a hostname.

Features:
    - DNS A/AAAA/CAA/TXT lookup via `getent` (fallback to socket.getaddrinfo)
    - Shows which resolver is configured (/etc/resolv.conf)
    - Optional HTTP(S) GET using curl if available

Examples:
    python3 dns_http_check.py 
    python3 dns_http_check.py --host api.github.com --json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional


def run(cmd: List[str], timeout: int = 15) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, text=True, timeout=timeout)
    except Exception as exc:
        return subprocess.CompletedProcess(cmd, 1, "", str(exc))


@dataclass
class DNSResult:
    host: str
    a: List[str]
    aaaa: List[str]
    txt: List[str]
    resolvers: List[str]


@dataclass
class HTTPResult:
    scheme: str
    url: str
    status: Optional[int]
    ip: Optional[str]
    time_total_ms: Optional[float]
    error: Optional[str]


def read_resolvers() -> List[str]:
    resolvers: List[str] = []
    try:
        with open("/etc/resolv.conf", "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("nameserver"):
                    parts = line.split()
                    if len(parts) >= 2:
                        resolvers.append(parts[1])
    except Exception:
        pass
    return resolvers


def getent_hosts(name: str) -> List[str]:
    ge = shutil.which("getent")
    ips: List[str] = []
    if ge:
        cp = run([ge, "hosts", name])
        if cp.returncode == 0:
            for line in cp.stdout.splitlines():
                parts = line.split()
                if parts:
                    ip = parts[0]
                    ips.append(ip)
    if not ips:
        # Fallback using socket
        try:
            info = socket.getaddrinfo(name, None)
            for fam, _, _, _, sockaddr in info:
                ip = sockaddr[0]
                if ip not in ips:
                    ips.append(ip)
        except Exception:
            pass
    return ips


def do_dns_query(host: str) -> DNSResult:
    a: List[str] = []
    aaaa: List[str] = []
    for ip in getent_hosts(host):
        if ":" in ip:
            if ip not in aaaa:
                aaaa.append(ip)
        else:
            if ip not in a:
                a.append(ip)
    return DNSResult(host=host, a=a, aaaa=aaaa, txt=[], resolvers=read_resolvers())


def curl_check(scheme: str, host: str) -> HTTPResult:
    curl = shutil.which("curl")
    url = f"{scheme}://{host}"
    if not curl:
        return HTTPResult(scheme=scheme, url=url, status=None, ip=None, time_total_ms=None, error="curl not installed")
    cp = run([curl, "-sS", "-o", "/dev/null", "-w", "%{http_code} %{time_total} %{remote_ip}", url], timeout=25)
    if cp.returncode != 0:
        return HTTPResult(scheme=scheme, url=url, status=None, ip=None, time_total_ms=None, error=cp.stderr.strip() or "curl error")
    parts = cp.stdout.strip().split()
    status = int(parts[0]) if parts and parts[0].isdigit() else None
    time_total_ms = float(parts[1]) * 1000.0 if len(parts) > 1 else None
    ip = parts[2] if len(parts) > 2 else None
    return HTTPResult(scheme=scheme, url=url, status=status, ip=ip, time_total_ms=time_total_ms, error=None)


def main() -> int:
    ap = argparse.ArgumentParser(description="DNS and HTTP reachability diagnostics")
    ap.add_argument("--host", required=True, help="Hostname to check")
    ap.add_argument("--http", action="store_true", help="Test http://HOST with curl if available")
    ap.add_argument("--https", action="store_true", help="Test https://HOST with curl if available")
    ap.add_argument("--json", action="store_true", help="Output JSON")
    args = ap.parse_args()

    dns = do_dns_query(args.host)
    http: List[HTTPResult] = []
    if args.http:
        http.append(curl_check("http", args.host))
    if args.https:
        http.append(curl_check("https", args.host))

    payload = {"dns": asdict(dns), "http": [asdict(h) for h in http]}

    if args.json:
        print(json.dumps(payload, indent=2))
        return 0

    print(f"Resolvers: {', '.join(payload['dns']['resolvers']) or 'unknown'}")
    print(f"A: {', '.join(payload['dns']['a']) or '-'}")
    print(f"AAAA: {', '.join(payload['dns']['aaaa']) or '-'}")
    if http:
        print("HTTP checks:")
        for h in payload["http"]:
            print(f"- {h['scheme'].upper()} {h['url']} -> status={h['status']} ip={h['ip']} time_ms={h['time_total_ms']} err={h['error']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
