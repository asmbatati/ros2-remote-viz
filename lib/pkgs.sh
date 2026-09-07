# Source packages compiled into the local image.
#
# lib/msgs.sh mirrors interface definitions, which is all "ros2 topic echo" and
# rviz2's built-in displays need. An rviz plugin is a different thing: a panel
# or a display is compiled code that rviz2 dlopen()s at start-up, so a package
# shipping one must be BUILT here, for this machine's architecture. The robot
# has already built it -- for aarch64, on a Jetson -- and that binary cannot be
# copied to an x86 laptop. Only the source can.
#
# Staged packages are also the real definitions rather than a reconstruction,
# so a package staged here supersedes its interface-only mirror in msgs/.

PKGS_DIR() { echo "$RRV_ROOT/pkgs"; }

# Packages staged locally, one directory each.
pkgs_staged() {
  local d p; d="$(PKGS_DIR)"
  [ -d "$d" ] || return 0
  for p in "$d"/*/; do
    [ -f "$p/package.xml" ] && basename "$p"
  done
  return 0
}

# The name a package declares, which need not match its directory.
pkgs_name_of() {
  sed -n 's:.*<name>\([^<]*\)</name>.*:\1:p' "$1/package.xml" 2>/dev/null | head -1
}

# The library each plugin_description.xml declares, as pluginlib will look for
# it: <library path="foo"> means libfoo.so.
pkgs_plugin_libs() {
  sed -n 's:.*<library[[:space:]]\+path="\([^"]*\)".*:\1:p' "$1/plugin_description.xml" 2>/dev/null
}

# Does this directory hold a package that ships rviz plugins?
pkgs_has_rviz_plugin() {
  [ -f "$1/package.xml" ] && [ -f "$1/plugin_description.xml" ] \
    && grep -q 'rviz_common::' "$1/plugin_description.xml" 2>/dev/null
}

# Source trees in the remote container that ship rviz plugins.
#
# A built package installs its plugin_description.xml into share/ but has no
# CMakeLists.txt beside it; requiring both is what separates a source tree --
# the only thing we can rebuild here -- from its install artefacts.
pkgs_remote_candidates() {
  rcontainer_script <<'RSCRIPT' 2>/dev/null | tr -d '\r' | sort -u
find / \( -path /proc -o -path /sys -o -path /dev \) -prune -o \
       -name plugin_description.xml -print 2>/dev/null |
while read -r f; do
  d=$(dirname "$f")
  [ -f "$d/package.xml" ] || continue
  [ -f "$d/CMakeLists.txt" ] || continue
  grep -q 'rviz_common::' "$f" || continue
  n=$(sed -n 's:.*<name>\([^<]*\)</name>.*:\1:p' "$d/package.xml" | head -1)
  [ -n "$n" ] && echo "$n $d"
done
RSCRIPT
}

# Copy one package's source tree out of the remote container.
pkgs_fetch_remote() {
  local pkg="$1" rdir="$2"
  local out; out="$(PKGS_DIR)/$pkg"
  local tmp; tmp="$(PKGS_DIR)/.$pkg.tar"
  mkdir -p "$(PKGS_DIR)"
  # -h dereferences symlinks for the same reason lib/msgs.sh does: a workspace
  # built with colcon --symlink-install has files pointing back into its source
  # tree, and the links alone arrive here broken.
  rsh "docker exec $R_CONTAINER tar chf - -C '$rdir' \
         --exclude=.git --exclude=build --exclude=install --exclude=log ." \
    > "$tmp" 2>/dev/null || true
  if [ ! -s "$tmp" ]; then rm -f "$tmp"; return 1; fi
  rm -rf "$out"; mkdir -p "$out"
  tar xf "$tmp" -C "$out" 2>/dev/null || { rm -f "$tmp"; rm -rf "$out"; return 1; }
  rm -f "$tmp"
  [ -f "$out/package.xml" ] || { rm -rf "$out"; return 1; }
  return 0
}

# Stage from a directory on this machine.
pkgs_fetch_local() {
  local src="$1"
  [ -f "$src/package.xml" ] || die "$src is not a ROS package (no package.xml)"
  local pkg; pkg="$(pkgs_name_of "$src")"
  [ -n "$pkg" ] || die "cannot read a <name> from $src/package.xml"
  local out; out="$(PKGS_DIR)/$pkg"
  mkdir -p "$(PKGS_DIR)"; rm -rf "$out"; mkdir -p "$out"
  tar chf - -C "$src" --exclude=.git --exclude=build --exclude=install --exclude=log . \
    | tar xf - -C "$out"
  echo "$pkg"
}

# An interface-only mirror of a package we now build from source would declare
# the same types twice and colcon would refuse the workspace outright.
pkgs_unshadow_msgs() {
  local p m
  for p in $(pkgs_staged); do
    m="$(MSGS_DIR)/$p"
    if [ -d "$m" ]; then
      warn "removing msgs/$p - pkgs/$p supersedes it with the real definitions"
      rm -rf "$m"
    fi
  done
  return 0
}

# --- build dependencies -----------------------------------------------------
# Every key the staged packages need at build time, minus the ones we build
# ourselves and the ones the base image already carries.
pkgs_dep_keys() {
  local d staged p; d="$(PKGS_DIR)"
  staged="$(pkgs_staged)"
  [ -n "$staged" ] || return 0
  local -a own=()
  for p in $staged; do own+=("$p"); done
  # msgs/ mirrors are built into /opt/rrv_msgs and sourced before this
  # workspace, so they need no apt package either.
  for p in $(cd "$(MSGS_DIR)" 2>/dev/null && ls -d */ 2>/dev/null | tr -d /); do own+=("$p"); done

  local k
  for p in $staged; do
    sed -n 's:.*<\(buildtool_depend\|build_depend\|depend\)>[[:space:]]*\([^< ]*\)[[:space:]]*</.*:\2:p' \
      "$d/$p/package.xml"
  done | sort -u | while read -r k; do
    [ -n "$k" ] || continue
    case "$k" in
      ament_cmake|ament_cmake_*|ament_lint*|rosidl_default_generators|rosidl_default_runtime) continue ;;
    esac
    local o skip=0
    for o in "${own[@]}"; do [ "$k" = "$o" ] && { skip=1; break; }; done
    [ "$skip" = 1 ] || echo "$k"
  done
  return 0
}

