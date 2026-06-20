import 'dart:convert';

class CapabilityConfig {
  final String type;
  final int pin;
  final int extra;
  final String label;
  final int? value;

  CapabilityConfig({
    required this.type,
    this.pin = 0,
    this.extra = 0,
    this.label = '',
    this.value,
  });

  factory CapabilityConfig.fromJson(Map<String, dynamic> json) {
    return CapabilityConfig(
      type: json['type'] as String? ?? '',
      pin: json['pin'] as int? ?? 0,
      extra: json['extra'] as int? ?? 0,
      label: json['label'] as String? ?? '',
      value: json['value'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'pin': pin,
    'extra': extra,
    'label': label,
  };
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
