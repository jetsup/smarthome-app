import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import '../models/gateway.dart';

class DiscoveryService {
  MDnsClient? _client;
  bool _discovering = false;

  Stream<Gateway> discoverGateways({Duration timeout = const Duration(seconds: 8)}) async* {
    _discovering = true;
    _client = MDnsClient();
    await _client!.start();

    try {
      final stream = _client!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_http._tcp.local'),
      );

      final seen = <String>{};
      final deadline = DateTime.now().add(timeout);

      await for (final ptr in stream) {
        if (!_discovering || DateTime.now().isAfter(deadline)) break;

        final domain = ptr.domainName;
        if (seen.contains(domain)) continue;
        seen.add(domain);

        if (!domain.startsWith('smarthome-gw-')) continue;

        try {
          final ipRecord = await _client!
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(domain),
              )
              .first;
          final txtRecord = await _client!
              .lookup<TxtResourceRecord>(
                ResourceRecordQuery.text(domain),
              )
              .first;

          final ip = ipRecord.address;
          final rawText = txtRecord.text;

          String mac = '';
          for (final line in rawText.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            final parts = trimmed.split('=');
            if (parts.length >= 2 && parts[0] == 'id') {
              mac = parts.sublist(1).join('=');
              break;
            }
          }

          yield Gateway(
            id: domain.replaceAll('.local', ''),
            name: 'SmartHome ${domain.replaceAll('.local', '')}',
            localIp: ip.address,
            mdns: domain,
            mac: mac,
            nodeCount: 0,
            online: true,
          );
        } catch (_) {}
      }
    } catch (_) {}

    _discovering = false;
  }

  void stop() {
    _discovering = false;
    _client?.stop();
    _client = null;
  }
}
