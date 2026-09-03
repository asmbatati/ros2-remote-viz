# rmw_zenoh_cpp
#
# Topology: a router on each host, linked by unicast TCP; nodes attach to their
# own local router. Connecting a node straight to the remote router does open a
# transport, but discovery does not propagate through it and topics stay
# invisible -- so both routers are required.

ZENOH_PORT="${ZENOH_PORT:-7447}"

# Bind IPv4 explicitly. The shipped default is tcp/[::]:7447, which aborts with
# an address-family error wherever IPv6 is disabled (common on Jetson).
_zenoh_listen() { echo "listen/endpoints=[\"tcp/0.0.0.0:$ZENOH_PORT\"]"; }

rmw_remote_daemon_cmd() {
  echo "source /opt/ros/$R_DISTRO/setup.bash && exec ros2 run rmw_zenoh_cpp rmw_zenohd"
}
# Scoped to the router process only. Exporting this on the container would make
# every node inherit it and try to bind the router port too, failing with
# "Address already in use" / "failed to initialize rcl".
rmw_remote_daemon_env() {
  echo "-e RMW_IMPLEMENTATION=$P_RMW -e ZENOH_CONFIG_OVERRIDE=$(printf '%q' "$(_zenoh_listen)")"
}

rmw_local_daemon_cmd() {
  echo "source /opt/ros/$R_DISTRO/setup.bash && exec ros2 run rmw_zenoh_cpp rmw_zenohd"
}
rmw_local_daemon_env() {
  printf 'RMW_IMPLEMENTATION=%s\nZENOH_CONFIG_OVERRIDE=%s\n' \
    "$P_RMW" "$(_zenoh_listen);connect/endpoints=[\"tcp/$P_XHOST:$ZENOH_PORT\"]"
}

# Nodes talk to the local router (its default localhost endpoint). 0 = wait for
# it forever instead of exiting if it has not come up yet.
rmw_local_node_env() {
  printf 'RMW_IMPLEMENTATION=%s\nZENOH_ROUTER_CHECK_ATTEMPTS=0\n' "$P_RMW"
}
rmw_remote_node_env() { printf 'RMW_IMPLEMENTATION=%s\n' "$P_RMW"; }
rmw_ports() { echo "$ZENOH_PORT"; }
