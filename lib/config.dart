/// Default hub address used when no hub URL has been entered or discovered.
/// Override at build time: `flutter run --dart-define=HUB_URL=http://10.0.0.5:9000`
const String kDefaultHubUrl =
    String.fromEnvironment('HUB_URL', defaultValue: 'http://192.168.100.100:9000');

/// Shown at the bottom of Settings.
const String kAppVersion = '1.0.0';
const String kAppName = 'SmartHomes';
const String kCompanyTagline = 'Centralized control for your ESP32 mesh network.';
