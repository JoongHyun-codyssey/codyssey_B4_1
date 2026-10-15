# Linux 서버 보안 설정 및 시스템 관제 자동화

Ubuntu 컨테이너에 SSH·방화벽·역할별 접근 권한을 구성하고, 제공 앱의 프로세스·포트와 시스템 자원을 Bash로 점검했다. 점검 결과는 로그에 누적하고, `agent-admin`의 cron으로 매분 수집하도록 설정했다.

## 1. 환경과 제출물

| 항목 | 실제 구성 |
| --- | --- |
| 실습일 | 2026-10-15 |
| 호스트 | macOS, Apple Silicon ARM64 |
| 실습 환경 | Docker Desktop, Ubuntu 22.04 LTS ARM64 컨테이너 |
| 컨테이너·호스트명 | `agent-lab` |
| 제공 앱 | `agent-app-linux-arm64` — Linux ARM64 실행 파일 |
| 자동화 언어 | Bash |
| 방화벽 | UFW |
| SSH / 앱 포트 | TCP 20022 / TCP 15034 |
| 앱 실행 / cron 계정 | `agent-admin` |
| 스크립트 작성 계정 | `agent-dev` |
| 최종 시간대 | `Asia/Seoul` — KST, UTC+09:00 |

제출물은 이 수행 내역서와 [monitor.sh](monitor.sh)이다. 증거 이미지는 저장소의 `docs/screenshots/`에 배치한다. 제공 실행 파일과 키 파일은 Git에 포함하지 않는다.

> 증거 이미지 파일명은 10절에 정리했다. `09-cron-registration.png`는 등록 내용을 별도로 캡처해 추가해야 한다. cron의 실제 자동 실행은 로그 증가로 확인했다.

## 2. 실습 환경 준비

아래 명령어는 설정과 검증 과정을 재현하기 위한 기록이다. 이미 구성한 환경에서 컨테이너·계정 생성 명령을 다시 실행할 필요는 없다. `root`로 표시한 작업은 컨테이너 내부에서 수행했다.

### 2.1 컨테이너 생성 — Mac 터미널

저장소의 `data/`에 제공 앱을 준비하고 Docker Desktop을 실행한 상태에서 진행했다.

```bash
cd ~/Desktop/codyssey_b4_1/data
docker run -d \
  --name agent-lab --hostname agent-lab --platform linux/arm64 \
  --init --cap-add NET_ADMIN \
  -p 127.0.0.1:20022:20022 -p 127.0.0.1:15034:15034 \
  --mount "type=bind,source=$(pwd),target=/mission-data,readonly" \
  ubuntu:22.04 sleep infinity
docker exec -it agent-lab bash
```

`NET_ADMIN`은 실습 컨테이너에서 UFW를 설정하기 위해 부여했다. 호스트의 포트는 `127.0.0.1`에 게시했으며, 앱은 컨테이너 내부에서 `0.0.0.0:15034`로 리슨한다.

### 2.2 패키지 설치 — root

```bash
apt-get update
apt-get install -y sudo openssh-server ufw acl cron logrotate procps iproute2 nano file
```

로그 회전은 `monitor.sh`의 Bash 로직으로 구현했다. 설치한 `logrotate`를 이용한 별도 회전 규칙은 구성하지 않았다.

## 3. 계정·그룹 및 접근 권한

### 3.1 계정·그룹 생성 — root

```bash
groupadd agent-common
groupadd agent-core
useradd -m -U -s /bin/bash -G agent-common,agent-core agent-admin
useradd -m -U -s /bin/bash -G agent-common,agent-core agent-dev
useradd -m -U -s /bin/bash -G agent-common agent-test
passwd agent-admin

id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core
```

| 계정 | 역할 | 공통 그룹 | 핵심 그룹 |
| --- | --- | --- | --- |
| `agent-admin` | 앱 운영, cron 실행 | `agent-common` | `agent-core` |
| `agent-dev` | 스크립트 작성, 개발·운영 | `agent-common` | `agent-core` |
| `agent-test` | QA·테스트 | `agent-common` | 소속되지 않음 |

