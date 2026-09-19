#!/usr/bin/env python3
"""ORION Subspace Beacon Key v1 LAN discovery and optional SSH handoff.

Scans active local IPv4 LAN routes for TCP/22022, verifies endpoints by SSH
key auth, and reads C:\\ProgramData\\ORION\\endpoint.json.

The controller may have VPN, Wintun, WSL, or proxy adapters. The old
implementation selected the source address for a public UDP connection. A
proxy route could therefore make discovery scan a virtual 198.18.0.0/24
instead of the physical LAN. Discovery now reads connected routes and keeps
only interfaces that have a real IPv4 default gateway.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import ipaddress
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_PORT = 22022
DEFAULT_USER = "ORION-RELAY"

_IPV4_TOKEN = re.compile(r"(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])")
_PRIVATE_LAN_RANGES = (
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
)
_NON_LAN_INTERFACE_RANGES = (
    ipaddress.ip_network("0.0.0.0/8"),
    ipaddress.ip_network("100.64.0.0/10"),
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("169.254.0.0/16"),
    ipaddress.ip_network("198.18.0.0/15"),
    ipaddress.ip_network("224.0.0.0/4"),
    ipaddress.ip_network("240.0.0.0/4"),
)


def _is_private_lan(ip: ipaddress.IPv4Address) -> bool:
    return any(ip in network for network in _PRIVATE_LAN_RANGES)


def _is_non_lan_interface(ip: ipaddress.IPv4Address) -> bool:
    return any(ip in network for network in _NON_LAN_INTERFACE_RANGES)


def _route_metric(line: str) -> int:
    fields = line.split()
    if fields and fields[-1].isdigit():
        return int(fields[-1])
    return 2**31 - 1


def _parse_windows_route_table(text: str) -> tuple[list[tuple[ipaddress.IPv4Network, str, int]], set[str]]:
    """Parse numeric rows from ``route print -4`` without localized headers."""
    connected: list[tuple[ipaddress.IPv4Network, str, int]] = []
    default_interfaces: set[str] = set()
    for raw_line in text.splitlines():
        tokens = _IPV4_TOKEN.findall(raw_line)
        if len(tokens) < 3:
            continue
        try:
            destination = ipaddress.ip_address(tokens[0])
            netmask = ipaddress.ip_address(tokens[1])
            interface = ipaddress.ip_address(tokens[-1])
            network = ipaddress.ip_network(f"{destination}/{netmask}", strict=False)
        except ValueError:
            continue

        if destination == ipaddress.IPv4Address("0.0.0.0") and netmask == ipaddress.IPv4Address("0.0.0.0"):
            default_interfaces.add(str(interface))
            continue

        # A connected route has no gateway token, therefore exactly three IP
        # tokens. Host routes and multicast/broadcast routes are not LANs.
        if len(tokens) != 3 or network.prefixlen >= 31:
            continue
        if not _is_private_lan(interface) or _is_non_lan_interface(interface):
            continue
        if interface not in network:
            continue
        connected.append((network, str(interface), _route_metric(raw_line)))

    return connected, default_interfaces


def _windows_connected_networks() -> list[tuple[ipaddress.IPv4Network, str, int]]:
    route_exe = shutil.which("route.exe") or shutil.which("route")
    if not route_exe:
        return []
    try:
        result = subprocess.run(
            [route_exe, "print", "-4"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    connected, default_interfaces = _parse_windows_route_table(result.stdout)
    if default_interfaces:
        selected = [item for item in connected if item[1] in default_interfaces]
        if selected:
            connected = selected
    return connected


def _posix_connected_networks() -> list[tuple[ipaddress.IPv4Network, str, int]]:
    """Best-effort route reader for Unix controllers; Windows is primary."""
    ip_exe = shutil.which("ip")
    if not ip_exe:
        return []
    try:
        result = subprocess.run(
            [ip_exe, "-4", "route", "show", "scope", "link"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return []

    found: list[tuple[ipaddress.IPv4Network, str, int]] = []
    for raw_line in result.stdout.splitlines():
        fields = raw_line.split()
        if not fields or fields[0] == "default" or "src" not in fields:
            continue
        try:
            network = ipaddress.ip_network(fields[0], strict=False)
            interface = ipaddress.ip_address(fields[fields.index("src") + 1])
        except (ValueError, IndexError):
            continue
        if network.version == 4 and _is_private_lan(interface) and not _is_non_lan_interface(interface):
            found.append((network, str(interface), 0))
    return found


def local_lan_networks() -> list[tuple[ipaddress.IPv4Network, str, int]]:
    """Return deduplicated physical/private LAN routes for auto discovery."""
    found = _windows_connected_networks() if os.name == "nt" else _posix_connected_networks()
    unique: dict[tuple[str, str], tuple[ipaddress.IPv4Network, str, int]] = {}
    for network, interface, metric in found:
        unique[(str(network), interface)] = (network, interface, metric)
    return sorted(unique.values(), key=lambda item: (item[2], int(item[0].network_address)))


def default_ipv4() -> str:
    detected = local_lan_networks()
    if detected:
        return detected[0][1]

    # Fallback for controllers without a usable route command.
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("1.1.1.1", 80))
        address = ipaddress.ip_address(s.getsockname()[0])
        if isinstance(address, ipaddress.IPv4Address):
            return str(address)
    finally:
        s.close()
    raise RuntimeError("Unable to determine a controller IPv4 address")


def tcp_open(host: str, port: int, timeout: float) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def ssh_verify(host: str, port: int, user: str, key: Path, timeout: int) -> dict | None:
    ssh = shutil.which("ssh")
    if not ssh:
        raise RuntimeError("ssh executable was not found on the controller")
    with tempfile.NamedTemporaryFile(prefix="orion-known-hosts-", delete=False) as f:
        kh = f.name
    try:
        cmd = [
            ssh,
            "-i", str(key),
            "-p", str(port),
            "-o", "BatchMode=yes",
            "-o", f"ConnectTimeout={timeout}",
            "-o", "StrictHostKeyChecking=no",
            "-o", f"UserKnownHostsFile={kh}",
            "-o", "LogLevel=ERROR",
            f"{user}@{host}",
            r'type C:\ProgramData\ORION\endpoint.json',
        ]
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 3)
        if p.returncode != 0:
            return None
        try:
            data = json.loads(p.stdout.strip())
        except json.JSONDecodeError:
            return None
        if data.get("orion_endpoint") is not True:
            return None
        data["ip"] = host
        return data
    except subprocess.TimeoutExpired:
        return None
    finally:
        try:
            os.unlink(kh)
        except OSError:
            pass


def scan(network: ipaddress.IPv4Network, port: int, workers: int, timeout: float) -> list[str]:
    hosts = [str(h) for h in network.hosts()]
    found: list[str] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        futures = {ex.submit(tcp_open, h, port, timeout): h for h in hosts}
        for fut in concurrent.futures.as_completed(futures):
            h = futures[fut]
            try:
                if fut.result():
                    found.append(h)
            except Exception:
                pass
    return sorted(found, key=lambda x: ipaddress.ip_address(x))


def main() -> int:
    ap = argparse.ArgumentParser(description="Discover ORION Subspace Beacon endpoints on the LAN")
    ap.add_argument(
        "--subnet",
        action="append",
        help="IPv4 CIDR to scan. May be repeated. Default: active physical/private LAN routes",
    )
    ap.add_argument("--key", default=str(Path.home() / ".ssh" / "orion_enrollment_ed25519"), help="Controller private key path")
    ap.add_argument("--user", default=DEFAULT_USER)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--workers", type=int, default=64)
    ap.add_argument("--timeout", type=float, default=0.35, help="TCP connect timeout in seconds")
    ap.add_argument("--ssh-timeout", type=int, default=3)
    ap.add_argument("--connect", action="store_true", help="If exactly one verified endpoint is found, open an interactive SSH session")
    args = ap.parse_args()

    key = Path(args.key).expanduser()
    if not key.exists():
        print(f"Controller private key not found: {key}", file=sys.stderr)
        return 2

    if args.subnet:
        networks = []
        for value in args.subnet:
            network = ipaddress.ip_network(value, strict=False)
            if network.version != 4:
                raise SystemExit("Only IPv4 is supported in v1")
            networks.append(network)
        route_label = "explicit subnet(s)"
    else:
        detected = local_lan_networks()
        networks = [item[0] for item in detected]
        if detected:
            route_label = "automatic physical/private LAN route(s)"
            print("Auto-selected LAN interface(s): " + ", ".join(item[1] for item in detected))
        else:
            ip = default_ipv4()
            networks = [ipaddress.ip_network(f"{ip}/24", strict=False)]
            route_label = "fallback /24"

    deduplicated = sorted(set(networks), key=lambda value: (value.prefixlen, int(value.network_address)))
    print(f"Scanning {route_label}: {', '.join(str(network) for network in deduplicated)} TCP/{args.port} ...")
    candidates_set: set[str] = set()
    for network in deduplicated:
        candidates_set.update(scan(network, args.port, max(1, min(args.workers, 256)), max(0.05, args.timeout)))
    candidates = sorted(candidates_set, key=lambda x: ipaddress.ip_address(x))
    if not candidates:
        print("No TCP candidates found.")
        return 1

    verified: list[dict] = []
    for host in candidates:
        item = ssh_verify(host, args.port, args.user, key, args.ssh_timeout)
        if item:
            verified.append(item)

    if not verified:
        print(f"Found {len(candidates)} TCP candidate(s), but none authenticated as ORION endpoints.")
        return 1

    print(f"Verified {len(verified)} ORION endpoint(s):")
    for i, e in enumerate(verified, 1):
        print(f"[{i}] {e.get('hostname','?')}  {e['ip']}:{e.get('port', args.port)}  id={e.get('device_id','?')}  {e.get('windows','')}")

    if args.connect:
        if len(verified) != 1:
            print("--connect requires exactly one verified endpoint.", file=sys.stderr)
            return 3
        e = verified[0]
        ssh = shutil.which("ssh")
        assert ssh
        os.execvp(ssh, [
            ssh,
            "-i", str(key),
            "-p", str(e.get("port", args.port)),
            "-o", "StrictHostKeyChecking=no",
            "-o", f"UserKnownHostsFile={os.devnull}",
            f"{args.user}@{e['ip']}",
        ])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