# rosdep keys whose apt name is not derivable from the key. Everything else
# resolves as ros-<distro>-<key with dashes>, or as the key itself.
pkgs_apt_candidates() {
  case "$1" in
    eigen)        echo "libeigen3-dev" ;;
    qt5_gui_libs) echo "qtbase5-dev" ;;
    yaml_cpp|yaml-cpp) echo "libyaml-cpp-dev" ;;
    boost)        echo "libboost-all-dev" ;;
    *)            echo "ros-$R_DISTRO-$(echo "$1" | tr '_' '-') $1" ;;
  esac
}

# Resolve every key to an apt package that actually exists, in ONE container:
# apt-get update dominates the cost and doing it per key is unusably slow.
# stdin: keys. stdout: apt package names.
pkgs_apt_resolve() {
  local k spec=""
  while read -r k; do
    [ -n "$k" ] || continue
    spec="$spec$k:$(pkgs_apt_candidates "$k")
"
  done
  [ -n "$spec" ] || return 0
  printf '%s' "$spec" | docker run --rm -i "$P_IMAGE" bash -c '
    apt-get update -qq >/dev/null 2>&1
    while IFS=: read -r key cands; do
      [ -n "$key" ] || continue
      for c in $cands; do
        if apt-cache policy "$c" 2>/dev/null | grep -q "Candidate: [0-9]"; then
          echo "$c"; break
        fi
      done
    done' 2>/dev/null | tr -d '\r' | sort -u
  return 0
}

# The full --build-arg PKG_APT value for the image build. Cached alongside the
# detection cache: it only changes when the staged packages change.
pkgs_apt_list() {
  local staged; staged="$(pkgs_staged)"
  [ -n "$staged" ] || return 0
  local stamp cachef
  stamp="$(cd "$(PKGS_DIR)" && md5sum */package.xml 2>/dev/null | md5sum | cut -d' ' -f1)"
  cachef="$RRV_CACHE/$RRV_PROFILE.pkgapt"
  if [ -f "$cachef" ] && [ "$(head -1 "$cachef")" = "$stamp" ]; then
    tail -n +2 "$cachef"; return 0
  fi
  local list; list="$(pkgs_dep_keys | pkgs_apt_resolve | tr '\n' ' ')"
  mkdir -p "$RRV_CACHE"
  { echo "$stamp"; echo "$list"; } > "$cachef"
  echo "$list"
}

# --- command ----------------------------------------------------------------
pkgs_show_status() {
  local staged; staged="$(pkgs_staged)"
  step "Staged in $(PKGS_DIR)"
  if [ -z "$staged" ]; then
    dim "  (none - run: rrv pkgs sync)"
  else
    local p libs
    for p in $staged; do
      if pkgs_has_rviz_plugin "$(PKGS_DIR)/$p"; then
        libs="$(pkgs_plugin_libs "$(PKGS_DIR)/$p" | tr '\n' ' ')"
        info "  $p  $C_DIM(rviz plugins: ${libs% })$C_RST"
      else
        info "  $p"
      fi
    done
  fi
}