각 계정에는 별도의 기본 그룹도 있다. `id`와 그룹 조회로 위 보조 그룹 구성을 확인했다.

### 3.2 디렉토리와 ACL 설정 — root

```bash
export AGENT_HOME=/home/agent-admin/agent-app
mkdir -p "$AGENT_HOME"/{upload_files,api_keys,bin} /var/log/agent-app

chown agent-admin:agent-common "$AGENT_HOME" "$AGENT_HOME/upload_files"
chown agent-admin:agent-core "$AGENT_HOME/api_keys" /var/log/agent-app
chown agent-dev:agent-core "$AGENT_HOME/bin"

chmod 2750 "$AGENT_HOME" "$AGENT_HOME/bin"
chmod 2770 "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" /var/log/agent-app

setfacl -m g:agent-common:--x /home/agent-admin
setfacl -d -m u::rwx,g::rwx,m::rwx,o::--- \
  "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" /var/log/agent-app
```

| 경로 | 소유자:그룹 | 권한 | 목적 |
| --- | --- | --- | --- |
| `/home/agent-admin` | `agent-admin:agent-admin` | `agent-common`에 ACL `--x` 추가 | 공유 경로까지 통과 허용 |
| `$AGENT_HOME` | `agent-admin:agent-common` | `2750` | 그룹에 조회·통과 허용 |
| `$AGENT_HOME/upload_files` | `agent-admin:agent-common` | `2770` + 기본 ACL | 세 계정의 공유 공간 |
| `$AGENT_HOME/api_keys` | `agent-admin:agent-core` | `2770` + 기본 ACL | admin·dev의 키 관리 공간 |
| `/var/log/agent-app` | `agent-admin:agent-core` | `2770` + 기본 ACL | admin·dev의 로그 관리 공간 |
| `$AGENT_HOME/bin` | `agent-dev:agent-core` | `2750` | 스크립트 작성·실행 공간 |
| `$AGENT_HOME/bin/monitor.sh` | `agent-dev:agent-core` | `750` | dev가 수정하고 core가 실행 |

디렉토리의 setgid로 새 항목이 디렉토리 그룹을 상속하도록 했다. 기본 ACL은 새 항목에 적용할 권한을 지정한다. 단, 생성 프로그램이 명시적으로 제한한 파일 모드를 기본 ACL이 무조건 넓히지는 않는다.

```bash
ls -ld /home/agent-admin "$AGENT_HOME" "$AGENT_HOME/bin" \
  "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" /var/log/agent-app
getfacl /home/agent-admin "$AGENT_HOME/upload_files" \
  "$AGENT_HOME/api_keys" /var/log/agent-app
ls -l "$AGENT_HOME/bin/monitor.sh"
```

역할별로 각 디렉토리에 임시 파일을 생성·기록·조회·삭제하는 테스트를 수행했다.

| 계정 | upload_files | api_keys | 로그 디렉토리 |
| --- | --- | --- | --- |
| agent-admin | 허용 | 허용 | 허용 |
| agent-dev | 허용 | 허용 | 허용 |
| agent-test | 허용 | 거부 | 거부 |

총 **7개 허용, 2개 거부**를 확인했다. 이 검증은 각 계정의 디렉토리 접근과 파일 작업을 확인한 것으로, 다른 계정이 만든 모든 파일의 수정 권한까지 검증한 것은 아니다. 민감 경로의 제한은 일반 사용자 기준이며 root의 관리 권한은 별개다.

## 4. SSH 및 방화벽

### 4.1 SSH 설정 — root

`/etc/ssh/sshd_config.d/00-agent-lab.conf`에 다음 내용을 설정했다.

```text
Port 20022
PermitRootLogin no
```

```bash
mkdir -p /run/sshd
sshd -t && service ssh restart
sshd -T | grep -E '^(port|permitrootlogin) '
ss -tlnp 'sport = :20022'
```

유효 설정에서 `port 20022`, `permitrootlogin no`를 확인했고, SSH의 20022 포트 리슨을 확인했다. Mac 터미널에서 일반 계정 접속도 검증했다.

```bash
ssh -p 20022 agent-admin@127.0.0.1
whoami
id
```

접속 계정은 `agent-admin`이었다. SSH 포트 변경은 기본 포트를 노리는 접근을 줄이는 보조 조치이며, Root 원격 로그인 차단은 관리자 계정에 대한 직접 원격 접근을 제한한다.

### 4.2 UFW 설정 — root

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw enable
ufw status verbose
ufw status numbered
```

| 항목 | 확인 결과 |
| --- | --- |
| 활성 상태 | `Status: active` |
| 기본 정책 | incoming deny, outgoing allow, routed deny |
| IPv4 허용 포트 | `20022/tcp`, `15034/tcp` |
| IPv6 허용 포트 | `20022/tcp (v6)`, `15034/tcp (v6)` |

인바운드의 신규 접근은 필요한 TCP 포트만 허용하도록 구성했다.

## 5. 제공 앱 실행 환경

### 5.1 과제 명세와 제공 실행 파일의 차이

실제 제공 파일은 직접 실행하는 Linux ARM64 바이너리였다. 실행 시 출력된 오류를 기준으로 다음 차이를 확인했다.

| 항목 | 과제 명세 | 제공 바이너리가 요구한 값 / 적용 내용 |
| --- | --- | --- |
| 실행 대상 | `agent_app.py` 등 Python 앱 | `./agent-app-linux-arm64` |
| `AGENT_KEY_PATH` | 키 파일 전체 경로 | `$AGENT_HOME/api_keys` 디렉토리 |
| 필수 키 파일명 | `t_secret.key` | `secret.key` |

명세의 `t_secret.key`도 생성하고, 바이너리가 요구하는 `secret.key`를 같은 내용으로 추가했다. 앱 파일은 수정하지 않았다.

### 5.2 환경 변수 설정 — root

`/etc/profile.d/agent-app.sh`에 다음 내용을 저장하고 소유자 `root:root`, 권한 `644`로 설정했다.

```bash
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys"
export AGENT_LOG_DIR=/var/log/agent-app
```

기존 셸에서는 `source /etc/profile.d/agent-app.sh`로 반영했다. 실행 환경은 다음 명령과 앱의 환경 변수 검사 단계로 확인했다.

```bash
env | sort | grep '^AGENT_'
```

### 5.3 앱과 키 파일 배치 — root

```bash
source /etc/profile.d/agent-app.sh
cp /mission-data/agent-app-linux-arm64 "$AGENT_HOME/"
chown agent-admin:agent-core "$AGENT_HOME/agent-app-linux-arm64"
chmod 750 "$AGENT_HOME/agent-app-linux-arm64"

printf '%s\n' 'agent_api_key_test' > "$AGENT_HOME/api_keys/t_secret.key"
cp "$AGENT_HOME/api_keys/t_secret.key" "$AGENT_HOME/api_keys/secret.key"
chown agent-admin:agent-core "$AGENT_HOME/api_keys/"*.key
chmod 660 "$AGENT_HOME/api_keys/"*.key
```

### 5.4 앱 실행 — SSH로 접속한 agent-admin

```bash
source /etc/profile.d/agent-app.sh
cd "$AGENT_HOME"
./agent-app-linux-arm64
```

| Boot Sequence | 확인 결과 |
| --- | --- |
| 1. User Account | `[OK]` — 일반 계정 `agent-admin`으로 실행 |
| 2. Environment Variables | `[OK]` |
| 3. Required Files | `[OK]` |
| 4. Port Availability | `[OK]` |
| 5. Log Permission | `[OK]` |
| 최종 준비 상태 | `Agent READY` 출력 |

다른 root 터미널에서 다음을 확인했다.

```bash
ss -tlnp 'sport = :15034'
ps -u agent-admin -o pid,ppid,comm,args
```

`0.0.0.0:15034`의 LISTEN 상태와 앱 프로세스를 확인했다. 최초 검증에서는 PID `4470,4471`이 관찰되었고, 앱 재실행 후에는 PID가 달라졌다. 앱 실행 터미널은 유지하고, 종료 테스트에는 `Ctrl+C`를 사용했다.

## 6. monitor.sh 구현 및 실행

### 6.1 파일과 실행 권한

`agent-dev` 계정으로 `$AGENT_HOME/bin/monitor.sh`를 작성하고 권한을 `750`으로 설정했다. 최종 소유 관계는 `agent-dev:agent-core`이다.

스크립트의 첫 줄은 `#!/bin/bash`이며, `set -uo pipefail`을 사용한다. 실행은 파일 경로를 직접 호출하거나 `bash`로 수행한다.

