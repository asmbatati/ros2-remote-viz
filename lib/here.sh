# Launching from the robot, displaying on this machine.
#
# Two ways round, both driven from a shell inside the remote container, both
# carried by one persistent reverse-tunnelled ssh connection that `rrv up`
# maintains:
#
#   rviz-here <layout>   rviz2 runs HERE, on this machine's GPU. The robot only
#                        sends the request. This is the fast path -- the same
#                        one `rrv rviz` uses -- and the only one worth pointing
#                        at a camera or a lidar.
#
#   rviz2 / ros2 launch  rviz2 runs on the ROBOT and draws on this screen over
#                        X11. Nothing needs to know about rrv, so an unmodified
#                        launch file works, but a remote X display gets no
#                        direct rendering: Mesa falls back to its software
#                        rasteriser on the Jetson's CPU and ships whole frames
#                        over the network. Fine for a grid and a few paths.
#
# The container side is opt-in (`rrv here install`) because it writes two files
# in the container; `rrv here remove` takes them back out.

HERE_CTL_PORT_DEFAULT=7910
HERE_X11_PORT_DEFAULT=6010

here_ctl_port() { echo "${HERE_CTL_PORT:-$HERE_CTL_PORT_DEFAULT}"; }
here_x11_port() { echo "${HERE_X11_PORT:-$HERE_X11_PORT_DEFAULT}"; }
# X clients name the display by number, not by port: 6010 is :10.
here_display() { echo "localhost:$(( $(here_x11_port) - 6000 )).0"; }

here_tunnel_pidfile()   { echo "$RRV_CACHE/$RRV_PROFILE.tunnel.pid"; }
here_listener_pidfile() { echo "$RRV_CACHE/$RRV_PROFILE.listen.pid"; }

# Paths written inside the container.
HERE_WRAPPER=/usr/local/bin/rviz-here
HERE_ENV=/root/.rrv-here.sh
HERE_COOKIE=/tmp/.rrv.xauth
HERE_RC_BEGIN="# >>> rrv here >>>"
HERE_RC_END="# <<< rrv here <<<"

# --- process tracking -------------------------------------------------------
# A pid file alone is not proof: pids get reused. Check the command line still
# looks like the process we started.
_here_alive() {
  local pidfile="$1" want="$2" pid
  [ -f "$pidfile" ] || return 1
  pid="$(cat "$pidfile" 2>/dev/null)" || return 1
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q -- "$want" || return 1
  echo "$pid"
}
_here_stop() {
  local pidfile="$1" want="$2" pid
  pid="$(_here_alive "$pidfile" "$want")" || { rm -f "$pidfile"; return 1; }
  kill "$pid" 2>/dev/null || true
  rm -f "$pidfile"
  echo "$pid"
}

here_tunnel_pid()   { _here_alive "$(here_tunnel_pidfile)"   "-R $(here_ctl_port):"; }
here_listener_pid() { _here_alive "$(here_listener_pidfile)" "rrv-listen"; }

# --- container side ---------------------------------------------------------
here_container_installed() {
  rsh "docker exec $R_CONTAINER test -x $HERE_WRAPPER" 2>/dev/null
}

