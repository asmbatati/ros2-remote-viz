# rmw_cyclonedds_cpp
#
# No daemon. Discovery is peer-to-peer, so the two hosts are introduced by
# listing each other as unicast peers. Multicast is left enabled for same-LAN
# convenience but is never relied upon -- it does not survive most VPNs.

_cyclone_uri() {
  local peer="$1"
  cat <<XML
<CycloneDDS><Domain><General><AllowMulticast>default</AllowMulticast></General>
<Discovery><ParticipantIndex>auto</ParticipantIndex>
<Peers><Peer address="$peer"/></Peers></Discovery></Domain></CycloneDDS>
XML
}
# Passed inline as a URI rather than a file so nothing has to be installed on
# the remote; Cyclone accepts raw XML in CYCLONEDDS_URI.
_cyclone_inline() { _cyclone_uri "$1" | tr -d '\n'; }

rmw_remote_daemon_cmd() { echo ""; }   # none needed
rmw_remote_daemon_env() { echo ""; }
rmw_local_daemon_cmd()  { echo ""; }
rmw_local_daemon_env()  { echo ""; }

rmw_local_node_env() {
  printf 'RMW_IMPLEMENTATION=%s\nROS_DOMAIN_ID=%s\nCYCLONEDDS_URI=%s\n' \
    "$P_RMW" "$ROS_DOMAIN_ID" "$(_cyclone_inline "$P_XHOST")"
}
rmw_remote_node_env() {
  printf 'RMW_IMPLEMENTATION=%s\nROS_DOMAIN_ID=%s\nCYCLONEDDS_URI=%s\n' \
    "$P_RMW" "$ROS_DOMAIN_ID" "$(_cyclone_inline "$L_TRANSPORT_SELF")"
}
rmw_ports() { echo "7400-7500/udp"; }
