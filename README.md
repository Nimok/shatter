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

## HTTP API

> **Not yet implemented.** `Shatter.APISupervisor` and `Shatter.API.Router` are part of the supervision tree but the router currently returns 404 for all paths. The planned endpoints are:

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/pools` | Create an IP pool |
| `DELETE` | `/pools/:id` | Delete a pool |
| `GET` | `/pools` | List all pools |
| `GET` | `/leases` | List all active leases |
| `GET` | `/status` | Cluster membership and pool utilization |
