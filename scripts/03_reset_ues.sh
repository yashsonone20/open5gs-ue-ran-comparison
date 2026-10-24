#!/usr/bin/env bash
# Stop every UE (UERANSIM nr-ue, OAI nr-uesoftmodem, free-ran-ue ue). The gNB keeps running.
source "$(dirname "$0")/common.sh"
n=$(( $(pgrep -c -x nr-ue) + $(pgrep -c -x nr-uesoftmodem) + $(role_pids free-ran-ue ue | wc -l) ))
(( n > 0 )) && info "Stopping $n UE process(es)"
stop_ues
pass "No UE processes running"
