# Controller-side use

Default controller private key:

`~/.ssh/orion_enrollment_ed25519`

The private key never goes onto the USB. Run `PREPARE-KEY.cmd` on Windows; it copies only the `.pub` file into `identity/controller.pub`.

Discover on the active physical/private LAN routes. VPN, Wintun, WSL, and
proxy-only routes are excluded from automatic selection:

```bash
python3 controller/discover.py
```

Discover and connect when exactly one endpoint is found:

```bash
python3 controller/discover.py --connect
```

Explicit subnet:

```bash
python3 controller/discover.py --subnet 192.168.50.0/24 --connect
```

Multiple explicit subnets are supported by repeating `--subnet`:

```bash
python3 controller/discover.py --subnet 192.168.50.0/24 --subnet 192.168.60.0/24
```

Direct connection when the IP is already known:

```bash
ssh -i ~/.ssh/orion_enrollment_ed25519 -p 22022 ORION-RELAY@192.168.50.123
```
