# controlbit_uwb_rtos

Real-time location tracking (RTLS) dashboard for UWB (Ultra-Wideband) anchor boards.
Receives range measurements from UWB hardware over MQTT, computes tag positions via least-squares trilateration, and visualizes them on a Flutter-based interactive map.

## Features

- **Real-time MQTT ingest** — automatic transport selection per platform: raw TCP for mobile/desktop, WebSocket (TLS) for web
- **Anchor management UI** — per-anchor coordinates, range-array index, and calibration offset; persisted via `SharedPreferences`
- **Position estimation** — least-squares trilateration (≥3 anchors) with median-based outlier rejection that is unit-agnostic (works with cm, mm, m)
- **Interactive map** — `CustomPainter` rendering with grid, anchor/tag markers, dashed range lines, and live distance labels
- **Pan / zoom / drag** — pan and zoom the map; toggle edit mode to drag anchors with the mouse and update their coordinates in place
- **Connection setup UI** — first-launch form for broker host, ports, TLS, and topic; last-used values auto-populate

## Data format

The firmware publishes to MQTT topic `uwb/range/{src}` with the following JSON payload:

```json
{
  "src": "A0",
  "mac": "020471167d78",
  "id": 0,
  "range": [482, 66, 360, 0, 0, 0, 0, 0]
}
```

| Field | Meaning |
|---|---|
| `src` | Anchor identifier (e.g., `A0`, `A1`) |
| `mac` | Device MAC address |
| `id` | Tag ID being ranged |
| `range[i]` | Distance from **anchor at index `i`** to the tag. Unit is firmware-defined (cm or mm); the dashboard works with either. A value of `0` means "no measurement from that anchor". |

## Project structure

```
lib/
├── main.dart                       # App entry. Provider root + screen routing.
├── models/
│   ├── mqtt_config.dart            # Broker config + load/save.
│   └── anchor.dart                 # Anchor (src, index, x, y, calibration) + load/save.
├── mqtt/
│   └── mqtt_manager.dart           # MQTT client (kIsWeb branch, MQTT 3.1.1).
├── providers/
│   └── position_provider.dart      # ChangeNotifier. Wires MQTT ingest to position computation.
├── services/
│   └── trilateration.dart          # LS trilateration + robust outlier rejection.
└── screens/
    ├── connection_screen.dart      # Broker input form (shown on cold start).
    ├── dashboard_screen.dart       # Main dashboard (Map / Data tabs).
    ├── map_view.dart               # Map visualization, zoom/pan, drag-to-edit.
    └── anchor_setup_screen.dart    # Anchor coordinate / index / calibration form.
```

## Getting started

### 1. Install dependencies

```sh
flutter pub get
```

### 2. Configure the MQTT broker

The first launch presents a connection form. Sample values:

| Field | HiveMQ public broker | Private Mosquitto |
|---|---|---|
| Host | `broker.hivemq.com` | `192.168.0.10` |
| TCP port | `1883` (or `8883` for TLS) | `1883` |
| WebSocket port | `8884` (TLS) | `9001` |
| WS path | `/mqtt` | `/` |
| TLS | ON | OFF |
| Topic | `uwb/range/+` | `uwb/range/+` |

Web builds **must** use WebSocket due to browser sandbox restrictions. TLS (`wss://`) is recommended in production.

### 3. Register anchors

Tap the 📍 icon in the dashboard app bar. Add at least three anchors before position estimation can run.

| Field | Description |
|---|---|
| `src` | Identifier — must match the device payload's `src` (e.g., `A0`) |
| `idx` | Index into the `range[]` array (0–7). Auto-derived from trailing digits in `src`. |
| `X`, `Y` | Anchor coordinates in the same unit as the device's range values |
| `cal` | Calibration offset. Effective distance = `range[idx] + cal`. Use negative to subtract. |

Saving (or pressing back) auto-saves the configuration and recomputes positions for all known tags.

### 4. Run

```sh
flutter run -d chrome    # web
flutter run -d windows   # desktop
flutter run -d android   # Android
```

## Position estimation

### Least-squares trilateration

Ported from the reference WPF implementation (`SolveLsTrilateration`) into Dart. With three or more anchor distances, the system solves the linearized equations:

```
2(xi − x0)·X + 2(yi − y0)·Y = (xi² + yi² − di²) − (x0² + y0² − d0²)
```

The system is solved in a coordinate frame translated so that the first anchor sits at the origin (improves floating-point conditioning when absolute coordinates are large), then the result is shifted back to the input frame.

### Robust outlier rejection

Plain LS is sensitive to a single bad measurement (e.g., a multipath spike). After the initial solve, the dashboard:

1. Computes per-anchor residuals `|‖p̂ − aᵢ‖ − dᵢ|`
2. Identifies the largest residual `r_max` and the median `r_med`
3. If `r_max > 3·r_med`, the corresponding anchor is dropped as an outlier and the system is re-solved
4. Iterates until either residuals are consistent or fewer than four anchors remain

This rule is scale-invariant — it works with cm, mm, or any unit without configuration.

## Dashboard usage

| Tab | Contents |
|---|---|
| **Map** | Anchors as blue squares, tags as cyan circles. Top-right toggles for distance lines and anchor edit mode. Bottom-right zoom controls. |
| **Data** | Per-anchor latest reading cards + per-tag table grouped by anchor + computed `(x, y)`. |

The status bar at the top shows the live MQTT state plus three counters: `anchors / tags / positioned`. If `positioned` stays at `0` while `tags ≥ 1`, the issue is usually unit mismatch, an outlier, or `src`/`idx` mapping.

## Debugging

Open Chrome DevTools (F12) → **Console**. Useful log lines:

```
[MQTT] connecting → wss://broker.hivemq.com:8884/mqtt
[MQTT] connected, subscribing → uwb/range/+
[MQTT] uwb/range/A0: {"src":"A0",...}
[Trilat] in: (0,0,d=482) (500,0,d=66) (0,500,d=360) → out: (...)
[Trilat] outlier reject: (500.0,0.0) d=66.0 residual=... (median=...)
```

## Dependencies

- [`mqtt_client ^10.5.1`](https://pub.dev/packages/mqtt_client) — MQTT 3.1.1 (explicitly forced for HiveMQ compatibility)
- [`provider ^6.1.2`](https://pub.dev/packages/provider) — state management
- [`shared_preferences ^2.3.0`](https://pub.dev/packages/shared_preferences) — persistent settings (broker, anchors)

## License

TBD.