# Written through stdin rather than a quoted command line: these files contain
# quotes, $ and tabs, and pushing them through ssh + docker exec + sh as an
# argument is how this kind of helper gets silently corrupted.
_here_write_wrapper() {
  local port; port="$(here_ctl_port)"
  rsh_in "docker exec -i $R_CONTAINER sh -c 'cat > $HERE_WRAPPER && chmod 755 $HERE_WRAPPER'" <<WRAPEOF
#!/usr/bin/env bash
# Open an rviz2 window on the operator's station instead of here.
#
# Written by "rrv here install" on the operator's machine; remove it with
# "rrv here remove". Needs the reverse tunnel that "rrv up" maintains.
#
#   rviz-here                 the operator's default layout
#   rviz-here geo_field       a layout by name, resolved on their machine first
#   rviz-here /abs/path.rviz  a layout from THIS container, copied across
#
# The connection is held open on purpose: closing it (Ctrl-C, or the launch
# file exiting) closes the window over there.
port="\${RRV_HERE_PORT:-$port}"

tab=\$(printf '\t')
req=""
for a in "\$@"; do
  req="\$req\$a\$tab"
done

if ! exec 3<>/dev/tcp/127.0.0.1/"\$port"; then
  echo "rviz-here: nothing is listening on 127.0.0.1:\$port" >&2
  echo "  The operator's machine opens that tunnel with: rrv up" >&2
  exit 1
fi
printf '%s\n' "\$req" >&3

# Closing this connection is what closes the window over there, so every way
# out of here has to close it. The reader runs in the background and holds its
# own copy of the socket: signalling this script alone would leave that copy
# open, and the window would outlive the command that asked for it.
pump=""
cleanup() {
  [ -n "\$pump" ] && kill "\$pump" 2>/dev/null
  exec 3<&- 2>/dev/null
  exit 130
}
trap cleanup INT TERM HUP
# Stream their progress back here, and block until the window closes.
cat <&3 &
pump=\$!
wait "\$pump"
WRAPEOF
}

_here_write_env() {
  local disp; disp="$(here_display)"
  rsh_in "docker exec -i $R_CONTAINER sh -c 'cat > $HERE_ENV'" <<ENVEOF
# Point X clients in this container at the operator's screen.
# Written by "rrv here install"; removed by "rrv here remove".
export DISPLAY=$disp
export XAUTHORITY=$HERE_COOKIE
# A remote X display gets no direct rendering, and the Tegra GL stack will not
# quietly fall back. Ask for Mesa's software rasteriser explicitly, so this is
# slow rather than a GL error nobody can read.
export LIBGL_ALWAYS_SOFTWARE=1
# Shared-memory pixmaps cannot cross a tunnel.
export QT_X11_NO_MITSHM=1
ENVEOF
}

_here_write_rc() {
  rsh_in "docker exec -i $R_CONTAINER sh -c 'cat >> /root/.bashrc'" <<RCEOF
$HERE_RC_BEGIN
[ -f $HERE_ENV ] && . $HERE_ENV
$HERE_RC_END
RCEOF
}

here_rc_present() {
  rsh "docker exec $R_CONTAINER grep -qF '$HERE_RC_BEGIN' /root/.bashrc" 2>/dev/null
}

here_install_container() {
  _here_write_wrapper
  _here_write_env
  here_rc_present || _here_write_rc
  return 0
}

here_remove_container() {
  # sed the marked block out rather than truncating: the file is the user's.
  rsh "docker exec $R_CONTAINER sh -c '
    rm -f $HERE_WRAPPER $HERE_ENV $HERE_COOKIE
    if [ -f /root/.bashrc ]; then
      sed -i \"/^# >>> rrv here >>>\$/,/^# <<< rrv here <<<\$/d\" /root/.bashrc
    fi'" 2>/dev/null || true
  return 0
}

# --- X11 cookie -------------------------------------------------------------
# Refreshed on every `rrv up`: an X cookie belongs to one X session, and a stale
# one fails as "cannot open display", which reads like a tunnel fault.
here_push_cookie() {
  [ -n "${DISPLAY:-}" ] || return 0
  local cookie; cookie="$(mktemp)"
  # Wildcard the address family: the container's hostname is not this one's.
  xauth nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' \
    | xauth -f "$cookie" nmerge - 2>/dev/null || true
  if [ ! -s "$cookie" ]; then rm -f "$cookie"; return 1; fi
  scp -q -o ControlPath="$(ssh_ctl_path)" "$cookie" "$REMOTE_SSH:/tmp/.rrv.xauth" 2>/dev/null \
    && rsh "docker cp /tmp/.rrv.xauth $R_CONTAINER:$HERE_COOKIE >/dev/null 2>&1" 2>/dev/null
  local rc=$?
  rm -f "$cookie"
  return $rc
}

