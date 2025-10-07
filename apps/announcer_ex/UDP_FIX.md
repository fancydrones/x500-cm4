# XMAVLink UDP Socket Binding Fix

## Problem

The announcer-ex application was failing to connect to the router service with the error:

```
Could not open udpout:10.43.59.107:14560: {:error, :eaddrnotavail}. Retrying in 1 second
```

## Root Cause

This is a bug in the XMAVLink library (version 0.4.3) in the `XMAVLink.UDPOutConnection` module.

The problematic code is in `deps/xmavlink/lib/mavlink/udp_out_connection.ex` line 65:

```elixir
case :gen_udp.open(0, [:binary, ip: address, active: true]) do
```

The `ip: address` option tells Erlang's `:gen_udp.open/2` to **bind** the local socket to the specified IP address. However, `address` contains the **remote** router service IP (resolved from the DNS hostname), not a local IP.

When running in Kubernetes:
1. The hostname `router-service.rpiuav.svc.cluster.local` resolves to the ClusterIP `10.43.59.107`
2. XMAVLink tries to bind the UDP socket to `10.43.59.107` 
3. This fails with `:eaddrnotavail` because the pod's network interface doesn't have that IP address

For UDP client (outbound) connections, the socket should bind to `0.0.0.0` (any local interface), not the remote destination IP.

## Solution

Created a patched version of `XMAVLink.UDPOutConnection` that removes the incorrect `ip: address` option:

**File**: `lib/announcer_ex/udp_out_connection_patch.ex`

The key change in the `connect/2` function:

```elixir
# BEFORE (broken):
case :gen_udp.open(0, [:binary, ip: address, active: true]) do

# AFTER (fixed):
case :gen_udp.open(0, [:binary, active: true]) do
```

By naming our patched module `XMAVLink.UDPOutConnection` (same as the dependency), Elixir's module system will use our version instead of the one from the xmavlink package. This is because modules in `lib/` are compiled after dependencies.

## Testing

The fix has been tested locally with `mix compile` and `mix test`. You'll see a warning:

```
warning: redefining module XMAVLink.UDPOutConnection
```

This is expected and confirms our patch is working.

## Deployment

After rebuilding the Docker image with this fix, the application should successfully connect to the router service without the `:eaddrnotavail` errors.

## Long-term Solution

Consider:
1. **Report the bug upstream**: File an issue with the xmavlink project
2. **Fork and fix**: Create a fork of xmavlink with the fix and use it as a git dependency
3. **Wait for upstream fix**: Check if newer versions of xmavlink have fixed this issue

For now, the in-tree patch is the quickest solution.
