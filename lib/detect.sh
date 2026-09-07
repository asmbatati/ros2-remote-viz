# Probing of the local machine and the remote container.
# Everything here is read-only: detection never changes either side.

# Map librmw_*.so files to RMW implementation names. Only the implementations
# ROS 2 actually ships are considered; the librmw_dds_common* files are support
# libraries, not implementations, so they are filtered out.
_rmw_from_libdir() {
  # shellcheck disable=SC2016
  echo 'for f in "$1"/librmw_*_cpp.so; do
          [ -e "$f" ] || continue
          b=$(basename "$f" .so)
          case "$b" in
            librmw_dds_common*|librmw_fastrtps_shared_cpp) continue ;;
          esac
          echo "${b#lib}"
        done | sort -u | tr "\n" " "'
}

detect_local() {
  step "Local machine"
  L_OS=$(. /etc/os-release 2>/dev/null && echo "${NAME:-linux} ${VERSION_ID:-}")
  L_ARCH=$(uname -m)
  L_DISTROS=$(ls /opt/ros 2>/dev/null | tr '\n' ' ')
  L_DOCKER=no; have_cmd docker && docker info >/dev/null 2>&1 && L_DOCKER=yes
  L_NVIDIA_RT=no
  [ "$L_DOCKER" = yes ] && docker info --format '{{json .Runtimes}}' 2>/dev/null \
    | grep -q '"nvidia"' && L_NVIDIA_RT=yes
  L_GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
  L_DISPLAY="${DISPLAY:-}"
  L_SESSION="${XDG_SESSION_TYPE:-unknown}"

  # RMWs per locally installed distro, so a native (no-container) run can be
  # chosen when the distro happens to match the remote.
  L_RMWS=""
  local d
  for d in $L_DISTROS; do
    local r; r=$(bash -c "$(_rmw_from_libdir)" _ "/opt/ros/$d/lib")
    L_RMWS="$L_RMWS${d}:${r};"
  done

  dim "  os          $L_OS ($L_ARCH)"
  dim "  ros distros ${L_DISTROS:-<none>}"
  dim "  docker      $L_DOCKER (nvidia runtime: $L_NVIDIA_RT)"
  dim "  gpu         ${L_GPU:-<none detected>}"
  dim "  display     ${L_DISPLAY:-<unset>} ($L_SESSION)"
}

# Choose which remote container to use when REMOTE_CONTAINER=auto: prefer the
# only running one; if several are running, the user must name it.
_pick_container() {
  local running; running=$(rsh 'docker ps --format "{{.Names}}"' 2>/dev/null | tr -d '\r')
  local n; n=$(printf '%s\n' "$running" | grep -c . || true)
  case "$n" in
    0) die "no running containers on $REMOTE_SSH. Start yours, then re-run detect." ;;
    1) printf '%s\n' "$running" | grep . ;;
    *) die "several containers are running on $REMOTE_SSH:
$(printf '%s\n' "$running" | sed 's/^/    /')
Set REMOTE_CONTAINER in config/$RRV_PROFILE.env to the one you want." ;;
  esac
}

# The namespace the robot's own topics live under.
#
# rviz plugin packages ship layouts that name topics RELATIVELY -- their launch
# files put rviz2 in the vehicle's namespace and let ROS resolve them. Launch
# the same layout at the root and every display silently subscribes to a topic
# that does not exist. The panels read the same namespace to find their nodes.
#
# Taken as the first path segment that most namespaced topics share. Not all
# of them: a vehicle namespace always sits alongside a handful of strays --
# a node publishing its own status at the root, mavros's /uasN -- and demanding
# unanimity finds nothing on a perfectly ordinary robot.
_detect_namespace() {
  local topics
  topics=$(rsh "docker exec $R_CONTAINER bash -lc \
    'source /opt/ros/$R_DISTRO/setup.bash >/dev/null 2>&1; ros2 topic list 2>/dev/null'" \
    2>/dev/null | tr -d '\r' | grep -E '^/[^/]+/')
  [ -n "$topics" ] || return 0
  local total; total=$(printf '%s\n' "$topics" | grep -c .)
  [ "$total" -ge 5 ] || return 0
  local top n ns
  top=$(printf '%s\n' "$topics" | sed 's:^/\([^/]*\)/.*:\1:' | sort | uniq -c | sort -rn | head -1)
  n=$(printf '%s' "$top" | awk '{print $1}')
  ns=$(printf '%s' "$top" | awk '{print $2}')
  # A clear majority, or it is not a namespace -- just the busiest node.
  [ $((n * 100 / total)) -ge 60 ] || return 0
  printf '/%s\n' "$ns"
}