# --- tunnel and listener ----------------------------------------------------
here_tunnel_up() {
  here_tunnel_pid >/dev/null && return 0
  local ctl x11 sock dnum
  ctl="$(here_ctl_port)"; x11="$(here_x11_port)"
  local -a fwd=(-R "$ctl:127.0.0.1:$ctl")

  # The X11 leg is optional: without a local display there is nothing to
  # forward, and the control channel is still worth having.
  if [ -n "${DISPLAY:-}" ]; then
    dnum="${DISPLAY#*:}"; dnum="${dnum%%.*}"
    sock="/tmp/.X11-unix/X${dnum}"
    if [ -S "$sock" ]; then
      fwd+=(-R "$x11:$sock")
    else
      warn "no X socket at $sock - forwarding the control channel only"
    fi
  fi

  # ControlPath=none: this connection must outlive the multiplexed one that the
  # rest of rrv shares, which ControlPersist tears down 60s after the last use.
  # ExitOnForwardFailure: a tunnel that silently did not bind is worse than one
  # that refused to start.
  local log; log="$RRV_CACHE/$RRV_PROFILE.tunnel.log"
  mkdir -p "$RRV_CACHE"
  nohup ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes \
      -o ControlMaster=no -o ControlPath=none \
      -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
      "${fwd[@]}" "$REMOTE_SSH" > "$log" 2>&1 &
  local pid=$!
  echo "$pid" > "$(here_tunnel_pidfile)"
  # Give it long enough to fail on a port already in use.
  local i
  for i in 1 2 3 4 5 6; do
    kill -0 "$pid" 2>/dev/null || break
    here_tunnel_pid >/dev/null && return 0
    sleep 0.5
  done
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$(here_tunnel_pidfile)"
    warn "the reverse tunnel would not start:
$(sed 's/^/     /' "$log" 2>/dev/null | head -5)
     A stale one on the robot usually clears with: rrv down"
    return 1
  fi
  return 0
}

here_listener_up() {
  here_listener_pid >/dev/null && return 0
  local log; log="$RRV_CACHE/$RRV_PROFILE.listen.log"
  mkdir -p "$RRV_CACHE"
  RRV_PROFILE="$RRV_PROFILE" RRV_BIN="$RRV_ROOT/bin/rrv" \
    nohup python3 "$RRV_ROOT/bin/rrv-listen" "$(here_ctl_port)" > "$log" 2>&1 &
  local pid=$!
  echo "$pid" > "$(here_listener_pidfile)"
  sleep 0.5
  here_listener_pid >/dev/null && return 0
  rm -f "$(here_listener_pidfile)"
  warn "the request listener would not start:
$(sed 's/^/     /' "$log" 2>/dev/null | head -5)"
  return 1
}

# Called from cmd_up. Silent no-op unless the container side is installed.
here_up() {
  # cmd_rviz calls cmd_up, and the listener reaches cmd_rviz through here_open:
  # without this the link would re-check and re-push its cookie on every window.
  [ -n "${RRV_IN_HERE_OPEN:-}" ] && return 0
  here_container_installed || return 0
  step "Bringing up the launch-from-robot link"
  here_listener_up || return 0
  here_tunnel_up   || return 0
  # The wrapper and env file live in the container's own filesystem, so a
  # recreated container loses them. Cheap to check, and it means
  # `jetson-containers run` does not quietly break the link.
  here_rc_present || _here_write_rc
  if here_push_cookie; then
    ok "rviz-here, and rviz2 on $(here_display), reach this screen"
  else
    ok "rviz-here reaches this screen"
    warn "could not refresh the X cookie - 'rviz2' in the container will not
     display here, but 'rviz-here' still works"
  fi
  return 0
}

here_down() {
  local pid
  pid="$(_here_stop "$(here_tunnel_pidfile)" "-R $(here_ctl_port):")" \
    && dim "  stopped the reverse tunnel (pid $pid)" || true
  pid="$(_here_stop "$(here_listener_pidfile)" "rrv-listen")" \
    && dim "  stopped the request listener (pid $pid)" || true
  return 0
}