```bash
# root 터미널에서 일반 계정으로 실행
runuser -u agent-admin -- /home/agent-admin/agent-app/bin/monitor.sh
echo "Exit code: $?"
```

정상 실행에서 프로세스·포트 `[OK]`, CPU·메모리·디스크 사용률, UFW 활성 상태, 로그 기록 완료 메시지와 종료 코드 `0`을 확인했다. 제출한 소스는 `bash -n monitor.sh` 문법 검사도 통과했다.

### 6.2 점검 및 자원 수집 방식

| 항목 | 구현 방식 | 처리 기준 |
| --- | --- | --- |
| 프로세스 | `pgrep -u agent-admin -f`로 실행 명령에서 앱 파일명 검색, 여러 PID를 쉼표로 연결 | 없으면 실패 메시지 후 `exit 1` |
| 포트 | `ss -H -ltn 'sport = :15034'` | LISTEN 결과가 없으면 `exit 1` |
| CPU | `/proc/stat`을 1초 간격으로 두 번 읽어 전체·유휴 시간 차이 계산 | `> 20%` 경고 |
| 메모리 | `/proc/meminfo`에서 `(MemTotal - MemAvailable) / MemTotal × 100` | `> 10%` 경고 |
| 디스크 | `df -P /`의 Used % | `> 80%` 경고 |
| 방화벽 | `sudo -n /usr/sbin/ufw status` | 비활성 또는 조회 실패 시 경고, 계속 실행 |

자원 임계값은 **초과** 조건이다. 경고는 점검과 로그 기록을 중단하지 않는다. CPU·메모리·디스크 수집 실패와 로그 기록 실패는 별도의 실패로 종료한다.

CPU 계산은 전체 시간에서 idle과 iowait를 유휴 시간으로 처리하며 guest 시간을 중복 합산하지 않는다. 수집하는 값은 `/proc`에 노출된 시스템 기준으로, 앱 프로세스 자체의 CPU·메모리 사용률이나 컨테이너 cgroup 한도 대비 사용률과는 구분한다. 프로세스 존재와 포트 리슨은 각각 검사하며, 해당 소켓이 앱 PID 소유인지까지 대조하지는 않는다.

### 6.3 방화벽 조회 권한 — root

일반 계정이 암호 입력 없이 상태만 조회하도록 `/etc/sudoers.d/agent-monitor`에 다음 규칙을 설정했다.

```sudoers
agent-admin ALL=(root) NOPASSWD: /usr/sbin/ufw status
```

```bash
chmod 440 /etc/sudoers.d/agent-monitor
visudo -cf /etc/sudoers.d/agent-monitor
runuser -u agent-admin -- sudo -n /usr/sbin/ufw status
```

문법 검사와 일반 계정의 상태 조회를 확인했다. `agent-admin`에 UFW 변경 명령이나 포괄적인 sudo 권한을 추가하지 않았다.

### 6.4 로그 형식과 회전

로그 경로는 `/var/log/agent-app/monitor.log`이다. 실제 기록은 다음과 같다.

```text
[2026-10-15 16:45:02] PID:4470,4471 CPU:3.7% MEM:9.0% DISK_USED:4%
[2026-10-15 16:46:02] PID:4470,4471 CPU:1.6% MEM:8.3% DISK_USED:4%
[2026-10-15 16:53:25] PID:5787,5788 CPU:3.8% MEM:9.4% DISK_USED:4%
```

