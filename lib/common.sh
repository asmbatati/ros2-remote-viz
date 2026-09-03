# Shared helpers. Sourced by bin/rrv; not executable on its own.

RRV_ROOT="${RRV_ROOT:?RRV_ROOT must be set}"
RRV_CACHE="${RRV_CACHE:-$RRV_ROOT/.cache}"

# --- output -----------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RST=$'\033[0m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_CYN=$'\033[36m'
else
  C_RST=; C_DIM=; C_B=; C_RED=; C_GRN=; C_YEL=; C_CYN=
fi

info()  { printf '%s\n' "$*"; }
step()  { printf '%s==>%s %s\n' "$C_CYN$C_B" "$C_RST" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn()  { printf '%swarn%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
die()   { printf '%s fail%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }
dim()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RST"; }

# --- config -----------------------------------------------------------------
# Config lives in config/<profile>.env. Anything already exported wins, so
# single settings can be overridden per invocation without editing the file.
load_profile() {
  local profile="${1:-default}"
  local f="$RRV_ROOT/config/$profile.env"
  [ -f "$f" ] || die "no such profile: $profile (expected $f)
Run: rrv init $profile"
  RRV_PROFILE="$profile"
  # shellcheck disable=SC1090
  set -a; . "$f"; set +a

  : "${REMOTE_SSH:?REMOTE_SSH must be set in $f}"
  : "${RMW:=auto}"
  : "${REMOTE_CONTAINER:=auto}"
  : "${ROS_DOMAIN_ID:=0}"
  # Address the local side dials to reach the remote. Defaults to the SSH host,
  # which is right on a LAN; override for VPNs where SSH and data take different
  # routes.
  : "${TRANSPORT_HOST:=${REMOTE_SSH#*@}}"
  export RRV_PROFILE RMW REMOTE_CONTAINER ROS_DOMAIN_ID TRANSPORT_HOST
}

# --- ssh --------------------------------------------------------------------
# One multiplexed connection for the whole run: detection makes many small
# calls and a fresh TCP+auth handshake for each is the dominant cost.
ssh_ctl_path() { echo "${TMPDIR:-/tmp}/rrv-%r@%h:%p"; }
rsh() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 \
      -o ControlMaster=auto -o ControlPath="$(ssh_ctl_path)" -o ControlPersist=60 \
      "$REMOTE_SSH" "$@"
}
rsh_check() {
  rsh true 2>/dev/null && return 0
  die "cannot ssh to $REMOTE_SSH with key auth.
Set it up once with:  ssh-copy-id $REMOTE_SSH
(run that in a real terminal; it needs a TTY to read the password)"
}

# --- cache ------------------------------------------------------------------
cache_file() { echo "$RRV_CACHE/$RRV_PROFILE.env"; }
cache_load() {
  local f; f="$(cache_file)"
  [ -f "$f" ] || die "no detection cache for '$RRV_PROFILE'. Run: rrv detect $RRV_PROFILE"
  # shellcheck disable=SC1090
  set -a; . "$f"; set +a
}
cache_save() {
  local f; f="$(cache_file)"; mkdir -p "$(dirname "$f")"
  : > "$f"
  local kv
  for kv in "$@"; do printf '%s\n' "$kv" >> "$f"; done
}

# Print the first element of $2 (space separated) that also appears in $1.
# Used to pick an RMW both sides actually have.
first_common() {
  local have="$1" want="$2" w h
  for w in $want; do
    for h in $have; do [ "$w" = "$h" ] && { echo "$w"; return 0; }; done
  done
  return 1
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }
