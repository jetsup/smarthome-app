class Gateway {
  final String id;
  final String name;
  final String? apiKey;
  final bool online;
  final String? lastSeen;
  final int nodeCount;
  final int onlineNodes;
  final String? localIp;
  final String? mdns;
  final String? mac;

  Gateway({
    required this.id,
    required this.name,
    this.apiKey,
    this.online = false,
    this.lastSeen,
    this.nodeCount = 0,
    this.onlineNodes = 0,
    this.localIp,
    this.mdns,
    this.mac,
  });

  factory Gateway.fromJson(Map<String, dynamic> json) {
    return Gateway(
      id: json['id'] as String? ?? json['gatewayId'] as String? ?? '',
      name: json['name'] as String? ?? 'Gateway ${json['id'] ?? ''}',
      apiKey: json['apiKey'] as String?,
      online: json['online'] as bool? ?? false,
      lastSeen: json['lastSeen'] as String?,
      nodeCount: json['nodeCount'] as int? ?? 0,
      onlineNodes: json['onlineNodes'] as int? ?? 0,
      localIp: json['wifiIP'] as String?,
      mdns: json['mdns'] as String?,
      mac: json['mac'] as String?,
    );
  }
}
