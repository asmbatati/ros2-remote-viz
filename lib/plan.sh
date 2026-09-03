# Turns detection results into a concrete plan.

# Preference order when RMW=auto. Zenoh first: it is the only one here that
# routes over unicast TCP by design, so it survives VPNs and subnets where DDS
# multicast discovery silently fails.
RMW_PREFERENCE="rmw_zenoh_cpp rmw_cyclonedds_cpp rmw_fastrtps_cpp"

plan_build() {
  # --- RMW ------------------------------------------------------------------
  if [ "$RMW" = auto ]; then
    # Favour what the remote already uses, if we can also provide it.
    local pref="$RMW_PREFERENCE"
    [ -n "$R_RMW_CUR" ] && pref="$R_RMW_CUR $RMW_PREFERENCE"
    P_RMW=$(first_common "$R_RMWS" "$pref") \
      || die "no usable RMW on the remote. Found: ${R_RMWS:-<none>}"
  else
    case " $R_RMWS " in
      *" $RMW "*) P_RMW="$RMW" ;;
      *) die "RMW '$RMW' is not available in container '$R_CONTAINER'.
Available there: ${R_RMWS:-<none>}" ;;
    esac
  fi

  # --- how to run rviz2 locally --------------------------------------------
  # Cross-distro ROS 2 does not interoperate: message type hashes and, for
  # Zenoh, the wire protocol itself differ between distros. So the local side
  # must run the SAME distro as the remote. Native if we happen to have it with
  # the right RMW, otherwise a container built for that distro.
  local local_rmws_for_distro=""
  case ";$L_RMWS" in
    *";$R_DISTRO:"*)
      local_rmws_for_distro=$(printf '%s' "$L_RMWS" | tr ';' '\n' \
        | sed -n "s/^$R_DISTRO://p" | head -1) ;;
  esac

  P_IMAGE="rrv-rviz:$R_DISTRO"
  if [ -n "$local_rmws_for_distro" ] && \
     case " $local_rmws_for_distro " in *" $P_RMW "*) true ;; *) false ;; esac && \
     [ -x "/opt/ros/$R_DISTRO/bin/rviz2" ]; then
    P_MODE=native
    P_REASON="local ROS $R_DISTRO matches the remote and provides $P_RMW"
  else
    P_MODE=docker
    [ "$L_DOCKER" = yes ] || die "local ROS is '${L_DISTROS:-none}' but the remote runs '$R_DISTRO',
so rviz2 must run in a $R_DISTRO container - and docker is not usable here."
    if [ -n "$L_DISTROS" ] && [ -z "$local_rmws_for_distro" ]; then
      P_REASON="local ROS is '${L_DISTROS% }' but remote is '$R_DISTRO'; distros must match"
    else
      P_REASON="no local ROS $R_DISTRO; running rviz2 in a $R_DISTRO container"
    fi
  fi

  # --- does this RMW need a helper daemon? ---------------------------------
  P_NEEDS_ROUTER=no
  [ "$P_RMW" = rmw_zenoh_cpp ] && P_NEEDS_ROUTER=yes

  P_XHOST="$TRANSPORT_HOST"
}

plan_show() {
  step "Plan"
  info "  rmw           $C_B$P_RMW$C_RST"
  info "  ros distro    $R_DISTRO (both sides)"
  info "  local rviz2   $C_B$P_MODE$C_RST${P_MODE:+  }$C_DIM($P_REASON)$C_RST"
  [ "$P_MODE" = docker ] && info "  image         $P_IMAGE"
  info "  transport to  $P_XHOST"
  info "  router needed $P_NEEDS_ROUTER"
}
