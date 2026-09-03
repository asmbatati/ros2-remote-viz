# rmw_fastrtps_cpp
#
# No daemon. Like Cyclone, the two hosts are introduced as unicast initial
# peers via an XML profile, so discovery does not depend on multicast. The
# profile is written to a temp file because Fast DDS only reads XML from a
# path, not inline.

_fast_xml() {
  local peer="$1"
  cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<dds xmlns="http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles">
  <profiles>
    <participant profile_name="rrv" is_default_profile="true">
      <rtps><builtin><initialPeersList>
        <locator><udpv4><address>$peer</address></udpv4></locator>
      </initialPeersList></builtin></rtps>
    </participant>
  </profiles>
</dds>
XML
}

# $1 = peer address, $2 = destination path
fast_write_profile() { _fast_xml "$1" > "$2"; }

rmw_remote_daemon_cmd() { echo ""; }
rmw_remote_daemon_env() { echo ""; }
rmw_local_daemon_cmd()  { echo ""; }
rmw_local_daemon_env()  { echo ""; }

RRV_FAST_LOCAL="${TMPDIR:-/tmp}/rrv-fastdds-local.xml"
RRV_FAST_REMOTE="/tmp/rrv-fastdds-remote.xml"

rmw_local_node_env() {
  fast_write_profile "$P_XHOST" "$RRV_FAST_LOCAL"
  printf 'RMW_IMPLEMENTATION=%s\nROS_DOMAIN_ID=%s\nFASTRTPS_DEFAULT_PROFILES_FILE=%s\n' \
    "$P_RMW" "$ROS_DOMAIN_ID" "$RRV_FAST_LOCAL"
}
rmw_remote_node_env() {
  printf 'RMW_IMPLEMENTATION=%s\nROS_DOMAIN_ID=%s\nFASTRTPS_DEFAULT_PROFILES_FILE=%s\n' \
    "$P_RMW" "$ROS_DOMAIN_ID" "$RRV_FAST_REMOTE"
}
# Fast DDS needs its profile as a real file inside the container.
rmw_remote_prepare() {
  local tmp; tmp=$(mktemp)
  fast_write_profile "$L_TRANSPORT_SELF" "$tmp"
  rsh "cat > $RRV_FAST_REMOTE" < "$tmp"
  rsh "docker cp $RRV_FAST_REMOTE $R_CONTAINER:$RRV_FAST_REMOTE >/dev/null"
  rm -f "$tmp"
}
# In docker mode the profile is written on the host, so the container needs it
# bind-mounted or Fast DDS logs "realpath failed" and silently ignores it.
rmw_local_mounts() { echo "$RRV_FAST_LOCAL"; }
rmw_ports() { echo "7400-7500/udp"; }
