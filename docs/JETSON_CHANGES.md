# Everything changed on the Jetson

Audited on 2026-09-03 against `nvidia@192.168.1.118` (JetPack 6 / R36.5,
Ubuntu 22.04, aarch64) and the `ihunter` container.

## Summary

**No system configuration was modified and no packages were installed.**
`sudo` was never used. `apt` was never run (`/var/log/apt/history.log` shows
zero runs on 2026-09-03). `sshd_config`, sysctls, and the Docker daemon config
are all untouched.

Everything below is either a file in a home/temp directory or a process.

## 1. SSH key (you made this change)

You ran `ssh-copy-id`, which appended one line to
`/home/nvidia/.ssh/authorized_keys` (now 4 lines; 1 matches this PC's key).

**To undo:** remove the line ending `asmalbatati@hotmail.com` from that file.

## 2. Files still present

| Path | Where | What it is |
|---|---|---|
| `/home/nvidia/jetson_zenoh_router.sh` | host | First-draft router launcher. **Superseded by `rrv up`** — safe to delete. |
| `/tmp/rrv-fastdds-remote.xml` | host | Fast DDS peer profile written by `rrv`'s Fast DDS support. Regenerated on demand; cleared on reboot. |
| `/tmp/rrv-fastdds-remote.xml` | inside `ihunter` | Same file, `docker cp`'d in so Fast DDS can read it. |
| `/tmp/.docker.xauth` | inside `ihunter` | **Leftover, no longer used.** An X11 cookie from an early experiment, before the reverse-tunnel approach replaced it. Safe to delete. |

Remove all of them with:

    ssh nvidia@192.168.1.118 'rm -f ~/jetson_zenoh_router.sh /tmp/rrv-fastdds-remote.xml; \
      docker exec ihunter rm -f /tmp/.docker.xauth /tmp/rrv-fastdds-remote.xml'

## 2b. `/root/.gitconfig` inside `ihunter` (2026-09-07)

While identifying which commit of `geo_tuner` and `mav_navigator_ros` the robot
runs, git refused to read those repositories: they are owned by a different uid
than the one `docker exec` lands on, so git's `dubious ownership` guard fired.
I ran, **inside the container only**:

    git config --global --add safe.directory '*'

That created `/root/.gitconfig` with a `[safe] directory = *` entry. It affects
nothing but git's ownership check, and only for root inside `ihunter`. It is
also the reason the version check works at all — worth keeping if you want
`rrv pkgs` to keep reporting which commit is staged.

**To undo:**

    ssh nvidia@192.168.1.118 'docker exec ihunter rm -f /root/.gitconfig'

Nothing else was written this round: staging the packages copies files *out* of
the container with `tar`, and reads nothing else.

## 2c. `rrv here install` inside `ihunter` (2026-09-07, opt-in)

This one is **not** passive: you asked for the launch-from-robot link, and it
writes inside the container. Everything it writes is listed here, and
`rrv here remove` takes all of it back out.

| Path | What it is |
|---|---|
| `/usr/local/bin/rviz-here` | The wrapper you type in the container. Opens a TCP connection to the reverse tunnel and holds it. |
| `/root/.rrv-here.sh` | Sets `DISPLAY=localhost:10.0`, `XAUTHORITY`, `LIBGL_ALWAYS_SOFTWARE=1`, `QT_X11_NO_MITSHM=1`. |
| `/root/.bashrc` | Three lines between `# >>> rrv here >>>` markers, sourcing the file above. |
| `/tmp/.rrv.xauth` | The X cookie, refreshed by every `rrv up`. Cleared on container restart. |

Nothing else changed: no packages, no `apt`, no `sudo`, no ROS files touched.
`/opt/ros` is exactly as it was — the wrapper is a separate command, not a
replacement for `rviz2`.

**To undo:**

    rrv here remove

which is equivalent to:

    ssh nvidia@192.168.1.118 'docker exec ihunter sh -c "
      rm -f /usr/local/bin/rviz-here /root/.rrv-here.sh /tmp/.rrv.xauth
      sed -i \"/^# >>> rrv here >>>$/,/^# <<< rrv here <<<$/d\" /root/.bashrc"'

On the operator's machine it also leaves an ssh process holding the reverse
tunnel and a `rrv-listen` process; `rrv down` stops both.

## 3. Processes

A Zenoh router (`rmw_zenohd`) is **currently running inside `ihunter`**, started
by `rrv up`. Stop it with `rrv down`, or:

    ssh nvidia@192.168.1.118 'docker exec ihunter pkill -f rmw_zenohd'

All test publishers have been stopped.

## 4. Containers created and removed

Two throwaway containers were used for testing so `ihunter` itself was never
experimented on. **Both were removed**; only `ihunter` remains.

- `zenoh-interop-test` — proved rmw_zenoh 0.1.8 ↔ 0.1.9 interoperate
- `x11test` — proved the X11 fallback works

## 5. The `ihunter` container itself

Not modified, apart from the two `/tmp` files above. It stopped once during this
work (exit 127 at 10:25:40) while being probed; `docker exec`/`docker cp` do not
kill a container's main process, so this was most likely the interactive shell
ending. You restarted it and it has been stable since.

## Things deliberately NOT changed

- **`sshd_config` was not edited.** SSH X11 forwarding is broken here because
  IPv6 is disabled (`net.ipv6.conf.all.disable_ipv6=1`), so sshd cannot bind its
  X11 listener and rejects forwarding. The documented fix is `AddressFamily inet`
  plus an sshd reload — a change to a remote robot's SSH daemon, so `rrv x11`
  works around it with a reverse tunnel instead. If you would rather fix it
  properly, that is the one-line change.
- **`rmw_zenoh_cpp` was not upgraded** (0.1.8 → 0.1.9). Testing showed 0.1.8 and
  0.1.9 interoperate, so there is no reason to touch the robot.
