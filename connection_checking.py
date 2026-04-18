#!/usr/bin/env python3
"""
Service Connectivity Test Script
================================
Tests connectivity to containerized services deployed via Terraform.
Auto-detects service name and ports from .env file or environment variables.

Usage:
    python3 python_conn.py

Environment variables (override .env):
    APP_NAME  - Service name (e.g., redis, postgres)
    APP_PORT  - Primary application port
    HTTP_PORT - HTTP/API port
"""

import os
import sys
import json
import socket
import subprocess


def load_env_file(env_path: str) -> dict:
    """Load variables from a .env file."""
    env_vars = {}
    if not os.path.isfile(env_path):
        return env_vars
    with open(env_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, value = line.partition("=")
                env_vars[key.strip()] = value.strip()
    return env_vars


def check_port(host: str, port: int, timeout: float = 3.0) -> dict:
    """Check if a TCP port is open and accepting connections."""
    result = {"host": host, "port": port, "open": False}
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        conn = sock.connect_ex((host, port))
        result["open"] = conn == 0
        sock.close()
    except socket.error as e:
        result["error"] = str(e)
    return result


def check_http(url: str, timeout: float = 5.0) -> dict:
    """Check HTTP endpoint connectivity using curl (no external dependencies)."""
    result = {"url": url, "healthy": False}
    try:
        proc = subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", str(int(timeout)), url],
            capture_output=True, text=True, timeout=timeout + 2
        )
        status_code = int(proc.stdout.strip()) if proc.stdout.strip().isdigit() else 0
        result["status_code"] = status_code
        result["healthy"] = 200 <= status_code < 500
    except FileNotFoundError:
        result["error"] = "curl not available"
    except subprocess.TimeoutExpired:
        result["error"] = "Connection timeout"
    except Exception as e:
        result["error"] = str(e)
    return result


def check_docker_container(app_name: str) -> dict:
    """Check if the Docker container is running."""
    result = {"container": app_name, "running": False}
    try:
        proc = subprocess.run(
            ["docker", "ps", "--filter", f"name={app_name}", "--format", "{{.Names}}|{{.Status}}|{{.Ports}}"],
            capture_output=True, text=True, timeout=10
        )
        if proc.returncode == 0 and proc.stdout.strip():
            lines = proc.stdout.strip().split("\n")
            for line in lines:
                parts = line.split("|")
                result["running"] = True
                result["name"] = parts[0] if len(parts) > 0 else ""
                result["status"] = parts[1] if len(parts) > 1 else ""
                result["ports"] = parts[2] if len(parts) > 2 else ""
                break
        else:
            result["error"] = "Container not found"
    except FileNotFoundError:
        result["error"] = "docker not available"
    except Exception as e:
        result["error"] = str(e)
    return result


def print_section(title: str):
    """Print a section header."""
    print(f"\n{'─' * 50}")
    print(f"  {title}")
    print(f"{'─' * 50}")


def main() -> int:
    """Main entry point."""
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Load config from .env, then allow environment overrides
    env_vars = load_env_file(os.path.join(script_dir, ".env"))

    app_name = os.environ.get("APP_NAME") or os.environ.get("app_name") or env_vars.get("APP_NAME") or env_vars.get("app_name") or "service"
    app_port_str = os.environ.get("APP_PORT") or os.environ.get("app_port") or env_vars.get("APP_PORT") or env_vars.get("app_port") or "0"
    http_port_str = os.environ.get("HTTP_PORT") or os.environ.get("http_port") or env_vars.get("HTTP_PORT") or env_vars.get("http_port") or "0"

    try:
        app_port = int(app_port_str)
    except ValueError:
        app_port = 0

    try:
        http_port = int(http_port_str)
    except ValueError:
        http_port = 0

    host = "localhost"
    all_ok = True
    results = {"service": app_name, "checks": []}

    print("=" * 50)
    print(f"  Connectivity Test: {app_name.upper()}")
    print("=" * 50)

    # 1. Check Docker container
    print_section("Docker Container")
    container_result = check_docker_container(app_name)
    results["checks"].append({"type": "container", **container_result})

    if container_result.get("running"):
        print(f"  [OK]   Container '{container_result.get('name')}' is running")
        print(f"         Status: {container_result.get('status', 'N/A')}")
        print(f"         Ports:  {container_result.get('ports', 'N/A')}")
    else:
        print(f"  [FAIL] Container '{app_name}' is not running")
        if "error" in container_result:
            print(f"         Error: {container_result['error']}")
        all_ok = False

    # 2. Check app port (TCP)
    if app_port > 0:
        print_section(f"App Port ({app_port}/tcp)")
        port_result = check_port(host, app_port)
        results["checks"].append({"type": "app_port", **port_result})

        if port_result["open"]:
            print(f"  [OK]   {host}:{app_port} is accepting connections")
        else:
            print(f"  [FAIL] {host}:{app_port} is not reachable")
            all_ok = False

    # 3. Check HTTP port (TCP + HTTP)
    if http_port > 0 and http_port != app_port:
        print_section(f"HTTP Port ({http_port}/tcp)")
        port_result = check_port(host, http_port)
        results["checks"].append({"type": "http_port", **port_result})

        if port_result["open"]:
            print(f"  [OK]   {host}:{http_port} is accepting connections")
        else:
            print(f"  [FAIL] {host}:{http_port} is not reachable")
            all_ok = False

    # 4. Check HTTP health (try common health endpoints)
    test_port = http_port if http_port > 0 else app_port
    if test_port > 0:
        print_section(f"HTTP Health Check ({test_port})")
        # Try root path first
        http_result = check_http(f"http://{host}:{test_port}/")
        results["checks"].append({"type": "http_health", **http_result})

        if http_result.get("healthy"):
            print(f"  [OK]   HTTP {http_result.get('status_code')} at http://{host}:{test_port}/")
        else:
            print(f"  [WARN] HTTP returned {http_result.get('status_code', 'N/A')} at http://{host}:{test_port}/")
            if "error" in http_result:
                print(f"         {http_result['error']}")

    # Summary
    print(f"\n{'=' * 50}")
    results["healthy"] = all_ok
    if all_ok:
        print(f"  Result: {app_name.upper()} — ALL CHECKS PASSED")
    else:
        print(f"  Result: {app_name.upper()} — SOME CHECKS FAILED")
    print(f"{'=' * 50}")

    # Write results to JSON
    results_path = os.path.join(script_dir, "python_conn_results.json")
    try:
        with open(results_path, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\n  Results saved to: {results_path}")
    except Exception:
        pass

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
