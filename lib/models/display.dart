/// A paired HMI touch display.
class Display {
  final int id;
  final String slug;
  final String name;
  final String deviceId;
  final String gatewayId;
  final String gatewayName;
  final bool online;
  final bool gatewayOnline;
  final int nodeCount;
  final String? lastSeen;

  const Display({
    required this.id,
    required this.slug,
    required this.name,
    required this.deviceId,
    required this.gatewayId,
    required this.gatewayName,
    this.online = false,
    this.gatewayOnline = false,
    this.nodeCount = 0,
    this.lastSeen,
  });

  factory Display.fromJson(Map<String, dynamic> j) => Display(
        id: j['id'] as int? ?? 0,
        slug: j['slug'] as String? ?? '',
        name: j['name'] as String? ?? 'Display',
        deviceId: j['deviceId'] as String? ?? '',
        gatewayId: j['gatewayId'] as String? ?? '',
        gatewayName: j['gatewayName'] as String? ?? '',
        online: j['online'] as bool? ?? false,
        gatewayOnline: j['gatewayOnline'] as bool? ?? false,
        nodeCount: j['nodeCount'] as int? ?? 0,
        lastSeen: j['lastSeen'] as String?,
      );

  /// Last 4 characters of the hardware id: matches the "Display XXXX" shown on the screen.
  String get shortId => deviceId.length >= 4 ? deviceId.substring(deviceId.length - 4) : deviceId;
}

/// A node as seen from a display's detail: who (if anyone) shows it.
class DisplayNode {
  final int deviceId;
  final String name;
  final bool isOnline;
  final int? hmiId;
  final String hmiName;
  const DisplayNode(this.deviceId, this.name, this.isOnline, this.hmiId, this.hmiName);

  factory DisplayNode.fromJson(Map<String, dynamic> j) => DisplayNode(
        j['deviceId'] as int? ?? 0,
        j['name'] as String? ?? '',
        j['isOnline'] as bool? ?? false,
        j['hmiId'] as int?,
        j['hmiName'] as String? ?? '',
      );
}

/// What the display's QR code says: `SHHMI1;c=<code>;d=<device id>`.
class DisplayQr {
  final String code;
  final String deviceId;
  const DisplayQr(this.code, this.deviceId);

  static DisplayQr? parse(String raw) {
    if (!raw.startsWith('SHHMI1;')) return null;
    String? c, d;
    for (final part in raw.split(';').skip(1)) {
      final i = part.indexOf('=');
      if (i < 0) continue;
      final k = part.substring(0, i), v = part.substring(i + 1);
      if (k == 'c') c = v;
      if (k == 'd') d = v;
    }
    if (c == null || c.length != 6) return null;
    return DisplayQr(c, d ?? '');
  }
}
