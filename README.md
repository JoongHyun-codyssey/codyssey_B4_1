# Linux 서버 보안 설정 및 시스템 관제 자동화

리눅스 서버에 역할별 계정과 접근 권한을 구성하고, 애플리케이션 상태와 시스템 자원을 주기적으로 확인하는 프로젝트입니다. Bash 스크립트로 점검 결과를 기록하고, cron을 통해 모니터링을 자동화합니다.

> 이 문서는 수행 내역서 초안입니다. 아래 설정은 적용할 목표이며, 실제 수행 후 `[작성 필요]` 부분과 증거 자료를 채웁니다. 완료한 항목만 체크합니다.

## 1. 프로젝트 목표

- SSH 포트 변경과 Root 원격 로그인 차단으로 기본 보안을 설정합니다.
- 방화벽에서 필요한 포트만 허용합니다.
- 계정, 그룹, ACL로 공유 공간과 보안 공간의 접근 권한을 구분합니다.
- 환경 변수로 제공 Python 앱의 실행 환경을 구성합니다.
- Bash 스크립트로 프로세스, 포트, 자원 사용률을 확인하고 로그를 남깁니다.
- cron으로 매분 점검하고, 로그 용량과 보관 개수를 관리합니다.

## 2. 개발 및 실행 환경

| 항목 | 구성 |
| --- | --- |
| 운영체제 | Ubuntu 22.04 LTS 또는 동등 리눅스 환경 |
| 실습 방식 | [작성 필요: VM / 컨테이너 / 기타] |
| 자동화 언어 | Bash |
| 실행 대상 | 제공된 Python 애플리케이션 |
| 앱 파일명 | `agent_app.py` — 제공 파일명이 다르면 문서와 스크립트에 반영 |
| 방화벽 | UFW 사용 예정 — 실제 선택에 맞게 수정 |
| SSH 포트 | TCP 20022 |
| 앱 포트 | TCP 15034 |
| cron 실행 계정 | `agent-admin` |

## 3. 제출물 및 저장소 구성

최종 제출물은 수행 내역서인 `README.md`와 자동화 스크립트인 `monitor.sh`입니다. 아래는 저장소 구성 예시입니다.

| 경로 | 용도 |
| --- | --- |
| `README.md` | 설정, 명령어, 검증 결과 및 증거 자료 기록 |
| `monitor.sh` | 제출용 Bash 모니터링 스크립트 |
| `docs/screenshots/` | 설정 및 실행 결과 캡처 |

서버에 배치하는 스크립트의 실제 경로는 `$AGENT_HOME/bin/monitor.sh`입니다.

## 4. 기본 보안 및 네트워크 설정

### 4.1 SSH 설정

SSH 포트를 `20022`로 변경하고, Root 계정의 원격 로그인을 차단합니다.

```text
Port 20022
PermitRootLogin no
```

| 기록 항목 | 수행 내역 |
| --- | --- |
| 수정한 설정 파일 | [작성 필요] |
| 설정 변경 명령어 | [작성 필요] |
| 문법 검사 및 설정 적용 명령어 | [작성 필요] |
| 실제 적용된 SSH 포트 | [작성 필요] |
| Root 원격 로그인 차단 확인 | [작성 필요] |
| 일반 계정의 20022 포트 접속 확인 | [작성 필요] |

