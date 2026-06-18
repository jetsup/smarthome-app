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
  });

  factory SmartNode.fromJson(Map<String, dynamic> json) {
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
    );
  }

  String get typeLabel {
    const labels = {
      0: 'Unknown', 1: 'Analog Sensor', 2: 'Digital Sensor',
      3: 'Relay', 4: 'IR Transceiver', 5: 'Hybrid',
    };
    return labels[deviceType] ?? 'Unknown';
  }
}
