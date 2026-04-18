#!/usr/bin/env python3
"""
tls_cert_inspector.py

Purpose:
    Inspect a remote TLS certificate for host:port, including subject, issuer,
    SANs, and days until expiry. Uses Python stdlib (ssl, socket), no extra deps.

Examples:
    python3 tls_cert_inspector.py --host example.com --port 443 --json
    python3 tls_cert_inspector.py --host api.github.com --timeout 8

Notes:
    - Verification is disabled to allow inspecting misconfigured/expired certs.
    - SNI is used via server_hostname for proper cert selection.
"""
from __future__ import annotations

import argparse
import json
import socket
import ssl
from datetime import datetime, timezone
from typing import Dict, List, Optional


def fetch_cert(host: str, port: int, timeout: float = 5.0) -> dict:
    ctx = ssl.create_default_context()
    # Disable verification so we can inspect even invalid chains
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection((host, port), timeout=timeout) as sock:
        with ctx.wrap_socket(sock, server_hostname=host) as ssock:
            cert = ssock.getpeercert()
            return cert or {}


def parse_cert(cert: dict) -> Dict:
    subject = ""
    issuer = ""
    san: List[str] = []
    not_before = None
    not_after = None
    # subject and issuer come as tuples of tuples: ((('commonName','example.com'),), ...)
    if cert.get("subject"):
        subject_parts = []
        for rdn in cert["subject"]:
            for k, v in rdn:
                if k.lower() == "commonName".lower():
                    subject_parts.append(v)
        subject = ", ".join(subject_parts) or str(cert.get("subject"))
    if cert.get("issuer"):
        issuer_parts = []
        for rdn in cert["issuer"]:
            for k, v in rdn:
                if k.lower() == "commonName".lower():
                    issuer_parts.append(v)
        issuer = ", ".join(issuer_parts) or str(cert.get("issuer"))
    if cert.get("subjectAltName"):
        for typ, name in cert["subjectAltName"]:
            if typ.lower() == "dns":
                san.append(name)

    # Dates like 'Aug 12 23:59:59 2026 GMT'
    def parse_dt(s: Optional[str]):
        if not s:
            return None
        try:
            return datetime.strptime(s, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
        except Exception:
            return None

    not_before = parse_dt(cert.get("notBefore"))
    not_after = parse_dt(cert.get("notAfter"))

    days_remaining = None
    if not_after:
        delta = not_after - datetime.now(timezone.utc)
        days_remaining = int(delta.total_seconds() // 86400)

    return {
        "subject": subject,
        "issuer": issuer,
        "san": san,
        "not_before": not_before.isoformat() if not_before else None,
        "not_after": not_after.isoformat() if not_after else None,
        "days_remaining": days_remaining,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Inspect remote TLS certificate for host:port")
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, default=443)
    ap.add_argument("--timeout", type=float, default=5.0)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    try:
        raw = fetch_cert(args.host, args.port, timeout=args.timeout)
        info = parse_cert(raw)
        payload = {"host": args.host, "port": args.port, "certificate": info}
        if args.json:
            print(json.dumps(payload, indent=2))
        else:
            print(f"TLS certificate for {args.host}:{args.port}")
            print(f"  Subject: {info['subject']}")
            print(f"  Issuer:  {info['issuer']}")
            if info["san"]:
                print(f"  SANs:    {', '.join(info['san'])}")
            print(f"  NotBefore: {info['not_before']}")
            print(f"  NotAfter:  {info['not_after']}")
            print(f"  Days remaining: {info['days_remaining']}")
        return 0
    except Exception as exc:
        payload = {"host": args.host, "port": args.port, "error": str(exc)}
        if args.json:
            print(json.dumps(payload, indent=2))
        else:
            print(f"Error: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
