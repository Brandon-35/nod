#!/bin/bash
# Measures Nod's CPU (ps samples, optional powermetrics) and AirPods battery before/after one run.
# Founder runs it later on a real Mac with worn AirPods; no number from here is published before that.
# Usage: scripts/measure-cpu.sh --label on|off [--duration SEC] [--interval SEC] [--max-load N]
#                               [--out DIR] [--powermetrics] [--dry-run]
#   --dry-run  fake CPU and battery source, no sleeping, no sudo; checks the script only, result is NOT a measurement.
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="" DURATION=3600 INTERVAL=5 MAX_LOAD=6 OUT="dist/perf" POWERMETRICS=0 DRY=0 PROC="Nod"
die() { echo "measure-cpu: $*" >&2; exit 1; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --label) LABEL="${2:?}"; shift 2 ;;
        --duration) DURATION="${2:?}"; shift 2 ;;
        --interval) INTERVAL="${2:?}"; shift 2 ;;
        --max-load) MAX_LOAD="${2:?}"; shift 2 ;;
        --out) OUT="${2:?}"; shift 2 ;;
        --powermetrics) POWERMETRICS=1; shift ;;
        --dry-run) DRY=1; shift ;;
        *) die "unknown argument: $1" ;;
    esac
done
[[ "$LABEL" == "on" || "$LABEL" == "off" ]] || { [[ "$DRY" == 1 ]] && LABEL="${LABEL:-on}" || die "--label on|off is required"; }
[[ "$DURATION" =~ ^[0-9]+$ && "$INTERVAL" =~ ^[0-9]+$ && "$INTERVAL" -gt 0 ]] || die "duration/interval must be whole seconds"

# 1-minute load average from "{ 1m 5m 15m }".
LOAD1="$(sysctl -n vm.loadavg | awk '{print $2}')"
over_limit() { awk -v l="$LOAD1" -v m="$MAX_LOAD" 'BEGIN{exit !(l>m)}'; }
if over_limit; then
    if [[ "$DRY" == 1 ]]; then echo "measure-cpu: load $LOAD1 > $MAX_LOAD (ignored in --dry-run)" >&2
    else die "machine load $LOAD1 is above $MAX_LOAD; refusing to record. Wait for the load to drop."; fi
fi

# Reads the first AirPods battery percentage from system_profiler; prints "n/a" when none shows.
battery() {
    if [[ "$DRY" == 1 ]]; then echo "${FAKE_BATTERY:-80}"; return; fi
    system_profiler SPBluetoothDataType 2>/dev/null | awk -F': ' '/Battery Level/ {gsub(/[ %]/,"",$2); print $2; f=1; exit} END{if(!f) print "n/a"}'
}

if [[ "$DRY" == 1 ]]; then
    PID=0; SAMPLES=20; MODE="SIMULATED (dry-run, not a measurement)"
else
    [[ "$(uname)" == "Darwin" ]] || die "macOS only"
    PID="$(pgrep -x "$PROC" | head -1 || true)"
    if [[ "$LABEL" == "on" ]]; then [[ -n "$PID" ]] || die "$PROC is not running; start dist/Nod.app first"; fi
    SAMPLES=$((DURATION / INTERVAL)); MODE="MEASURED"
fi

mkdir -p "$OUT"
STAMP="$(date +%Y%m%d-%H%M%S)"
RAW="$OUT/$STAMP-$LABEL.samples"; RES="$OUT/$STAMP-$LABEL.txt"; : > "$RAW"
PM_PID=""
if [[ "$POWERMETRICS" == 1 && "$DRY" == 0 ]]; then
    [[ "$(id -u)" == 0 ]] || die "--powermetrics needs sudo: sudo scripts/measure-cpu.sh ..."
    powermetrics --samplers tasks -i $((INTERVAL * 1000)) -n "$SAMPLES" > "$OUT/$STAMP-$LABEL.powermetrics" 2>&1 & PM_PID=$!
fi
BAT_BEFORE="$(battery)"
for ((i = 0; i < SAMPLES; i++)); do
    if [[ "$DRY" == 1 ]]; then awk -v i="$i" 'BEGIN{printf "%.1f\n", 0.3 + (i % 5) * 0.1}' >> "$RAW"
    elif [[ "$LABEL" == "on" ]]; then ps -o %cpu= -p "$PID" | tr -d ' ' >> "$RAW" || break
    else echo 0 >> "$RAW"; fi
    [[ "$DRY" == 1 ]] || sleep "$INTERVAL"
done
BAT_AFTER="$(battery)"
[[ -z "$PM_PID" ]] || wait "$PM_PID" || true

STATS="$(sort -n "$RAW" | awk '{v[NR]=$1; s+=$1} END{if(!NR){print "0 0 0 0"; exit} m=(NR%2)?v[(NR+1)/2]:(v[NR/2]+v[NR/2+1])/2; printf "%d %.2f %.2f %.2f", NR, s/NR, m, v[NR]}')"
read -r N MEAN MEDIAN PEAK <<< "$STATS"
{
    echo "status: $MODE"
    echo "date: $(date '+%Y-%m-%d %H:%M:%S')  macos: $(sw_vers -productVersion)  label: Nod-$LABEL"
    echo "load1: $LOAD1 (limit $MAX_LOAD)  duration_s: $DURATION  interval_s: $INTERVAL  pid: ${PID:-none}"
    echo "samples: $N  cpu_mean_pct: $MEAN  cpu_median_pct: $MEDIAN  cpu_peak_pct: $PEAK"
    echo "airpods_battery_before: $BAT_BEFORE  after: $BAT_AFTER"
    echo "note: compare the on run with the off run; a single run proves nothing. Raw samples: $RAW"
} | tee "$RES"
echo "measure-cpu: wrote $RES"
