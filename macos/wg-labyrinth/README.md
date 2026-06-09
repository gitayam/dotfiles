# wg-labyrinth

A 3-hop WireGuard chain on macOS where the Mac is the entry hop, with 2 containers (middle, exit) handling the rest. Clean turn-on and turn-off.

This is a reference implementation of every macOS-specific WireGuard-in-containers lesson the [irregularpedia wiki](https://irregularpedia.org/infrastructure/wireguard-in-containers/) and [Geographic Labyrinth fieldnotes](https://fieldnotes.irregulars.io/post/wireguard-geographic-labyrinth-part-2) cover — encoded operationally so you don't rediscover them at 2 AM.

```
Mac (wg-quick + wireguard-go)
   │  utun7  10.0.1.1/24
   ▼ UDP to 192.168.<lan>:51840   (your Mac LAN IP, not 127.0.0.1 — see "Gotchas")
labyrinth-middle (Alpine + wg-quick)
   │  wg0  10.0.2.1/24   eth0  172.30.0.20
   ▼ UDP to 172.30.0.30:51841
labyrinth-exit (Alpine + wg-quick)
   │  wg0  10.0.3.1/24   eth0  172.30.0.30
   ▼ MASQUERADE on eth0 → Docker bridge → Mac's WAN → internet
```

## Quick start

```bash
brew install wireguard-tools             # provides wg, wg-quick, wireguard-go
./labyrinth up                            # build image, render configs, compose up, verify
./labyrinth selectivity destinations      # route only LABYRINTH_SELECTIVE_DESTS via chain
./labyrinth selectivity all               # route ALL Mac traffic via chain (kill-switch)
./labyrinth selectivity off               # back to normal routing (chain still running)
./labyrinth status                        # snapshot
./labyrinth test                          # rerun the 5-step diagnostic recipe
./labyrinth down                          # stop everything, preserve keys/configs
./labyrinth clean                         # also remove state dir + image
```

State (keys, rendered configs) lives in `~/.config/labyrinth/` — outside this dotfiles repo so it stays per-host.

Configure ports, IPs, selectivity defaults in `hops.conf` (sourced by the CLI on every run).

## The lifecycle, in detail

`init` → `up` → `down` (preserves state) → `up` (re-uses keys, same peer pubkeys) → `clean` (removes everything).

`down` is non-destructive: re-running `up` immediately afterwards uses the same keys, so peer pubkeys don't change. `clean` is the only thing that wipes state.

`selectivity` swaps Mac's `AllowedIPs` and bounces the `wg-quick` (brief gap, no sudo). It does NOT touch the containers — they keep handshaking middle↔exit regardless.

## What's encoded that the wiki/fieldnotes get subtly wrong

This script was built by running it and watching things break. Several patterns published in the wiki + fieldnotes don't actually work as written; the script does the corrected version. See the `Gotchas discovered while building this` section below.

## Gotchas discovered while building this

### 1. `\` line continuation in wg-quick configs is silently broken

The wiki and fieldnotes both use this pattern:

```ini
PostUp = sysctl -w net.ipv4.conf.%i.rp_filter=2 ; \
         iptables -A FORWARD -i %i -j ACCEPT ; \
```

`wg-quick` (Alpine 3.21, wireguard-tools v1.0.20210914) reads line-by-line and does NOT join `\`-continued lines. The continuation lines become bogus keys; you get `Line unrecognized: 'iptables-AFORWARD-i%i-jACCEPT;\'` and `wg setconf` aborts. The interface comes up briefly then gets torn down — looks like a "handshake failure" until you read `docker logs`.

**Use multiple `PostUp = ...` lines instead.** Each runs in order.

### 2. `PostUp = sysctl -w net.ipv4.conf.%i.rp_filter=2` fails on Docker Desktop

`/proc/sys` is read-only inside an unprivileged Docker container. Even if you only target `wg0` (which doesn't exist when the compose `sysctls:` block runs), the runtime `sysctl -w` still fails:

```
sysctl: error setting key 'net.ipv4.conf.wg0.rp_filter': Read-only file system
```

**Don't try.** Set `net.ipv4.conf.default.rp_filter=2` in compose `sysctls:`. Newly-created interfaces (including `wg0`) inherit the `.default` value at creation time. The kernel's `MAX(.all, per-interface)` then makes the effective rp_filter `2` (loose) — exactly what you want for asymmetric chain routing.

### 3. `ip route add default ... metric 50` doesn't beat metric 0

The wiki and fieldnotes use `metric 50`:

```
PostUp = ip route add default dev %i metric 50
```

The existing Docker bridge default has metric `0`. Lower metric wins, so this **adds a second default route at metric 50 that is never used**. Traffic still goes out eth0, the chain is bypassed, and you get clean handshakes (control plane is fine) with zero data-plane traffic.

**Use `ip route replace default dev %i`** (no metric). `replace` matches on (destination, table, metric) — with no metric specified, both default to 0 and replace actually replaces the bridge default.

### 4. Middle's `default dev wg0` creates a control-plane routing loop

Once middle's default is `dev wg0`, **wg-quick's own handshake replies** (UDP back to Mac via the Docker bridge) also try to use wg0 → cryptokey routes to exit's catch-all peer → re-encrypted and bounced through the chain. Mac never sees the handshake response. Mac↔middle never establishes.

`wg-quick`'s normal `Table = auto` solves this with fwmark: WireGuard tags its own outbound UDP with a mark, and a routing rule sends marked traffic through the main table (Docker bridge default) and unmarked traffic through a custom table (`default dev wg0`). But `Table = auto` also runs `sysctl -q net.ipv4.conf.all.src_valid_mark=1` against the read-only `/proc/sys`, restart-looping the container — so the wiki tells you to set `Table = off`.

**Set `Table = off` AND replicate the fwmark split manually:**

```
PostUp = wg set %i fwmark 51820
PostUp = ip rule add not fwmark 51820 table 51820
PostUp = ip rule add table main suppress_prefixlength 0
PostUp = ip route add default dev %i table 51820
```

WG-emitted UDP is marked → main table → eth0. Everything else (decapsulated forwarded chain traffic) → custom table → wg0. No loop.

### 5. macOS endpoint cannot be `127.0.0.1`

If Mac's wg config points at `Endpoint = 127.0.0.1:51840` (the obvious choice for a Docker-published port), `wg-quick` on macOS auto-adds a bypass route to keep its own UDP out of the tunnel:

```
route -q -n add -inet 127.0.0.1 -gateway <default-gw>
```

This rewrites loopback semantics for `127.0.0.1` — the Mac tries to send wg's encrypted UDP **out the LAN gateway**, which has no idea what to do with a 127.0.0.1 destination. The packet drops, no handshake, mysterious silence.

**Use the Mac's LAN IP as Endpoint** (e.g., `192.168.23.225:51840`). Bind Docker's published port to the same IP (`ports: ["192.168.23.225:51840:51840/udp"]`) so the port isn't exposed to the whole LAN. The script detects the LAN IP from the default route's interface at render time.

### 6. `selectivity = all` (kill-switch / 0.0.0.0/0) has a macOS limitation

When AllowedIPs = `0.0.0.0/0`, wg-quick adds a bypass route for the endpoint IP. With our Mac-LAN-IP endpoint, that bypass route says "to reach `<mac-lan-ip>`, go via the gateway" — which conflicts with the kernel's "hairpin to my own IP" behavior. Many home routers don't NAT-loopback correctly, so the packet drops.

**`selectivity = destinations` works without this issue** because for narrow AllowedIPs that don't cover the Mac LAN IP, wg-quick doesn't add the bypass route, and traffic to the Mac's own IP hairpins normally via `lo0`.

For true `all`-mode kill-switch on macOS, you need to manually delete the bypass route after `wg-quick up` — that requires `sudo route -n delete -host <mac-lan-ip>`. The script currently does NOT do this automatically; if you need `all` mode, do it manually:

```bash
./labyrinth selectivity all
sudo route -n delete -host "$(route -n get default | awk '/interface:/{print $2}' | xargs ifconfig | awk '/inet / && !/127\./ {print $2; exit}')"
```

### 7. `wg show` on macOS needs sudo

The userspace WireGuard socket at `/var/run/wireguard/<name>.sock` is root-owned. So `wg show labyrinth` from your user shell returns "Unable to access interface: No such file or directory" even when the chain is up. The script detects Mac wg state via `ifconfig` (no sudo) instead. For handshake bytes, run `sudo wg show labyrinth`.

## Diagnostic recipe (what `labyrinth test` does)

5 assertions, each fails loud and prints the offending output. Adapted from the wiki:

1. **Containers running** — `docker compose ps --status running` includes both middle and exit
2. **Recent handshakes** — `wg show wg0 latest-handshakes` on each hop returns a timestamp <180s old
3. **Routing topology**:
   - `3a`: middle's main-table default goes via eth0 (wg control plane intact, no loop)
   - `3b`: middle's table 51820 has `default dev wg0` (chain forwarding active)
4. **In-chain traceroute** — `traceroute` from middle to exit's wg-side IP reaches it in 1 hop
5. **End-to-end** — tcpdump on exit's eth0 captures a SYN sourced from exit's bridge IP (not middle's) while middle curls api.ipify.org. Proves traffic transited both decapsulations.

If `selectivity` is on (Mac in chain), an optional step 6 curls from Mac via the utun and asserts the SYN at exit's eth0 too.

## Performance

wireguard-go (the userspace WireGuard on macOS — kernel has no module) is slow. Expect ~150–250 Mbit single-stream. For a multi-hop chain that's encoding/decoding twice in containers + once on Mac, throughput drops further. Fine for testing, browsing, dev workflows. Not for streaming 4K video.

## Known limitations

- No IPv6 routing (`wg-quick up` tries to add `::/1` and fails on most macOS setups — harmless warning).
- `selectivity = all` requires manual sudo cleanup of one route on macOS (see gotcha #6).
- Mac's `wg show` state requires sudo (gotcha #7).
- LAN IP changes (DHCP renewal, network switch) require re-running `selectivity` to update the Endpoint.

## License / credit

Built standing on the shoulders of:
- [WireGuard](https://www.wireguard.com/) — official docs, especially [Routing & Network Namespace Integration](https://www.wireguard.com/netns/)
- [Pro Custodibus: Multi-Hop WireGuard](https://www.procustodibus.com/blog/2022/06/multi-hop-wireguard/) — the canonical multi-hop pattern
- [DBA1337TECH/OblivionEdge](https://github.com/DBA1337TECH/OblivionEdge) — Blake's upstream router image inspiration