# --- open (called by the listener) -----------------------------------------
# Resolve what the robot asked for into a layout on this machine, then hand it
# to the ordinary rviz path.
here_open() {
  export RRV_IN_HERE_OPEN=1
  local ns="" want=""
  local -a rest=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --ns) [ $# -ge 2 ] || die "--ns needs a namespace"; ns="$2"; shift 2 ;;
      --ns=*) ns="${1#*=}"; shift ;;
      -*) rest+=("$1"); shift ;;
      *) if [ -z "$want" ]; then want="$1"; else rest+=("$1"); fi; shift ;;
    esac
  done
  [ -n "$ns" ] && export RRV_NS_OVERRIDE="$ns"

  local cfg=""
  if [ -n "$want" ]; then
    # Prefer a layout on this machine: rviz/ holds the copies with the fixes
    # for this robot, and the robot's original would undo them.
    cfg="$(here_resolve_local "$want")" || true
    if [ -z "$cfg" ]; then
      case "$want" in
        /*) cfg="$(here_fetch_layout "$want")" \
              || die "no layout '$want' here, and it is not in $R_CONTAINER either" ;;
        *)  die "no layout '$want' here, and only an absolute path can be fetched
from the robot. Available: $(list_configs | tr '\n' ' ')" ;;
      esac
    fi
  fi
  cmd_rviz "$RRV_PROFILE" ${cfg:+"$cfg"} "${rest[@]}"
}

# resolve_config without its die: here we want to fall through to the robot.
here_resolve_local() {
  local name="$1" d; d="$(RVIZ_DIR)"
  local c
  for c in "$d/$name" "$d/$name.rviz" "$name"; do
    [ -f "$c" ] && { readlink -f "$c"; return 0; }
  done
  local n path
  while read -r n path; do
    [ "$n" = "${name%.rviz}" ] && { readlink -f "$path"; return 0; }
  done < <(list_pkg_configs)
  return 1
}

# Copy a layout out of the container so rviz2 here can read it.
here_fetch_layout() {
  local rpath="$1"
  local out="$RRV_CACHE/robot-layouts"
  mkdir -p "$out"
  local dest="$out/$(basename "$rpath")"
  rsh "docker exec $R_CONTAINER cat '$rpath'" > "$dest.part" 2>/dev/null || true
  if [ ! -s "$dest.part" ]; then rm -f "$dest.part"; return 1; fi
  mv "$dest.part" "$dest"
  echo "$dest"
}

# --- command ----------------------------------------------------------------
cmd_here() {
  local action="${1:-status}"
  [ $# -gt 0 ] && shift || true
  case "$action" in
    install)
      step "Installing the container side in $R_CONTAINER"
      here_install_container
      ok "  $HERE_WRAPPER   (type 'rviz-here' there)"
      ok "  $HERE_ENV  (sourced from /root/.bashrc)"
      echo
      info "Now run: rrv up
Then, in a NEW shell inside the container:
  rviz-here geo_field        opens here, rendered by this machine's GPU
  rviz2                      runs there, drawn here over X11 (slower)
Remove both files again with: rrv here remove"
      ;;
    remove)
      step "Removing the container side from $R_CONTAINER"
      here_remove_container
      here_down
      ok "removed"
      ;;
    status)
      step "Launch-from-robot link"
      here_container_installed \
        && ok "container side installed in $R_CONTAINER" \
        || { info "  not installed - run: rrv here install"; return 0; }
      here_rc_present && ok "/root/.bashrc sources $HERE_ENV" \
                      || warn "/root/.bashrc does not source $HERE_ENV (rrv up restores it)"
      local pid
      pid="$(here_listener_pid)" && ok "request listener running (pid $pid, port $(here_ctl_port))" \
                                 || warn "no request listener - run: rrv up"
      pid="$(here_tunnel_pid)" && ok "reverse tunnel running (pid $pid)" \
                              || warn "no reverse tunnel - run: rrv up"
      dim "  X display there   $(here_display)"
      ;;
    open) here_open "$@" ;;
    *) die "usage: rrv here [install|remove|status]" ;;
  esac
}