확인 명령어 예시:

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin) '
sudo ss -tlnp
```

- 실제 출력: [작성 필요]
- 증거 자료: `docs/screenshots/01-ssh.png` 추가 예정

### 4.2 방화벽 설정

UFW를 활성화하고, 인바운드는 TCP `20022`와 TCP `15034`만 허용하도록 구성합니다.

| 방향 | 포트 | 정책 | 용도 |
| --- | --- | --- | --- |
| 인바운드 | 20022/tcp | 허용 | SSH 접속 |
| 인바운드 | 15034/tcp | 허용 | 앱 접속 |
| 인바운드 | 그 외 | 차단 | 불필요한 접근 제한 |

- 실행한 설정 명령어: [작성 필요]
- 기존 허용 규칙 정리 내역: [작성 필요]
- 활성화 및 최종 규칙 확인: [작성 필요]

```bash
sudo ufw status verbose
sudo ufw status numbered
```

- 실제 출력: [작성 필요]
- 증거 자료: `docs/screenshots/02-firewall.png` 추가 예정

## 5. 계정, 그룹 및 디렉토리 권한

### 5.1 계정과 그룹

| 계정 | 역할 | 소속 그룹 |
| --- | --- | --- |
| `agent-admin` | 운영·관리 및 cron 실행 | `agent-common`, `agent-core` |
| `agent-dev` | 개발·운영 및 monitor.sh 작성 | `agent-common`, `agent-core` |
| `agent-test` | QA·테스트 | `agent-common` |

- 계정 생성 명령어: [작성 필요]
- 그룹 생성 및 그룹 가입 명령어: [작성 필요]

```bash
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core
```

- 실제 출력: [작성 필요]
- 증거 자료: `docs/screenshots/03-users-groups.png` 추가 예정

### 5.2 디렉토리 구조와 접근 정책

이 초안에서는 `AGENT_HOME=/home/agent-admin/agent-app`을 기준으로 작성합니다.

| 경로 | 그룹 및 접근 정책 |
| --- | --- |
| `$AGENT_HOME` | 필요한 계정이 하위 경로에 접근할 수 있도록 구성 |
| `$AGENT_HOME/upload_files` | `agent-common` 구성원 읽기·쓰기 가능 |
| `$AGENT_HOME/api_keys` | `agent-core` 구성원만 읽기·쓰기 가능 |
| `/var/log/agent-app` | `agent-core` 구성원만 읽기·쓰기 가능 |
| `$AGENT_HOME/bin/monitor.sh` | 소유자 `agent-dev`, 그룹 `agent-core`, 권한 `750` |

디렉토리에 접근하려면 상위 경로와 해당 디렉토리에 실행(`x`) 권한도 필요합니다. `/home/agent-admin`을 포함한 상위 경로의 통과 권한까지 확인합니다.

- 디렉토리 생성 및 소유자·그룹 변경 명령어: [작성 필요]
- 일반 권한 설정 명령어: [작성 필요]
- ACL 및 기본 ACL 설정 명령어: [작성 필요]
- 새로 생성한 파일의 그룹·접근 권한 확인: [작성 필요]

```bash
ls -ld /home/agent-admin "$AGENT_HOME" "$AGENT_HOME/bin" \
  "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" /var/log/agent-app
ls -l "$AGENT_HOME/bin/monitor.sh"
getfacl /home/agent-admin "$AGENT_HOME" "$AGENT_HOME/upload_files" \
  "$AGENT_HOME/api_keys" /var/log/agent-app