| 항목 | 구현 내용 |
| --- | --- |
| 크기 기준 | `10 × 1024 × 1024`바이트, 즉 10MiB를 과제의 10MB 기준으로 사용 |
| 검사 시점 | 새 로그 한 줄과 줄바꿈을 추가하면 기준을 넘는지 기록 전에 검사 |
| 보관 파일 | 현재 `monitor.log` 1개 + `.1.gz`부터 `.9.gz`까지 최대 9개 |
| 압축·삭제 | 가장 오래된 `.9.gz` 삭제 → 기존 번호 증가 → 현재 로그 gzip 압축 → 현재 로그 비우기 |
| 동시 실행 | `.monitor.lock`에 `flock`을 적용해 회전·기록 구간 직렬화 |
| 파일 생성 권한 | `umask 007`, 운영 디렉토리의 그룹·기본 ACL 적용 |

10개 제한은 `monitor.log`와 회전본의 합계다. 잠금 파일과 cron의 마지막 콘솔 출력 파일은 이 로그 보관본 개수에 포함하지 않는다. 운영 로그의 소유 관계 `agent-admin:agent-core`, 권한 `660`을 확인했다.

## 7. cron 및 한국시간 설정

### 7.1 매분 실행 설정

root에서 `service cron start`로 서비스를 시작하고, `agent-admin`의 crontab을 편집했다.

```bash
runuser -u agent-admin -- env EDITOR=/usr/bin/nano crontab -e
```

실습에서 사용한 등록 구성은 다음과 같다. 제출 전 `crontab -u agent-admin -l` 출력 화면을 별도 증거로 추가한다.

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