cmd_pkgs() {
  local action="${1:-status}"
  [ $# -gt 0 ] && shift || true

  case "$action" in
    status)
      pkgs_show_status
      echo
      step "Packages with rviz plugins in $R_CONTAINER"
      local cands; cands="$(pkgs_remote_candidates)"
      if [ -z "$cands" ]; then
        dim "  (none found)"
      else
        printf '%s\n' "$cands" | while read -r n d; do
          if [ -d "$(PKGS_DIR)/$n" ]; then info "  $n  $C_DIM(staged)$C_RST"
          else info "  $n  $C_DIM($d - not staged)$C_RST"; fi
        done
        echo; dim "  stage them with: rrv pkgs sync"
      fi
      ;;

    sync)
      step "Looking for rviz plugin packages in $R_CONTAINER"
      local cands; cands="$(pkgs_remote_candidates)"
      [ -n "$cands" ] || die "no source package in $R_CONTAINER ships an rviz plugin.
Nothing to build. If the sources live outside the container, stage them with:
  rrv pkgs add /path/to/package"
      local want="$*"
      local n d got=0
      while read -r n d; do
        [ -n "$n" ] || continue
        if [ -n "$want" ]; then
          printf '%s\n' $want | grep -qx "$n" || continue
        fi
        step "Staging $n"
        dim "  from $R_CONTAINER:$d"
        if pkgs_fetch_remote "$n" "$d"; then
          local nf; nf=$(find "$(PKGS_DIR)/$n" -type f | wc -l)
          ok "  $nf files -> pkgs/$n"
          got=$((got + 1))
        else
          warn "  could not copy $n - skipping"
        fi
      done <<< "$cands"
      [ "$got" -gt 0 ] || die "staged nothing"
      pkgs_unshadow_msgs
      echo; info "Now run: rrv build"
      ;;

    add)
      [ $# -ge 1 ] || die "usage: rrv pkgs add <path-to-package>"
      local src p
      for src in "$@"; do
        [ -d "$src" ] || die "no such directory: $src"
        p="$(pkgs_fetch_local "$(cd "$src" && pwd)")"
        ok "staged $p from $src"
      done
      pkgs_unshadow_msgs
      echo; info "Now run: rrv build"
      ;;

    remove|rm)
      [ $# -ge 1 ] || die "usage: rrv pkgs remove <name>"
      local p
      for p in "$@"; do
        [ -d "$(PKGS_DIR)/$p" ] || die "not staged: $p"
        rm -rf "${PKGS_DIR:?}/$p"
        ok "removed pkgs/$p"
      done
      info "Now run: rrv build"
      ;;

    deps)
      # What the image build will install for these packages.
      step "Build dependencies for the staged packages"
      local l; l="$(pkgs_apt_list)"
      [ -n "$l" ] && info "  $l" || dim "  (none)"
      ;;

    *) die "usage: rrv pkgs [status|sync [name...]|add <path>|remove <name>|deps]" ;;
  esac
}

# --- verification -----------------------------------------------------------
# Everything pluginlib needs to find a plugin when rviz2 starts: the manifest,
# the library the manifest names, and the ament index entry that points
# rviz_common at the manifest. A missing one of the three is invisible until
# you go looking -- the panel is simply absent from rviz2's Panels menu, with
# no error anywhere.
# Prints "OK <pkg> <lib>" or "MISSING <pkg>: <what>" per plugin library.
pkgs_verify_image() {
  local staged; staged="$(pkgs_staged)"
  [ -n "$staged" ] || return 0
  local spec="" p lib
  for p in $staged; do
    pkgs_has_rviz_plugin "$(PKGS_DIR)/$p" || continue
    for lib in $(pkgs_plugin_libs "$(PKGS_DIR)/$p"); do
      spec="$spec$p $lib
"
    done
  done
  [ -n "$spec" ] || return 0
  printf '%s' "$spec" | docker run --rm -i "$P_IMAGE" bash -c '
    idx=/opt/rrv_pkgs/share/ament_index/resource_index/rviz_common__pluginlib__plugin
    while read -r pkg lib; do
      [ -n "$pkg" ] || continue
      miss=""
      [ -f "/opt/rrv_pkgs/share/$pkg/plugin_description.xml" ] || miss="$miss manifest"
      [ -f "/opt/rrv_pkgs/lib/lib$lib.so" ]                    || miss="$miss lib$lib.so"
      [ -f "$idx/$pkg" ]                                       || miss="$miss ament-index"
      if [ -n "$miss" ]; then echo "MISSING $pkg:$miss"; else echo "OK $pkg $lib"; fi
    done' 2>/dev/null | tr -d '\r'
  return 0
}
