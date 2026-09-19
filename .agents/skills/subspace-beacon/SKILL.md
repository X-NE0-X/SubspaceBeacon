---
name: subspace-beacon
description: "Use when operating, activating, discovering, connecting to, or diagnosing an authorized Subspace Beacon on Windows, especially across mixed Windows versions, dual-band Wi-Fi, Clash/Mihomo proxies, Tailscale, or a portable USB deployment."
---

# Subspace Beacon

Use this skill whenever the user mentions Beacon, Subspace Beacon, ACTIVATE.cmd, DEACTIVATE.cmd, SCAN-LAN.cmd, ORION-RELAY, LAN discovery, or the portable USB package.

## Operating model

There are two roles:

- The controller keeps the private enrollment key and runs discovery.
- The target runs the Beacon service and receives only the controller public key.

The normal endpoint is TCP 22022, user ORION-RELAY, and state under C:\ProgramData\ORION. The USB package is an offline deployment artifact. It does not require GitHub, DNS, cloud APIs, Tailscale, or Internet access on the target.

The private key must remain on the controller. Never copy it to the USB drive or the target. The USB may contain identity\controller.pub.

## Standard workflow

1. Confirm the target and network are in the user-authorized scope.
2. On the controller, run PREPARE-KEY.cmd once. Verify that the private key exists locally and only the public key was exported.
3. On the target, run ACTIVATE.cmd as administrator and approve UAC. Wait for the service and firewall steps to finish.
4. Verify the target locally with sc query SUBSPACERELAY, sc qc SUBSPACERELAY, netstat -ano, and C:\ProgramData\ORION\endpoint.json.
5. From the controller, run SCAN-LAN.cmd, or use py -3 controller\discover.py --connect.
6. If discovery is ambiguous, first verify addresses and routes. Then use an explicit verified subnet with --subnet; do not guess a subnet from a public IP.
7. For a known target, test TCP 22022 and use direct SSH with the controller key.
8. On failure, use the rollback path and inspect the first underlying error. Exit code 99 is only the wrapper's generic failure.

## Network rules

Same SSID does not prove same LAN. Compare the controller and target IPv4 address, mask, default gateway, and route. A typical working pair is 192.168.31.x/24 with gateway 192.168.31.1. A 169.254.x.x address means DHCP failed.

5 GHz and 2.4 GHz can work together when the router bridges both bands into the same VLAN. Guest SSIDs, client/AP isolation, mesh VLAN policy, different gateways, old Wi-Fi drivers, and unsupported WPA modes can still prevent connection. Use ipconfig /all, route print -4, netsh wlan show interfaces, and netsh wlan show drivers before changing static IP settings.

The Beacon scanner intentionally focuses on physical private-LAN routes. Clash/Mihomo TUN routes, VPN-only routes, and Tailscale routes are not proof of reachability and may be excluded. A public IP is informational and cannot replace a private LAN path.

## Troubleshooting

Read references/troubleshooting.md for the compatibility matrix, exact diagnostics, proxy/Tailscale guidance, stale-state cleanup, ACL failures, and the historical failure modes this skill is intended to prevent.

## Evidence standard

Do not claim that a Beacon is connected from a process listing, a copied file, or a public-IP result. Require a fresh TCP test and an authenticated SSH or controller discovery result. Record the actual target IP, port, service state, route, and account context. Keep interactive-app configuration separate from service-account configuration.

## Cleanup boundary

Treat the USB volume and C:\ProgramData\ORION as exact targets. Before deleting anything, verify the volume label or root sentinel and compare a manifest. Remove only ORION-owned state marked by the Beacon marker. Do not format the USB, delete Windows installation media, or remove an unmarked C:\ProgramData\ORION tree unless the user explicitly expanded the scope.
