import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/network_state.dart';

void main() {
  test('UT-063 strict local network protocol and deterministic display', () {
    final snapshot = NetworkSnapshot.fromPlatform({
      'status': 'connected',
      'transports': ['ethernet', 'wifi'],
    });
    expect(snapshot.status, NetworkStatus.connected);
    expect(snapshot.transports, {
      NetworkTransport.wifi,
      NetworkTransport.ethernet,
    });
    expect(snapshot.label, 'Wi-Fi / 有线网络');
    final reordered = NetworkSnapshot.connected([
      NetworkTransport.wifi,
      NetworkTransport.ethernet,
    ]);
    expect(snapshot, reordered);
    expect(snapshot.hashCode, reordered.hashCode);
    expect(
      () => snapshot.transports.add(NetworkTransport.other),
      throwsUnsupportedError,
    );
    expect(
      NetworkSnapshot.fromPlatform({'status': 'offline', 'transports': []}),
      const NetworkSnapshot.offline(),
    );
    expect(
      NetworkSnapshot.fromPlatform({'status': 'unknown', 'transports': []}),
      const NetworkSnapshot.unknown(),
    );
  });

  test(
    'UT-063/SEC-005 malformed observations never become allowed networks',
    () {
      final invalid = <Object?>[
        null,
        [],
        'wifi',
        {},
        {'status': 'connected'},
        {'status': 'connected', 'transports': [], 'extra': true},
        {'status': 1, 'transports': []},
        {
          'status': 'online',
          'transports': ['wifi'],
        },
        {'status': 'connected', 'transports': 'wifi'},
        {'status': 'connected', 'transports': []},
        {
          'status': 'connected',
          'transports': ['wifi', 'wifi'],
        },
        {
          'status': 'connected',
          'transports': ['vpn'],
        },
        {
          'status': 'connected',
          'transports': [1],
        },
        {
          'status': 'offline',
          'transports': ['wifi'],
        },
        {
          'status': 'unknown',
          'transports': ['wifi'],
        },
        {
          'status': 'connected',
          'transports': ['wifi', 'ethernet', 'cellular', 'other', 'wifi'],
        },
      ];
      for (final value in invalid) {
        expect(
          () => NetworkSnapshot.fromPlatform(value),
          throwsA(isA<Exception>()),
        );
      }
    },
  );

  test('UT-063 type allowlist rejects mixed cellular by default', () {
    for (final state in [
      const NetworkSnapshot.unknown(),
      const NetworkSnapshot.offline(),
    ]) {
      for (final policy in NetworkUploadPolicy.values) {
        expect(policy.allows(state), isFalse);
      }
    }
    for (final values in [
      [NetworkTransport.wifi],
      [NetworkTransport.ethernet],
      [NetworkTransport.wifi, NetworkTransport.ethernet],
    ]) {
      expect(
        NetworkUploadPolicy.wifiAndEthernet.allows(
          NetworkSnapshot.connected(values),
        ),
        isTrue,
      );
    }
    for (final values in [
      [NetworkTransport.cellular],
      [NetworkTransport.other],
      [NetworkTransport.wifi, NetworkTransport.cellular],
      [NetworkTransport.ethernet, NetworkTransport.other],
    ]) {
      final snapshot = NetworkSnapshot.connected(values);
      expect(NetworkUploadPolicy.wifiAndEthernet.allows(snapshot), isFalse);
      expect(NetworkUploadPolicy.anyKnownNetwork.allows(snapshot), isTrue);
    }
    expect(
      NetworkUploadPolicy.anyKnownNetwork.allows(
        NetworkSnapshot.connected(NetworkTransport.values),
      ),
      isTrue,
    );
  });
}
