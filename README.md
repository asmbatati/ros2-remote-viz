# rrv — run rviz2 locally against ROS 2 in a remote container

Point it at a machine running ROS 2 in Docker (a Jetson, say). It works out what
ROS distro and RMW live on both sides, picks a pairing that can actually talk,
and starts whatever that needs. rviz2 then runs on **your** GPU, with only ROS
topics crossing the network.

```
rrv init                 # write config/default.env
$EDITOR config/default.env   # set REMOTE_SSH
rrv detect               # probe both machines
rrv build                # build the local rviz2 image, if needed
rrv rviz                 # rviz2 on your screen
```

## Why this exists

ROS 2 does not interoperate across distros. Point a Jazzy rviz2 at a Humble
robot and you get silence — no error, just an empty topic list. Two separate
things break:

- **Message type hashes** differ between distros, so DDS drops what it cannot match.
- **`rmw_zenoh`'s wire protocol** changed between Humble's 0.1.x and Jazzy's
  0.2.x. They cannot form a session at all.

And you usually cannot install the robot's distro natively — Humble does not
package for Ubuntu 24.04.

`rrv` resolves this by running rviz2 in a container built for **the remote's**
distro, while keeping the GPU, so you get matching ROS and local rendering.

## Requirements

- SSH key auth to the remote: `ssh-copy-id user@host` (run it in a real
  terminal — it needs a TTY for the password).
- The remote container started with `--network host`. Without it, ROS traffic
  cannot reach the container; `rrv doctor` flags this.
- Docker locally. The NVIDIA container runtime is used automatically if present.

## Commands

| | |
|---|---|
| `rrv detect` | Probe both machines, choose an RMW and a run mode, cache it |
| `rrv plan` | Show what was chosen, and why |
| `rrv build` | Build the local rviz2 image for the remote's ROS distro |
| `rrv up` | Start whatever daemons the chosen RMW needs |
| `rrv rviz` | Launch rviz2 here |
| `rrv run CMD` | Run any ros2 command here, wired to the remote graph |
| `rrv remote CMD` | Run a command in the remote container with matching env |
| `rrv x11` | Fallback: rviz2 inside the remote container, displayed here |
| `rrv doctor` | Connectivity and configuration checks |
| `rrv down` | Stop everything rrv started |

All take an optional profile name; `config/<profile>.env` holds the settings, so
one checkout can drive several robots.

## RMW support

`RMW=auto` picks something both sides have, preferring what the remote already
uses. Pin one with `RMW=` in the profile.

| RMW | How hosts find each other | Daemon |
|---|---|---|
| `rmw_zenoh_cpp` | A router per host, linked by unicast TCP:7447 | yes, `rrv up` starts both |
| `rmw_cyclonedds_cpp` | Unicast peers via inline `CYCLONEDDS_URI` | none |
| `rmw_fastrtps_cpp` | Unicast initial peers via an XML profile | none |

Zenoh is preferred by default because it routes over unicast TCP by design, so
it survives VPNs and routed subnets where DDS multicast discovery quietly fails.

### Off-LAN (ZeroTier, Tailscale)

Set `TRANSPORT_HOST` in the profile to the VPN address. SSH keeps using
`REMOTE_SSH`, so control and data can take different routes:

```
REMOTE_SSH=nvidia@192.168.1.118
TRANSPORT_HOST=10.147.19.118
```

## The X11 fallback

`rrv x11` runs rviz2 inside the remote container and displays it here. Rendering
happens on the remote GPU and is streamed as X protocol, so it is much slower
for pointclouds — prefer `rrv rviz`.

It uses a **reverse tunnel to your X socket rather than `ssh -X`**, because on a
host with IPv6 disabled sshd cannot bind its X11 listener and rejects forwarding
with `X11 forwarding request failed on channel 0`. The tunnel needs no sudo and
no `sshd_config` change on the robot.

## Notes from getting this working

- **Both Zenoh routers are required.** A node connecting straight to the
  *remote* router does establish a transport — the logs even say
  `Successfully connected` — but discovery never propagates and the topic list
  stays empty. Router-to-router is what carries it.
- **Scope `ZENOH_CONFIG_OVERRIDE` to the router process.** Set it on the
  container and every `docker exec` inherits it, so each *node* also tries to
  bind 7447 and dies with `Address already in use` / `failed to initialize rcl`.
- **Routers must bind `0.0.0.0`.** The shipped default is `tcp/[::]:7447`, which
  aborts wherever IPv6 is disabled — common on Jetson.
- **DDS multicast picks up the whole LAN.** During testing, topics from an
  unrelated machine appeared and looked like they came from the robot. If you
  are unsure a topic is really from your target, check with
  `RMW=rmw_zenoh_cpp`, or confirm the publisher's PID inside the container.

## Verified on

| | Local | Remote |
|---|---|---|
| Host | Ubuntu 24.04, RTX 5090 | JetPack 6 (R36.5), Ubuntu 22.04, aarch64 |
| ROS | Jazzy (bypassed; container used) | Humble in `ihunter` |
| RMW | `rmw_zenoh_cpp` 0.1.9, `rmw_fastrtps_cpp` | `rmw_zenoh_cpp` 0.1.8, `rmw_fastrtps_cpp` |

Both Zenoh and Fast DDS were confirmed carrying messages from the container to
rviz2's host, with rviz2 rendering at OpenGL 4.6 on the local GPU. Zenoh 0.1.8
and 0.1.9 interoperate (both negotiate protocol version 9).

See [docs/JETSON_CHANGES.md](docs/JETSON_CHANGES.md) for exactly what this work
put on the robot, and how to remove it.