* * * * * /home/agent-admin/agent-app/bin/monitor.sh > /var/log/agent-app/cron-last-run.txt 2>&1
```

스크립트는 앱 이름·포트·로그 경로를 내부에서 지정하므로 대화형 로그인 셸의 `AGENT_*` 변수에 의존하지 않는다. `monitor.log`에는 측정 이력을 누적하고 `cron-last-run.txt`에는 가장 최근 실행의 콘솔 출력만 덮어쓴다.

### 7.2 시간대 변경 — root

초기 로그가 UTC로 기록되어 한국시간으로 변경했다.

```bash
DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata
ln -snf /usr/share/zoneinfo/Asia/Seoul /etc/localtime
printf 'Asia/Seoul\n' > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata
service cron restart
date '+%Y-%m-%d %H:%M:%S %Z %z'
```

변경 후 `KST`를 확인했다. 기존 UTC 로그는 수정하지 않았으므로, 해당 실습 로그에는 시간대 변경 전·후 기록이 함께 있다. 변경 시점의 9시간 차이를 서비스 중단으로 해석하지 않는다.

### 7.3 자동 실행 검증

수동 실행 없이 다음 명령으로 로그 증가를 비교했다.

```bash
date '+%Y-%m-%d %H:%M:%S %Z'
wc -l /var/log/agent-app/monitor.log
tail -n 5 /var/log/agent-app/monitor.log
cat /var/log/agent-app/cron-last-run.txt
```

| 확인 시점 | 확인 시각 | 로그 줄 수 | 마지막 로그 시각 |
| --- | --- | --- | --- |
| 시간대 변경 후 첫 확인 | 2026-10-15 16:44:45 KST | 7 | 07:44:02 — 변경 전 UTC 기록 |
| 약 1분 23초 후 | 2026-10-15 16:46:08 KST | 9 | 16:46:02 KST |

`16:45:02`, `16:46:02` 두 줄이 자동으로 추가되었고, 마지막 실행 출력에서 프로세스·포트·UFW 정상 상태와 로그 기록 완료를 확인했다.

## 8. 기능 검증 결과

| 검증 항목 | 수행 방법 | 확인 결과 |
| --- | --- | --- |
| 정상 실행 | 앱 실행 중 admin으로 monitor 실행 | 프로세스·포트 OK, 자원 수집·로그 기록, 종료 코드 0 |
| 프로세스 실패 | 앱 터미널에서 Ctrl+C 후 monitor 실행 | 프로세스 FAIL, 종료 코드 1; 검증 후 앱 재실행 |
| 포트 실패 | 스크립트 복사본의 `APP_PORT`만 미사용 15035로 변경 | 프로세스 OK → 포트 FAIL, 종료 코드 1 |
| 방화벽 비활성 | UFW를 일시 중지하고 monitor 실행 | WARNING 후 로그 기록, 종료 코드 0 |
| 방화벽 복구 | 테스트 서브셸의 EXIT trap으로 UFW 재활성화 | `Status: active`, 기존 두 포트 허용 규칙 유지 |
| 메모리 경고 | 회전 테스트 중 MEM 10.5% 관찰 | `10.5% > 10%` WARNING 후 로그 기록 계속 |
| CPU·디스크 경고 | 제출 소스의 임계값 비교 로직 확인 | 구현 확인; 두 경고를 유발하는 실행 테스트는 별도 수행하지 않음 |
| 로그 회전 | `/tmp/agent-rotation.*`에서 로그 경로를 바꾼 복사본으로 크기 한계 테스트 11회 | 회전 성공, 현재 로그와 압축본 합계 10개 |
| 압축 무결성 | 테스트 압축 로그에 `gzip -t` 실행 | 모든 압축 파일 검사 통과 |
| cron 자동 실행 | 수동 실행을 멈추고 줄 수·시간 비교 | 7줄 → 9줄, 매분 신규 기록 확인 |

포트 실패는 원본의 15034 포트를 중단한 실험이 아니라, 복사본에 미사용 포트를 지정한 실패 분기 검증이다. 로그 회전 역시 운영 로그를 손상시키지 않도록 임시 경로의 복사본에서 검증했다.

## 9. 문제 해결 기록

| 문제 | 원인 및 조치 | 재검증 |
| --- | --- | --- |
| Docker 소켓에 연결 실패 | Docker Desktop이 실행되지 않아 `open -a Docker`로 시작 | Docker 명령 및 컨테이너 생성 진행 |
| `Key Path Mismatch` | 바이너리는 파일 경로가 아닌 `api_keys` 디렉토리를 요구하여 환경 변수 수정 | 환경 변수 단계 OK |
| `Missing File: secret.key` | 바이너리가 요구하는 파일명이 명세와 달라 동일 내용의 `secret.key` 추가 | 필수 파일 단계 OK, 최종 READY |
| `set: Illegal option -o pipefail` | Bash로 실행되지 않아 첫 줄을 `#!/bin/bash`로 바로잡고 직접 실행 | admin으로 실행 시 종료 코드 0 |
| 로그 시각이 07시로 표시 | 초기 UTC 설정을 `Asia/Seoul`로 변경하고 cron 재시작 | KST 시각의 자동 로그 확인 |

## 10. 증거 자료와 제출 체크리스트

아래 파일명으로 `docs/screenshots/`에 이미지를 배치한다. 앱 성공 화면은 `05-app-ready.png`로 이름을 정리한다. 경로는 저장소 기준이다.

