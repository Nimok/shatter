# Shatter

A distributed DHCPv4 server written in Elixir. Uses Mnesia for replicated lease storage, libcluster for automatic node discovery, and OTP supervision trees for fault isolation. Multiple nodes share a lease database and serve DHCP requests without double-allocating IPs. Designed around Mnesia's replicated coordination model; explicit quorum-based partition handling is planned but not yet implemented.

Built as a reference implementation for learning how BEAM primitives map to distributed systems problems.

## Architecture

```
Shatter.Application
├── Shatter.Cluster          — libcluster node discovery
├── Shatter.Store            — Mnesia abstraction (leases + pools tables)
├── Shatter.NetworkSupervisor
│   └── Shatter.Network.Listener   — UDP socket on port 67
│       └── Shatter.Network.HandlerSupervisor
│           └── (per-request processes)
├── Shatter.LeaseSupervisor
│   └── Shatter.LeaseReaper  — periodic expired-lease reclamation
└── Shatter.APISupervisor
    └── Shatter.API.Router   — HTTP management API (Bandit + Plug)
```

**Core modules:**

- `Shatter.DHCP.Packet` — pure binary ↔ struct parser/serializer for DHCPv4 packets
- `Shatter.DHCP.Options` — DHCP option encoding/decoding
- `Shatter.Lease` — lease struct with state machine (`offered → bound → expired`)
- `Shatter.Pool` — pool struct with IP range enumeration
- `Shatter.Store` — Mnesia layer; all reads and writes go through here
- `Shatter.Allocator` — lease allocation logic: find-or-allocate, MAC reuse, pool exhaustion

## Running

```bash
mix deps.get
mix run --no-halt
```

To form a cluster locally, start additional nodes with different names:

```bash
iex --name a@127.0.0.1 -S mix
iex --name b@127.0.0.1 -S mix
```

## Testing

```bash
mix test
```

Integration tests run against a real single-node Mnesia instance (`:ram_copies` in test env — no disk state between runs).

## Manual DHCP smoke test on macOS

Docker-based DHCP clients are awkward on macOS because Docker Desktop does not expose normal layer-2 networking to containers. For local manual testing, run Shatter on the dev UDP port and use the Elixir smoke client in `scripts/dhcp_smoke.exs`.

Start Shatter:

```bash
iex -S mix
```

Seed a local pool in IEx:

```elixir
Shatter.Store.insert_pool(%Shatter.Pool{
  id: :manual_pool,
  range_start: {10, 0, 0, 100},
  range_end: {10, 0, 0, 110},
  subnet_mask: {255, 255, 255, 0},
  gateway: {10, 0, 0, 1},
  dns_servers: [{1, 1, 1, 1}, {8, 8, 8, 8}],
  lease_duration_seconds: 3600,
  local: true
})
```

In another terminal, run a DHCP DISCOVER -> OFFER -> REQUEST -> ACK exchange against the running server:

```bash
mix run --no-start scripts/dhcp_smoke.exs
```

Useful variants:

```bash
# Reuse the same MAC; should receive the same lease.
mix run --no-start scripts/dhcp_smoke.exs --mac 02:00:00:00:00:01

# Use a different MAC; should receive a different lease while the pool has space.
mix run --no-start scripts/dhcp_smoke.exs --mac 02:00:00:00:00:02

# Print parsed OFFER and ACK packets.
mix run --no-start scripts/dhcp_smoke.exs --verbose
```

The `--no-start` flag is intentional: it loads the project modules for the client script without starting a second Shatter application that would collide with the server already listening on UDP `6767`.

## HTTP API

> **Not yet implemented.** `Shatter.APISupervisor` and `Shatter.API.Router` are part of the supervision tree but the router currently returns 404 for all paths. The planned endpoints are:

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/pools` | Create an IP pool |
| `DELETE` | `/pools/:id` | Delete a pool |
| `GET` | `/pools` | List all pools |
| `GET` | `/leases` | List all active leases |
| `GET` | `/status` | Cluster membership and pool utilization |
