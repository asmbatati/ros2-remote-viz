# rrv — run rviz2 locally against ROS 2 in a remote container

Point it at a machine running ROS 2 in Docker (a Jetson, say). It works out what
ROS distro and RMW live on both sides, picks a pairing that can actually talk,
and starts whatever that needs. rviz2 then runs on **your** GPU, with only ROS
topics crossing the network.

```
./bin/rrv install            # put rrv on your PATH, then just use `rrv`
rrv init                     # write config/default.env
$EDITOR config/default.env   # set REMOTE_SSH
rrv detect                   # probe both machines
rrv build                    # build the local rviz2 image, if needed
rrv rviz                     # rviz2 on your screen
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
| `rrv install` | Symlink `rrv` into `~/.local/bin` so it runs from any directory |
| `rrv configs` | List the `.rviz` layouts in `rviz/` |
| `rrv msgs [sync]` | Find message types this machine cannot decode, and fetch them |
| `rrv pkgs [sync]` | Build the robot's rviz plugin packages here, so their panels load |
| `rrv detect` | Probe both machines, choose an RMW and a run mode, cache it |
| `rrv plan` | Show what was chosen, and why |
| `rrv build` | Build the local rviz2 image for the remote's ROS distro |
| `rrv up` | Start whatever daemons the chosen RMW needs |
| `rrv rviz [layout]` | Launch rviz2 here, optionally with a saved layout |
| `rrv shell` | Interactive shell where plain `ros2 ...` hits the remote graph |
| `rrv run CMD` | Run any ros2 command here, wired to the remote graph |
| `rrv shim install` | Make bare `ros2` reach the remote in every shell (opt-in) |
| `rrv remote CMD` | Run a command in the remote container with matching env |
| `rrv x11` | Fallback: rviz2 inside the remote container, displayed here |
| `rrv doctor` | Connectivity and configuration checks |
| `rrv down` | Stop everything rrv started |

Use `-p NAME` to select a profile; `config/<NAME>.env` holds the settings, so one
checkout can drive several robots.

**After editing a profile, re-run `rrv detect`.** `detect` resolves the profile
into a cached plan (which address to dial, which RMW, which container), and the
other commands read that cache. The cache is fingerprinted against the profile
and the machine, so a stale one is refused with the mismatch spelled out rather
than quietly used — which previously meant a checkout pointed at a new robot
kept talking to the old one.

## Using plain `ros2` commands

Three ways, least to most invasive.

**One-off:**

```
rrv run ros2 topic list
```

**A shell where everything just works** — nothing outside it is affected:

```
rrv shell
(rrv:default) $ ros2 topic list
(rrv:default) $ ros2 topic echo /scan
```

**Globally, so bare `ros2` always reaches the robot:**

```
rrv shim install          # writes ~/.local/bin/ros2
hash -r                   # in every terminal that is already open
ros2 topic list           # now shows the remote's topics
rrv shim remove           # undo
```

`hash -r` matters. Bash caches the path of a command the first time it runs one,
per shell. A terminal that ran `ros2` before the shim existed keeps calling your
local `ros2`, which cannot see the remote graph and cannot decode its types — so
you get tracebacks like

```
TypeError: the 'package' argument is required to perform a relative import
```

with `/opt/ros/<your-distro>/bin/ros2` in the traceback. That path is the tell:
the shim was bypassed. `rrv doctor` checks this.

The shim *shadows your local `ros2`* — on a machine with its own ROS install
that affects all your local work too, so it is opt-in. Escape it per command
without uninstalling:

```
RRV_SHIM_BYPASS=1 ros2 topic list     # runs the local ros2
```

### Custom message types

`ros2 topic list` works for any topic, but `ros2 topic echo` and rviz2 need the
message *definitions* locally to deserialise it. `rrv msgs` works out what is
missing and how to get it:

```
rrv msgs                # what the graph publishes that this machine cannot decode
rrv msgs sync           # mirror the robot-only ones into msgs/
rrv build               # compile them into the image
```

By default only topics **publishing right now** are considered. To take every
interface package the container has — so message types from launch files that
are not running (cameras, lidar, gimbal) are covered too:

```
rrv msgs --all          # report
rrv msgs sync --all     # mirror everything missing, then rrv build
```

It splits the missing packages two ways:

- **In apt** — it prints an `EXTRA_APT=` line to paste into your profile, so you
  get the real released definitions.
- **Built only on the robot** — it copies the `.msg`/`.srv`/`.action` files out
  of the remote container into `msgs/<pkg>/`, generates an interface-only
  `package.xml` and `CMakeLists.txt`, and `rrv build` compiles them. A mirror
  produces identical type support, because that depends on the package name and
  the field definitions, not on the rest of the package.

`OVERLAY_WS=/path/to/ws` in the profile is the alternative if you already build
those messages locally. It must be built for **this** machine's architecture —
an arm64 build from the robot will not load on an x86 host.

### Custom rviz plugins

A panel or display plugin is not a message definition — it is **compiled code**
that rviz2 `dlopen()`s at start-up. Mirroring it the way `msgs/` mirrors
interfaces is not possible, and the robot's own build is the wrong architecture
(aarch64 on a Jetson) to copy. It has to be built here, from source.

`rrv pkgs` does that, and finds the packages by itself — it looks for a source
tree in the container whose `plugin_description.xml` declares an
`rviz_common::` class:

```
rrv pkgs                # what ships rviz plugins there, and what is staged here
rrv pkgs sync           # copy their sources into pkgs/
rrv build               # compile them into the image
```

`rrv build` reads the staged `package.xml` files, resolves each dependency to
an apt package that actually exists, and installs those before compiling; you
do not list them anywhere. `rrv pkgs deps` shows what it worked out.

Sources come from the **robot**, not from a local clone, on purpose: the panels
drive the robot's nodes over topics and services, so the two must be the same
version. A clone that has drifted ahead compiles cleanly and then fails at
runtime, which is the hardest kind of failure to read. `rrv pkgs add <path>`
stages a local directory when the sources are not in the container.

A staged package supersedes its interface-only mirror in `msgs/` — it carries
the real definitions — and `rrv build` removes the shadowed mirror for you,
because two packages declaring the same types make colcon reject the workspace.

`rrv doctor` checks each plugin is actually in the image: the manifest, the
library it names, and the ament index entry that points rviz_common at it. A
missing one of the three is otherwise invisible — the panel is simply absent
from rviz2's **Panels** menu, with nothing logged anywhere.

### The namespace rviz2 runs in

Packages that ship rviz panels name the topics in their layouts **relatively**,
because their own launch files put rviz2 in the vehicle's namespace and let ROS
resolve them. Open such a layout at the root and every display subscribes to a
topic that does not exist — and the panels, which read rviz2's namespace to find
the nodes they drive, sit there showing *no data* next to a perfectly healthy
robot.

`rrv detect` works the namespace out from the robot's own topics and `rrv rviz`
runs in it, printing which one it used. Override with `RVIZ_NS` in the profile;
`RVIZ_NS=/` pins rviz2 to the root.

### The ros2 CLI daemon

The `ros2` CLI keeps a daemon on `127.0.0.1:(11511+ROS_DOMAIN_ID)`. rrv's
containers use host networking, so a daemon started by a *different* ROS distro
on this machine answers their calls and breaks them with:

```
ResponseError: unknown tag 'rclpy.type_hash.TypeHash'
```

Topic *listing* still works, so this looks like a missing-message problem when
it is not. rrv stops a foreign-distro daemon automatically before each run, and
`rrv doctor` reports one. The reverse also holds: while rrv containers are
running, your local `ros2` may hit *their* daemon — `RRV_SHIM_BYPASS=1` does not
help there, so stop the containers with `rrv down` first.

## rviz layouts

Drop `.rviz` files into `rviz/` and open one by name:

```
rrv rviz nav          # opens rviz/nav.rviz
rrv rviz              # opens rviz/default.rviz if it exists, else a bare rviz2
rrv rviz ~/other.rviz # a path works too
rrv configs           # list what is in rviz/
```

The folder is mounted read-write at the same path inside the container, so
**Save Config** in rviz2 writes back to `rviz/` and survives the container —
commit the file and the layout travels with the repo.

Packages staged in `pkgs/` almost always ship the layout that docks their own
panels, and those are openable by name too — `rrv configs` lists them under
*Shipped by staged packages*. `rviz/` is searched first, so a copy there
overrides the package's original; `rrv configs` marks which ones are shadowed,
since editing a copy that nothing opens is an easy afternoon to lose.

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
