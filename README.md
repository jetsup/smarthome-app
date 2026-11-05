# smarthome-app

SmartHomes — Flutter Android app for the SmartHome hub: sign in (with two-step verification), add gateways over Bluetooth, activate and control nodes, edit modules/NeoPixel patterns, manage displays (pairing by QR, theme/background/RGB LED), view the activity log, approve web sign-ins from your phone.

## Installation

### Prerequisites

- **Flutter** (Dart SDK ≥ 3.8; `flutter doctor` must be green for Android)
- **JDK 17 or 21** (Flutter's bundled JDK 25 breaks Gradle 8.x: `flutter config --jdk-dir=/usr/lib/jvm/java-21-openjdk-amd64`)
- Android SDK with the platforms/build-tools that `flutter doctor` asks for
- An Android phone (USB debugging or wireless debugging) on the **same Wi-Fi as the hub**

### ⚠️ Set your hub address

The app starts with a default hub URL of `http://192.168.100.100:9000` — the author's network. Set yours when you build:

```bash
flutter pub get
flutter run --dart-define=HUB_URL=http://192.168.1.50:9000          # debug on a connected phone
flutter build apk --release --dart-define=HUB_URL=http://192.168.1.50:9000
```

(or edit `kDefaultHubUrl` in `lib/config.dart`). The hub address is **fixed per build** — there is no screen to type it — so rebuild if the hub's IP changes (give the hub a fixed IP). On your home Wi-Fi the app also discovers gateways automatically (mDNS) when the phone allows local-network access.

### Install on a phone

```bash
flutter build apk --debug --dart-define=HUB_URL=http://<HUB_IP>:9000
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

If `adb install` stalls over wireless debugging (the debug APK is ~200 MB), `adb push` the APK to `/data/local/tmp/` and run `adb shell pm install -r /data/local/tmp/app-debug.apk`. A release build is much smaller.

### Permissions the app asks for

Camera (scan display QR codes), Bluetooth/nearby devices (add a gateway), notifications (gateway offline alerts), local network. The hub is plain `http://` on your LAN, which the app allows.

## First run

1. Open the app → sign in with the account you registered on the web UI (or register).
2. Menu → **Add a gateway** to link a new gateway over Bluetooth; **Set up HMI Wi-Fi** / **Pair a display** for touch displays.
3. Open a gateway → **Discover nodes**, activate them and pick their modules and pins.
4. Settings has the Auto/Light/Dark theme and accent colour. On phones the app stays in portrait; tablets may rotate.

## Project layout

`lib/screens/` pages, `lib/widgets/` shared widgets (capability editor, module controls), `lib/services/` API, discovery, catalog, `lib/theme/` colours (`context.c.*`), `lib/config.dart` hub URL and app name.