detect_remote() {
  step "Remote: $REMOTE_SSH"
  rsh_check

  R_OS=$(rsh '. /etc/os-release 2>/dev/null && echo "${NAME:-linux} ${VERSION_ID:-}"' | tr -d '\r')
  R_ARCH=$(rsh 'uname -m' | tr -d '\r')
  R_IPV6=$(rsh 'cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 0' | tr -d '\r')
  R_JETPACK=$(rsh 'head -1 /etc/nv_tegra_release 2>/dev/null' | tr -d '\r')

  if [ "$REMOTE_CONTAINER" = auto ]; then
    R_CONTAINER=$(_pick_container)
  else
    R_CONTAINER="$REMOTE_CONTAINER"
    rsh "docker inspect $R_CONTAINER >/dev/null 2>&1" \
      || die "container '$R_CONTAINER' not found on $REMOTE_SSH"
    rsh "[ \"\$(docker inspect -f '{{.State.Running}}' $R_CONTAINER)\" = true ]" \
      || die "container '$R_CONTAINER' exists but is not running. Start it first."
  fi

  R_NETMODE=$(rsh "docker inspect -f '{{.HostConfig.NetworkMode}}' $R_CONTAINER" | tr -d '\r')
  R_IMAGE=$(rsh "docker inspect -f '{{.Config.Image}}' $R_CONTAINER" | tr -d '\r')
  R_DISTRO=$(rsh "docker exec $R_CONTAINER sh -c 'ls /opt/ros 2>/dev/null | head -1'" | tr -d '\r')
  [ -n "$R_DISTRO" ] || die "no /opt/ros/* inside container '$R_CONTAINER' - is ROS 2 installed there?"

  R_RMWS=$(rsh "docker exec $R_CONTAINER bash -c '$(_rmw_from_libdir)' _ /opt/ros/$R_DISTRO/lib" | tr -d '\r')
  R_RMW_CUR=$(rsh "docker exec $R_CONTAINER bash -lc 'printenv RMW_IMPLEMENTATION'" 2>/dev/null | tr -d '\r')
  R_HAS_RVIZ=no
  rsh "docker exec $R_CONTAINER test -x /opt/ros/$R_DISTRO/bin/rviz2" 2>/dev/null && R_HAS_RVIZ=yes

  R_NS="$(_detect_namespace)"

  dim "  os          $R_OS ($R_ARCH)${R_JETPACK:+ | $R_JETPACK}"
  dim "  container   $R_CONTAINER  [network: $R_NETMODE]"
  dim "  ros distro  $R_DISTRO"
  dim "  rmw avail   ${R_RMWS:-<none>}"
  dim "  rmw current ${R_RMW_CUR:-<unset>}"
  dim "  rviz2       $R_HAS_RVIZ"
  dim "  namespace   ${R_NS:-<none - robot not publishing, or topics are at the root>}"
  [ "$R_IPV6" = 1 ] && dim "  ipv6        disabled (routers must bind 0.0.0.0)"
  [ "$R_NETMODE" = host ] || warn "container network is '$R_NETMODE', not 'host'.
     Cross-machine ROS traffic will not reach it. Restart it with --network host."
}
