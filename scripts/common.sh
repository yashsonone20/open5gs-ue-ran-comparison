#!/usr/bin/env bash
# Shared helpers. Sourced by every script; not meant to be run directly.

BENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
source "$BENCH_ROOT/config.env"

RESULTS_ROOT="$BENCH_ROOT/$RESULTS_DIR/$PLATFORM"

c_green=$'\e[32m'; c_red=$'\e[31m'; c_yel=$'\e[33m'; c_off=$'\e[0m'
pass() { echo "${c_green}[PASS]${c_off} $*"; }
fail() { echo "${c_red}[FAIL]${c_off} $*"; }
warn() { echo "${c_yel}[WARN]${c_off} $*"; }
info() { echo "[INFO] $*"; }

need() {  # need <command> [apt package]
  command -v "$1" >/dev/null 2>&1 || { fail "'$1' not found. Install it: sudo apt install -y ${2:-$1}"; exit 1; }
}

run_tag() { date +%Y%m%d-%H%M%S; }

# Run a command inside the UE's data path context.
# Namespace mode: inside the namespace. Interface mode: as-is (caller binds to UE_IF).
ue_exec() {
  if [[ -n "$UE_NS" ]]; then sudo ip netns exec "$UE_NS" "$@"; else "$@"; fi
}

# IPv4 address of a UE interface (default UE_IF), looked up in the right context.
ue_ip() {
  local ifc="${1:-$UE_IF}"
  ue_exec ip -4 -o addr show dev "$ifc" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
}

# ping arguments that force traffic onto the UE tunnel in interface mode
ping_bind_args() {
  local ifc="${1:-$UE_IF}"
  if [[ -n "$UE_NS" ]]; then echo ""; else echo "-I $ifc"; fi
}

# OAI and free-ran-ue do not add a default route inside their namespace; make sure one
# exists (it disappears whenever the UE restarts). UERANSIM sets its own.
ensure_ue_route() {
  [[ "$PLATFORM" != "ueransim" && -n "$(ue_ip)" ]] && sudo ip netns exec "$UE_NS" ip route replace default dev "$UE_IF"
  return 0
}

# Start/stop one UE of the current platform in the background, output to a log file.
start_ue() {  # start_ue <logfile>
  case "$PLATFORM" in
    ueransim) sudo stdbuf -oL -eL "$UERANSIM_DIR/build/nr-ue" -c "$UE_CFG" > "$1" 2>&1 & ;;
    # shellcheck disable=SC2086
    oai) ( cd "$OAI_BUILD" && sudo ip netns exec "$OAI_NS" stdbuf -oL -eL ./nr-uesoftmodem $OAI_UE_ARGS > "$1" 2>&1 ) & ;;
    freeran) ( cd "$FRUE_DIR" && sudo ip netns exec "$FRUE_NS" ./build/free-ran-ue ue -c "$FRUE_UE_CFG" > "$1" 2>&1 ) & ;;
  esac
}
stop_ues() {
  local p
  for p in nr-ue nr-uesoftmodem; do
    pgrep -x "$p" >/dev/null || continue
    sudo pkill -INT -x "$p"; sleep 2
    pgrep -x "$p" >/dev/null && { sudo pkill -KILL -x "$p"; sleep 1; }
  done
  # free-ran-ue: same binary for gNB and UE - stop only the UE ones
  local pids; pids=$(role_pids free-ran-ue ue)
  if [[ -n "$pids" ]]; then
    sudo kill -INT $pids 2>/dev/null; sleep 2
    pids=$(role_pids free-ran-ue ue); [[ -n "$pids" ]] && { sudo kill -KILL $pids 2>/dev/null; sleep 1; }
  fi
  return 0
}

# PIDs of a program started with a given sub-command, e.g. role_pids free-ran-ue gnb
role_pids() {
  local pid
  for pid in $(pgrep -x "$1"); do
    ps -o args= -p "$pid" | grep -qE "(^|[[:space:]])$2([[:space:]]|$)" && echo "$pid"
  done
}

# Number of running gNB / UE program instances for the current platform
gnb_count() { if [[ "$PLATFORM" == "freeran" ]]; then role_pids free-ran-ue gnb | wc -l; else count_instances "$GNB_PROC"; fi; }
ue_count()  { if [[ "$PLATFORM" == "freeran" ]]; then role_pids free-ran-ue ue  | wc -l; else count_instances "$UE_PROC";  fi; }

# Count instances of a program, not processes: OAI forks a child process and sudo adds
# its own parent, so one gNB shows up as several PIDs. Counts only "top" processes
# whose parent is not the same program.
count_instances() {  # count_instances <exact process name>
  local n=0 pid ppid
  for pid in $(pgrep -x "$1"); do
    ppid=$(ps -o ppid= -p "$pid" | tr -d ' ')
    [[ "$(ps -o comm= -p "$ppid" 2>/dev/null)" == "$1" ]] || n=$((n+1))
  done
  echo $n
}

# Packet counter on ogstun. Used to prove traffic really crossed the 5G user plane
# (when UE and core share one machine, traffic to 10.45.0.1 can silently take the
# loopback shortcut and never touch GTP-U).
ogstun_rx() { cat /sys/class/net/ogstun/statistics/rx_packets 2>/dev/null || echo 0; }

assert_userplane() {  # assert_userplane <rx_before> <label>
  local after; after=$(ogstun_rx)
  local delta=$(( after - $1 ))
  if (( delta > 0 )); then
    pass "$2: $delta packets crossed ogstun (traffic used the 5G user plane)"
  else
    fail "$2: 0 packets on ogstun - traffic did NOT go through the 5G user plane; result is invalid"
    echo "$2 INVALID_NO_USERPLANE" >> "${OUT_DIR:-/tmp}/VALIDITY.txt"
  fi
}
