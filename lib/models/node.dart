import 'dart:convert';

class CapabilityConfig {
  final String type;
  final int pin;
  final int extra;
  final String label;
  final int? value;
  final int count; // NeoPixel LEDs
  final bool ring; // NeoPixel ring layout
  final int pin2; // second pin (I2C SCL / UART TX)
  final String display; // short live state text from the hub
  final String symbol; // icon picked on the website's dashboard (kept when the app saves)

  CapabilityConfig({
    required this.type,
    this.pin = 0,
    this.extra = 0,
    this.label = '',
    this.value,
    this.count = 0,
    this.ring = false,
    this.pin2 = 0,
    this.display = '',
    this.symbol = '',
  });

  factory CapabilityConfig.fromJson(Map<String, dynamic> json) {
    return CapabilityConfig(
      type: json['type'] as String? ?? '',
      pin: json['pin'] as int? ?? 0,
      extra: json['extra'] as int? ?? 0,
      label: json['label'] as String? ?? '',
      value: json['value'] as int?,
      count: json['count'] as int? ?? 0,
      ring: json['ring'] as bool? ?? false,
      pin2: json['pin2'] as int? ?? 0,
      display: json['display'] as String? ?? '',
      symbol: json['symbol'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'pin': pin,
    'extra': extra,
    'label': label,
    'count': count,
    'ring': ring,
    'pin2': pin2,
    if (symbol.isNotEmpty) 'symbol': symbol,
  };
}

/// One live sensor value (already scaled to real units by the hub).
class SensorReading {
  final int cap;
  final int channel;
  final String key;
  final String label;
  final String unit;
  final double value;
  const SensorReading(this.cap, this.channel, this.key, this.label, this.unit, this.value);

  factory SensorReading.fromJson(Map<String, dynamic> j) => SensorReading(
        j['cap'] as int? ?? 0,
        j['channel'] as int? ?? 0,
        j['key'] as String? ?? '',
        j['label'] as String? ?? '',
        j['unit'] as String? ?? '',
        (j['value'] as num?)?.toDouble() ?? 0,
      );
}

class SmartNode {
  final String nodeId;
  final int deviceId;
  final String gatewayId;
  final String? apiKey;
  final int deviceType;
  final int? capabilities;
  final int? value;
  final bool isOnline;
  final String? lastSeen;
  final String name;
  final List<CapabilityConfig> capabilitiesConfig;
  /// The one display this node is shown on (null = not assigned to any display).
  final int? hmiId;
  final List<SensorReading> readings;
  /// Last action settings per module index (e.g. the NeoPixel pattern in use).
  final Map<String, Map<String, dynamic>> effects;

  SmartNode({
    required this.nodeId,
    required this.deviceId,
    required this.gatewayId,
    this.apiKey,
    this.deviceType = 0,
    this.capabilities,
    this.value,
    this.isOnline = false,
    this.lastSeen,
    this.name = '',
    this.capabilitiesConfig = const [],
    this.hmiId,
    this.readings = const [],
    this.effects = const {},
  });

  factory SmartNode.fromJson(Map<String, dynamic> json) {
    List<CapabilityConfig> caps = [];
    if (json['capabilitiesConfig'] != null) {
      final raw = json['capabilitiesConfig'];
      if (raw is List) {
        caps = raw
            .map((e) => CapabilityConfig.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (raw is String && raw.isNotEmpty) {
        try {
          final decoded = _parseCapabilitiesJson(raw);
          caps = decoded;
        } catch (_) {}
      }
    }
    // Also parse from nested JSON string in capabilities_config
    if (caps.isEmpty && json['capabilities_config'] is String) {
      try {
        caps = _parseCapabilitiesJson(json['capabilities_config'] as String);
      } catch (_) {}
    }

    return SmartNode(
      nodeId: json['nodeId'] as String? ?? json['node_id'] as String? ?? '',
      deviceId: json['deviceId'] as int? ?? json['device_id'] as int? ?? 0,
      gatewayId: json['gatewayId'] as String? ?? json['gateway_id'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? json['api_key'] as String?,
      deviceType: json['deviceType'] as int? ?? json['device_type'] as int? ?? 0,
      capabilities: json['capabilities'] as int?,
      value: json['value'] as int? ?? json['lastValue'] as int? ?? json['last_value'] as int?,
      isOnline: json['isOnline'] as bool? ?? json['online'] as bool? ?? false,
      lastSeen: json['lastSeen'] as String? ?? json['last_seen'] as String?,
      name: json['name'] as String? ?? '',
      capabilitiesConfig: caps,
      hmiId: json['hmiId'] as int?,
      readings: ((json['readings'] as List?) ?? const [])
          .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
          .toList(),
      effects: ((json['effects'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map))),
    );
  }

  static List<CapabilityConfig> _parseCapabilitiesJson(String raw) {
    final list = List<Map<String, dynamic>>.from(
      const JsonDecoder().convert(raw) as List,
    );
    return list.map((e) => CapabilityConfig.fromJson(e)).toList();
  }

  String get typeLabel {
    const labels = {
      0: 'Unknown',
      1: 'Analog Sensor',
      2: 'Digital Sensor',
      3: 'Relay',
      4: 'IR Transceiver',
      5: 'Hybrid',
    };
    return labels[deviceType] ?? 'Unknown';
  }

  String get displayName => name.isNotEmpty ? name : typeLabel;
}