| 증거 파일 | 확인 내용 | 상태 |
| --- | --- | --- |
| `01-ssh.png` | SSH 유효 설정, 20022 리슨 | 확인 |
| `01-ssh-login.png` | agent-admin의 SSH 접속 | 확인 |
| `02-firewall.png` | UFW active 및 허용 포트 | 확인 |
| `03-users-groups.png` | 계정·그룹 구성 | 확인 |
| `04-permissions-acl(1).png`, `04-permissions-acl(2).png` | 디렉토리 소유·권한 및 ACL | 확인 |
| `04-access-test.png` | 역할별 7개 허용, 2개 거부 | 확인 |
| `05-app-ready.png` | Boot Sequence 5단계 OK, Agent READY | 확인 |
| `05-app-port.png` | 0.0.0.0:15034 LISTEN | 결과 확인 |
| `06-monitor-result.png` | 프로세스·포트·자원·방화벽 점검 | 확인 |
| `07-monitor-log.png` | 로그 누적 및 파일 권한 | 확인 |
| `08-log-rotation.png`, `08-log-test-code.png` | 회전 테스트 방법, 최대 10개, 압축 무결성, MEM 경고 | 확인 |
| `09-cron-registration.png` | agent-admin의 crontab 등록 내용 | 별도 캡처 추가 필요 |
| `10-cron-log-growth.png` | UTC 상태의 자동 누적 | 확인 |
| `10-cron-log-growth-korea-time.png` | KST 변경 후 7줄 → 9줄 증가 | 확인 |
| `11-process-failure.png` | 앱 중단 시 종료 코드 1 | 확인 |
| `12-port-failure.png` | 복사본의 포트 실패 시 종료 코드 1 | 확인 |
| `13-firewall-warning.png` | 비활성 경고·종료 코드 0·UFW 재활성화 | 확인 |

- [x] SSH 포트 20022 및 Root 원격 로그인 차단 설정 확인
- [x] 일반 계정의 SSH 접속 확인
- [x] UFW 활성화 및 TCP 20022·15034 허용 규칙 확인
- [x] 계정·그룹, 디렉토리 권한·ACL, 역할별 접근 확인
- [x] monitor.sh의 agent-dev:agent-core 소유 관계 및 750 권한 확인
- [x] 앱 Boot Sequence 5단계 OK 및 Agent READY 확인
- [x] 앱의 0.0.0.0:15034 LISTEN 확인
- [x] monitor 실행 결과, 경고 및 실패 종료 코드 확인
- [x] monitor.log 누적과 회전·압축·보관 개수 확인
- [x] cron에 의한 매분 자동 로그 증가 확인
- [ ] agent-admin의 crontab 등록 화면을 증거 파일로 추가

등록 증거는 root 터미널에서 다음 출력으로 캡처한다.

```bash
crontab -u agent-admin -l
service cron status
ls -l /home/agent-admin/agent-app/bin/monitor.sh
```

## 11. 운영 및 학습 정리

- 필요한 포트만 열면 외부에서 접근할 수 있는 서비스 범위를 줄일 수 있다. SSH 포트 변경만으로 인증 보안을 대신할 수는 없다.
- 공통 그룹과 핵심 그룹을 분리하면 테스트 계정의 협업 공간을 유지하면서 키·운영 로그 접근은 제한할 수 있다. 상위 디렉토리 통과 권한까지 함께 설계해야 한다.
- 환경 변수는 실행 경로를 일관되게 지정하는 수단이다. 명세와 제공 앱의 실제 검사 조건이 다른 경우 오류 출력과 Boot Sequence를 근거로 차이를 기록해야 한다.
- 프로세스와 포트 점검은 서비스 실행 상태를, 자원 로그는 시각별 시스템 상태를 확인하게 해 준다. 현재 스크립트는 건강 점검 실패 시 즉시 종료하므로 그 실패는 콘솔에 남고 자원 로그는 추가되지 않는다.
- cron은 수동 점검을 주기 수집으로 바꾸며, 회전·압축·삭제 정책은 장기 누적 로그의 용량을 관리한다. 경고와 실패 종료를 구분하면 방화벽 경고 중에도 측정 기록을 유지할 수 있다.

이 컨테이너는 `sleep infinity`를 주 프로세스로 사용하는 실습 환경이다. 컨테이너를 재시작하면 SSH·cron 서비스와 앱의 실행 상태를 다시 확인하고 필요한 서비스를 시작해야 한다. UFW 상태도 다시 확인한다. 앱은 일반 계정으로 재실행한다.

```bash
# root: 컨테이너 재시작 후 점검·복구
mkdir -p /run/sshd
service ssh start
service cron start
ufw status verbose

# SSH agent-admin: 앱 실행
source /etc/profile.d/agent-app.sh
cd "$AGENT_HOME"
./agent-app-linux-arm64
```
