# controlbit_uwb_rtos

UWB(Ultra-Wideband) 앵커 보드용 실시간 위치 추적(RTLS) 대시보드.
하드웨어가 MQTT로 publish하는 거리 측정값을 받아 LS Trilateration으로 태그 위치를 계산하고, Flutter 기반 UI에서 지도 위에 시각화합니다.

## 주요 기능

- **MQTT 실시간 수신** — TCP(모바일/데스크톱) / WebSocket TLS(웹) 자동 분기
- **앵커 관리** — UI에서 앵커별 좌표·인덱스·캘리브레이션 입력, SharedPreferences로 자동 저장
- **위치 계산** — Least Squares Trilateration (앵커 ≥3개), median 기반 outlier 자동 제거
- **시각화** — CustomPainter 지도, 앵커/태그 마커, 거리 점선 + 라벨
- **인터랙션** — 줌/팬, 앵커 마우스 드래그로 좌표 재배치
- **연결 설정 UI** — 브로커 호스트·포트·TLS·토픽 입력, 마지막 값 자동 로딩

## 데이터 포맷

디바이스가 MQTT 토픽 `uwb/range/{src}` 로 publish:

```json
{
  "src": "A0",
  "mac": "020471167d78",
  "id": 0,
  "range": [482, 66, 360, 0, 0, 0, 0, 0]
}
```

- `src` — 앵커 식별자 (예: `A0`, `A1`)
- `id` — 측정 대상 태그 ID
- `range[i]` — **인덱스 `i`의 앵커**에서 태그까지의 거리 (단위는 펌웨어 의존; cm/mm 모두 지원)

## 프로젝트 구조

```
lib/
├── main.dart                       # 앱 엔트리. Provider 루트, 화면 분기
├── models/
│   ├── mqtt_config.dart            # 브로커 설정 + load/save
│   └── anchor.dart                 # 앵커 모델 (src, index, x, y, calibration) + load/save
├── mqtt/
│   └── mqtt_manager.dart           # MQTT 연결 (kIsWeb으로 TCP/WS 분기, MQTT 3.1.1 강제)
├── providers/
│   └── position_provider.dart      # ChangeNotifier. 메시지 수신 → 위치 계산 → notify
├── services/
│   └── trilateration.dart          # LS Trilateration + outlier rejection
└── screens/
    ├── connection_screen.dart      # 브로커 입력 폼 (앱 시작시)
    ├── dashboard_screen.dart       # 메인 대시보드 (Map / Data 탭)
    ├── map_view.dart               # 지도 시각화 + 줌/팬/드래그
    └── anchor_setup_screen.dart    # 앵커 좌표/인덱스/캘리브 입력
```

## 설정

### 1. 의존성 설치

```sh
flutter pub get
```

### 2. MQTT 브로커 설정

앱 실행 시 첫 화면에서 직접 입력:

| 항목 | 예 (HiveMQ public) | 예 (사설 Mosquitto) |
|---|---|---|
| Host | `broker.hivemq.com` | `192.168.0.10` |
| TCP Port | `1883` (또는 TLS `8883`) | `1883` |
| WS Port | `8884` (TLS) | `9001` |
| WS Path | `/mqtt` | `/` |
| TLS | ON | OFF |
| Topic | `uwb/range/+` | `uwb/range/+` |

웹 빌드는 브라우저 보안 제약상 **반드시 WebSocket** 사용. 운영 시 TLS(`wss://`) 권장.

### 3. 앵커 등록

대시보드 우측 상단 📍 아이콘 → 좌표 입력. 최소 3개 등록되면 위치 계산이 시작됩니다.

| 필드 | 의미 |
|---|---|
| src | 디바이스 페이로드의 src와 동일하게 (예: `A0`) |
| idx | range[] 배열에서 이 앵커의 인덱스 (0~7). src 끝 숫자 자동 추출 |
| X, Y | 앵커 위치 좌표 (range와 같은 단위) |
| cal | 거리 보정값. 실제 거리 = `range[idx] + cal` |

저장(💾) 또는 뒤로가기 → 자동 저장 후 모든 태그 위치 재계산.

### 4. 실행

```sh
flutter run -d chrome    # 웹
flutter run -d windows   # 데스크톱
flutter run -d android   # 안드로이드
```

## 위치 계산

### LS Trilateration

레퍼런스 WPF 프로젝트의 `SolveLsTrilateration`을 Dart로 포팅. 최소 3개 앵커 거리에서 다음 정규방정식을 푼다:

```
2(xi - x0)·X + 2(yi - y0)·Y = (xi² + yi² - di²) - (x0² + y0² - d0²)
```

수치 안정성을 위해 첫 앵커를 origin으로 평행이동 후 푼 뒤 origin을 더해 복원.

### Outlier 제거

LS는 측정 outlier 1개에도 결과가 크게 흔들리는 약점이 있어, 후처리로 잔차 기반 robust filter를 추가:

1. LS 결과로 각 앵커의 추정거리 계산
2. 측정거리와의 잔차 |est - measured| 산출
3. 최대 잔차가 **median × 3배 초과**면 그 앵커를 outlier로 판정해 제거
4. 남은 앵커가 ≥3개일 때까지 반복 (단위 무관, mm/cm 모두 동작)

## 대시보드 사용

- **Map 탭**: 앵커(파란 사각형) + 태그(시안 원). 우상단 토글로 거리 점선 표시 / 앵커 드래그 편집 모드
- **Data 탭**: 앵커별 최신 측정 카드 + 태그별 거리표 + 산출된 좌표
- **상단 STATUS 띠**: MQTT 연결 상태, anchors / tags / positioned 카운트

## 디버깅

Chrome DevTools(F12) → Console 탭에서 다음 로그 확인 가능:

```
[MQTT] connecting → wss://broker.hivemq.com:8884/mqtt
[MQTT] connected, subscribing → uwb/range/+
[MQTT] uwb/range/A0: {"src":"A0",...}
[Trilat] in: (0,0,d=482) (500,0,d=66) (0,500,d=360) → out: (...)
[Trilat] outlier reject: (500.0,0.0) d=66.0 residual=... (median=...)
```

## 의존성

- `mqtt_client ^10.5.1` — MQTT v3.1.1 (HiveMQ 호환을 위해 명시 강제)
- `provider ^6.1.2` — 상태 관리
- `shared_preferences ^2.3.0` — 브로커/앵커 설정 영속화