```

| 검증 항목 | 기대 결과 | 실제 결과 |
| --- | --- | --- |
| admin/dev/test의 upload_files 읽기·쓰기 | 허용 | [작성 필요] |
| admin/dev의 api_keys 및 로그 디렉토리 읽기·쓰기 | 허용 | [작성 필요] |
| test의 api_keys 및 로그 디렉토리 접근 | 거부 | [작성 필요] |
| admin의 monitor.sh 실행 | 허용 | [작성 필요] |
| test의 monitor.sh 실행 | 거부 | [작성 필요] |

- 실제 출력 및 접근 테스트 명령어: [작성 필요]
- 증거 자료: `docs/screenshots/04-permissions-acl.png` 추가 예정

## 6. 애플리케이션 실행 환경

### 6.1 환경 변수

```bash
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys/t_secret.key"
export AGENT_LOG_DIR=/var/log/agent-app
```

- 환경 변수를 저장한 파일과 적용 명령어: [작성 필요]
- 새 세션에서 환경 변수 유지 확인: [작성 필요]

### 6.2 키 파일

| 항목 | 값 |
| --- | --- |
| 경로 | `$AGENT_HOME/api_keys/t_secret.key` |
| 내용 | `agent_api_key_test` 한 줄 |
| 접근 정책 | `agent-core` 구성원만 읽기·쓰기 가능 |

- 생성 및 권한 설정 명령어: [작성 필요]

### 6.3 일반 계정으로 앱 실행

`agent-admin` 등 일반 계정에서 실행합니다. 제공 앱 파일명이 다르면 실행 명령어를 수정합니다.

```bash
cd "$AGENT_HOME"
python3 agent_app.py
```

| Boot Sequence | 성공 기준 | 실제 결과 |
| --- | --- | --- |
| 1. 계정 확인 | 일반 계정 실행 및 `[OK]` | [작성 필요] |
| 2. 환경 변수 확인 | 필요한 값 확인 및 `[OK]` | [작성 필요] |
| 3. 필수 파일 확인 | 키 파일과 내용 확인 및 `[OK]` | [작성 필요] |
| 4. 포트 가용성 확인 | 15034 포트 사용 가능 및 `[OK]` | [작성 필요] |
| 5. 로그 권한 확인 | 로그 디렉토리 쓰기 가능 및 `[OK]` | [작성 필요] |

- 마지막 `Agent READY` 출력: [작성 필요]
- `0.0.0.0:15034` LISTEN 확인: [작성 필요]
- 실제 실행 계정 및 출력: [작성 필요]
- 증거 자료: `docs/screenshots/05-app-ready.png` 추가 예정

앱 실행 터미널을 유지하고 별도 터미널에서 관제를 검증합니다. 앱은 `Ctrl+C`로 종료합니다.

## 7. 시스템 관제 스크립트

### 7.1 파일 배치 및 실행

| 항목 | 설정 |
| --- | --- |
| 서버 경로 | `$AGENT_HOME/bin/monitor.sh` |
| 소유자 | `agent-dev` |
| 그룹 | `agent-core` |
| 권한 | `750` (`rwxr-x---`) |
| 자동 실행 계정 | `agent-admin` |

`agent-admin` 계정에서 수동 실행합니다.

```bash
/home/agent-admin/agent-app/bin/monitor.sh
echo "종료 코드: $?"
```

### 7.2 점검 항목과 처리 기준

| 구분 | 점검 내용 | 처리 |
| --- | --- | --- |
| 프로세스 | 제공 앱 프로세스 실행 여부 | 비정상 시 `exit 1` |
| 포트 | TCP 15034 LISTEN 여부 | 비정상 시 `exit 1` |
| 방화벽 | 선택한 방화벽의 활성화 여부 | 비활성 시 `[WARNING]`, 계속 실행 |
| CPU | 시스템 CPU 사용률 | 20% 초과 시 `[WARNING]`, 계속 실행 |
| 메모리 | 시스템 메모리 사용률 | 10% 초과 시 `[WARNING]`, 계속 실행 |
| 디스크 | 루트 파티션(`/`) 사용률 | 80% 초과 시 `[WARNING]`, 계속 실행 |

- 프로세스 및 포트 확인 방식: [작성 필요]
- CPU 측정 방식과 측정 간격: [작성 필요]
- 메모리 사용률 계산 기준: [작성 필요]
- 방화벽 상태 조회 방법 및 필요한 권한: [작성 필요]
- 실패 메시지·경고 메시지와 종료 코드 확인: [작성 필요]

### 7.3 로그 기록

로그 파일은 `/var/log/agent-app/monitor.log`이며 다음 형식으로 누적합니다.

```text
[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
```

확인 명령어:

```bash
tail -n 10 /var/log/agent-app/monitor.log
```

- monitor.sh 실제 콘솔 출력: [작성 필요]
- 누적 로그의 최근 라인: [작성 필요]
- 증거 자료: `docs/screenshots/06-monitor-result.png`, `docs/screenshots/07-monitor-log.png` 추가 예정

### 7.4 로그 용량 및 보관 정책

| 항목 | 정책 |
| --- | --- |
| 파일 크기 기준 | 10MB |
| 보관 개수 | 최대 10개 파일 |
| 구현 방식 | [작성 필요: logrotate / Bash 로직] |
| 보관 개수 산정 | [작성 필요: 현재 로그 포함 여부 및 실제 최대 개수] |
| 오래된 로그 처리 | [작성 필요: 압축·삭제 방식] |

- 관련 설정 파일 또는 스크립트 로직: [작성 필요]
- 크기 초과 시 회전·압축·삭제 검증 결과: [작성 필요]
- 증거 자료: `docs/screenshots/08-log-rotation.png` 추가 예정

크기 기준을 언제 검사하는지와 실제 최대 보관 개수를 명시하고, 과제의 10MB/10개 제한에 맞게 검증합니다.

## 8. cron 자동 실행

`agent-admin` 계정의 crontab에 매분 실행 규칙을 등록합니다. 아래는 실행 경로 예시입니다.

```cron
* * * * * /home/agent-admin/agent-app/bin/monitor.sh
```

cron 환경에서는 대화형 셸의 환경 변수를 그대로 사용할 수 있다고 가정하지 않습니다. 스크립트 내부 또는 별도 설정 파일에서 필요한 경로와 환경 변수를 준비합니다.

- cron에 적용한 환경 변수 및 PATH 설정: [작성 필요]
- 실제 등록한 crontab 내용: [작성 필요]

`agent-admin` 계정에서 등록 상태를 확인합니다.

```bash
crontab -l
wc -l /var/log/agent-app/monitor.log
tail -n 5 /var/log/agent-app/monitor.log
```

수동 실행을 멈춘 상태에서 1~2분 뒤 같은 명령어로 로그를 다시 확인합니다. 검증 중 로그가 회전했다면 회전된 파일도 함께 확인합니다.

| 확인 시점 | 확인 시각 | 로그 줄 수 | 마지막 로그 시각 |
| --- | --- | --- | --- |
| 자동 실행 확인 전 | [작성 필요] | [작성 필요] | [작성 필요] |
| 1~2분 후 | [작성 필요] | [작성 필요] | [작성 필요] |

- 자동 실행 검증 결과: [작성 필요]
- 증거 자료: `docs/screenshots/09-cron-registration.png`, `docs/screenshots/10-cron-log-growth.png` 추가 예정

## 9. 기능 검증 기록

| 검증 상황 | 기대 결과 | 실제 결과 |
| --- | --- | --- |
| 앱이 정상 실행 중 | 프로세스·포트 정상 확인, 자원 수집 및 로그 기록 | [작성 필요] |
| 앱 프로세스 없음 | 실패 메시지 출력 및 종료 코드 1 | [작성 필요] |
| 프로세스는 있으나 15034 LISTEN 없음 | 실패 메시지 출력 및 종료 코드 1 | [작성 필요] |
| 방화벽 비활성 | `[WARNING]` 출력 후 자원 수집·로그 기록 계속 | [작성 필요] |
| CPU > 20% | `[WARNING]` 출력 후 계속 실행 | [작성 필요] |
| MEM > 10% | `[WARNING]` 출력 후 계속 실행 | [작성 필요] |
| DISK_USED > 80% | `[WARNING]` 출력 후 계속 실행 | [작성 필요] |
| 로그 크기·개수 제한 도달 | 설정한 보관 정책대로 회전·정리 | [작성 필요] |
| cron 등록 후 1~2분 경과 | 새 시각의 로그 자동 누적 | [작성 필요] |

실제로 재현한 상황과 사용한 검증 방법을 기록합니다. 아직 확인하지 못한 항목은 미검증으로 표시합니다.

## 10. 필수 증거 자료 체크리스트

- [ ] SSH 포트 20022 및 Root 원격 로그인 차단 설정 확인
- [ ] SSH 포트 리슨 및 일반 계정 접속 확인
- [ ] 방화벽 활성화 및 20022/tcp, 15034/tcp만 허용 확인
- [ ] agent-admin/dev/test 계정 및 agent-common/core 그룹 확인
- [ ] 디렉토리 구조, 소유자·그룹, 권한 및 ACL 확인
- [ ] 역할별 접근 허용·거부 확인
- [ ] monitor.sh의 agent-dev:agent-core 소유 관계 및 750 권한 확인
- [ ] 앱 Boot Sequence 5단계 `[OK]` 및 `Agent READY` 확인
- [ ] 앱의 `0.0.0.0:15034` LISTEN 확인
- [ ] monitor.sh 실행 결과의 프로세스·포트·리소스·경고 확인
- [ ] monitor.log 최근 라인 및 누적 기록 확인
- [ ] 로그 10MB/10개 보관 정책과 정리 동작 확인
- [ ] agent-admin crontab 매분 실행 등록 확인
- [ ] 1~2분 후 로그가 자동으로 증가한 증거 확인

## 11. 문제 해결 기록

| 발생한 문제 | 원인 | 해결 방법 | 재검증 결과 |
| --- | --- | --- | --- |
| [작성 필요] | [작성 필요] | [작성 필요] | [작성 필요] |

## 12. 학습 정리

수행한 설정과 검증 결과를 바탕으로 아래 내용을 정리합니다.

- SSH 포트 변경과 Root 원격 로그인 차단의 목적: [작성 필요]
- 필요한 포트만 허용하는 방화벽 정책의 의미: [작성 필요]
- 공유 디렉토리와 보안 디렉토리를 분리한 이유: [작성 필요]
- 그룹 권한과 ACL을 적용한 방식: [작성 필요]
- 환경 변수로 실행 환경을 고정한 이유와 검증 방법: [작성 필요]
- 상태 점검 → 로그 기록 → 장애 추적의 흐름: [작성 필요]
- cron 자동 실행 및 로그 보관 정책이 필요한 이유: [작성 필요]
