# Dispatch to the module for the planned RMW. Each module defines the same
# function names, so the rest of the tool never branches on which RMW is used.

rmw_load() {
  case "$P_RMW" in
    rmw_zenoh_cpp)      . "$RRV_ROOT/lib/rmw/zenoh.sh" ;;
    rmw_cyclonedds_cpp) . "$RRV_ROOT/lib/rmw/cyclonedds.sh" ;;
    rmw_fastrtps_cpp)   . "$RRV_ROOT/lib/rmw/fastdds.sh" ;;
    *) die "no support module for RMW '$P_RMW'" ;;
  esac
  # Optional hooks: define no-ops when a module does not need them.
  command -v rmw_remote_prepare >/dev/null || rmw_remote_prepare() { :; }
  command -v rmw_local_mounts  >/dev/null || rmw_local_mounts()  { :; }
}

# The address the REMOTE should dial to reach us. Chosen as the local IP on the
# route to the remote, which picks the right interface automatically when
# several exist (LAN, VPN, docker bridges).
detect_self_ip() {
  local ip
  ip=$(ip -4 route get "$TRANSPORT_HOST" 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)
  [ -n "$ip" ] || ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo "$ip"
}
