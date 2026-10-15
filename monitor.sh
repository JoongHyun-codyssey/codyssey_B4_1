#!/bin/bash

set -uo pipefail

APP_NAME="agent-app-linux-arm64"
APP_PORT=15034

echo "====== SYSTEM MONITOR RESULT ======"
echo
echo "[HEALTH CHECK]"

# 전체 실행 명령어에서 앱을 찾고, PID들을 쉼표로 연결한다.
PIDS=$(pgrep -d ',' -u agent-admin \
  -f "(^|/)$APP_NAME([[:space:]]|$)" || true)

if [[ -z "$PIDS" ]]; then
    echo "[FAIL] Process '$APP_NAME' is not running."
    exit 1
fi

echo "[OK] Process '$APP_NAME' (PID: $PIDS)"

# 헤더를 제외한 TCP LISTEN 결과가 있는지 확인한다.
if ! ss -H -ltn "sport = :$APP_PORT" | grep -q .; then
    echo "[FAIL] TCP port $APP_PORT is not listening."
    exit 1
fi

echo "[OK] TCP port $APP_PORT is listening."

export LC_ALL=C

echo
echo "[RESOURCE MONITORING]"

# CPU 누적 시간과 유휴 시간을 읽는다.
read_cpu() {
    awk '/^cpu / {
        total = 0
        for (i = 2; i <= 9; i++) total += $i
        idle = $5 + $6
        printf "%.0f %.0f\n", total, idle
        exit
    }' /proc/stat
}

# 1초 동안 증가한 시간을 비교해 CPU 사용률을 계산한다.
read -r TOTAL1 IDLE1 < <(read_cpu)
sleep 1
read -r TOTAL2 IDLE2 < <(read_cpu)

CPU=$(awk \
    -v t1="$TOTAL1" -v i1="$IDLE1" \
    -v t2="$TOTAL2" -v i2="$IDLE2" '
    BEGIN {
        elapsed = t2 - t1
        idle = i2 - i1
        if (elapsed <= 0) exit 1
        usage = 100 * (elapsed - idle) / elapsed
        if (usage < 0) usage = 0
        if (usage > 100) usage = 100
        printf "%.1f", usage
    }') || {
    echo "[FAIL] CPU measurement failed."
    exit 1
}

# 전체 메모리 중 사용 가능한 메모리를 뺀 비율이다.
MEM=$(awk '
    /^MemTotal:/     { total = $2 }
    /^MemAvailable:/ { available = $2; found = 1 }
    END {
        if (total <= 0 || !found) exit 1
        printf "%.1f", 100 * (total - available) / total
    }' /proc/meminfo) || {
    echo "[FAIL] Memory measurement failed."
    exit 1
}

# 루트 파일시스템의 사용률에서 % 문자를 제거한다.
DISK_USED=$(df -P / | awk 'NR == 2 {
    gsub(/%/, "", $5)
    print $5
}') || {
    echo "[FAIL] Disk measurement failed."
    exit 1
}

if [[ ! "$DISK_USED" =~ ^[0-9]+$ ]]; then
    echo "[FAIL] Invalid disk usage."
    exit 1
fi

printf 'CPU Usage : %s%%\n' "$CPU"
printf 'MEM Usage : %s%%\n' "$MEM"
printf 'DISK Used : %s%%\n' "$DISK_USED"

# 소수점 비교는 awk로 수행한다. 초과할 때만 경고한다.
warn_if_high() {
    local name="$1" value="$2" threshold="$3"

    if awk -v value="$value" -v limit="$threshold" \
        'BEGIN { exit !(value > limit) }'; then
        printf '[WARNING] %s threshold exceeded (%s%% > %s%%)\n' \
            "$name" "$value" "$threshold"
    fi
}

warn_if_high CPU "$CPU" 20
warn_if_high MEM "$MEM" 10
warn_if_high DISK_USED "$DISK_USED" 80

echo
echo "[FIREWALL CHECK]"

# 조회에 필요한 명령어만 sudo로 실행한다.
if FIREWALL_STATUS=$(/usr/bin/sudo -n /usr/sbin/ufw status 2>&1); then
    if grep -qx 'Status: active' <<< "$FIREWALL_STATUS"; then
        echo "[OK] UFW is active."
    elif grep -qx 'Status: inactive' <<< "$FIREWALL_STATUS"; then
        echo "[WARNING] UFW is inactive."
    else
        echo "[WARNING] Unrecognized UFW status."
    fi
else
    echo "[WARNING] Could not query UFW status."
    printf '%s\n' "$FIREWALL_STATUS" >&2
fi

# 방화벽 경고가 발생해도 로그 기록은 계속한다.

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

LOG_DIR="/var/log/agent-app"
LOG_FILE="$LOG_DIR/monitor.log"
MAX_BYTES=$((10 * 1024 * 1024))

umask 007

# 동시에 실행돼도 로그 회전과 기록이 겹치지 않도록 잠근다.
exec 9>"$LOG_DIR/.monitor.lock" || fail "Cannot open log lock."
flock -x 9 || fail "Cannot lock log."

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

LOG_LINE=$(printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%' \
    "$TIMESTAMP" "$PIDS" "$CPU" "$MEM" "$DISK_USED")

CURRENT_SIZE=0
if [[ -f "$LOG_FILE" ]]; then
    CURRENT_SIZE=$(stat -c %s "$LOG_FILE") \
        || fail "Cannot read log size."
fi

# 새 로그와 줄바꿈 1바이트를 포함해 크기를 검사한다.
if (( CURRENT_SIZE + ${#LOG_LINE} + 1 > MAX_BYTES )); then

    # 가장 오래된 보관 로그를 삭제한다.
    rm -f -- "$LOG_FILE.9.gz" \
        || fail "Cannot remove oldest archive."

    # 기존 보관 로그의 번호를 뒤에서부터 증가시킨다.
    for ((i = 8; i >= 1; i--)); do
        if [[ -f "$LOG_FILE.$i.gz" ]]; then
            mv -- "$LOG_FILE.$i.gz" "$LOG_FILE.$((i + 1)).gz" \
                || fail "Cannot shift archive."
        fi
    done

    # 현재 로그를 압축 보관한 뒤 내용만 비운다.
    if [[ -s "$LOG_FILE" ]]; then
        gzip -c -- "$LOG_FILE" > "$LOG_FILE.1.gz" \
            || fail "Cannot compress log."

        : > "$LOG_FILE" || fail "Cannot truncate log."
    fi

    echo "[INFO] Log rotated."
fi

printf '%s\n' "$LOG_LINE" >> "$LOG_FILE" \
    || fail "Cannot append log."

echo
echo "[INFO] Log appended: $LOG_FILE"
