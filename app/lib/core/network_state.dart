enum NetworkStatus { unknown, offline, connected }

enum NetworkTransport { wifi, ethernet, cellular, other }

/// Local system observation only; it is not evidence that a host is reachable.
final class NetworkSnapshot {
  const NetworkSnapshot.unknown()
    : status = NetworkStatus.unknown,
      transports = const {};
  const NetworkSnapshot.offline()
    : status = NetworkStatus.offline,
      transports = const {};
  NetworkSnapshot.connected(Iterable<NetworkTransport> values)
    : status = NetworkStatus.connected,
      transports = Set.unmodifiable(values) {
    if (transports.isEmpty) throw const FormatException('网络类型未确认。');
  }
  final NetworkStatus status;
  final Set<NetworkTransport> transports;

  factory NetworkSnapshot.fromPlatform(Object? value) {
    if (value is! Map ||
        value.length != 2 ||
        !value.containsKey('status') ||
        !value.containsKey('transports') ||
        value['status'] is! String ||
        value['transports'] is! List) {
      throw const FormatException('网络观察格式未确认。');
    }
    final status = switch (value['status']) {
      'unknown' => NetworkStatus.unknown,
      'offline' => NetworkStatus.offline,
      'connected' => NetworkStatus.connected,
      _ => throw const FormatException('网络状态未确认。'),
    };
    final raw = value['transports'] as List;
    if (raw.length > NetworkTransport.values.length ||
        raw.any((item) => item is! String)) {
      throw const FormatException('网络类型未确认。');
    }
    final types = raw
        .map(
          (item) => switch (item) {
            'wifi' => NetworkTransport.wifi,
            'ethernet' => NetworkTransport.ethernet,
            'cellular' => NetworkTransport.cellular,
            'other' => NetworkTransport.other,
            _ => throw const FormatException('网络类型未确认。'),
          },
        )
        .toSet();
    if (types.length != raw.length ||
        (status != NetworkStatus.connected && types.isNotEmpty)) {
      throw const FormatException('网络类型未确认。');
    }
    return switch (status) {
      NetworkStatus.unknown => const NetworkSnapshot.unknown(),
      NetworkStatus.offline => const NetworkSnapshot.offline(),
      NetworkStatus.connected => NetworkSnapshot.connected(types),
    };
  }

  String get label => switch (status) {
    NetworkStatus.unknown => '网络状态未确认',
    NetworkStatus.offline => '离线',
    NetworkStatus.connected =>
      NetworkTransport.values
          .where(transports.contains)
          .map(
            (type) => switch (type) {
              NetworkTransport.wifi => 'Wi-Fi',
              NetworkTransport.ethernet => '有线网络',
              NetworkTransport.cellular => '移动网络',
              NetworkTransport.other => '其他网络',
            },
          )
          .join(' / '),
  };

  @override
  bool operator ==(Object other) =>
      other is NetworkSnapshot &&
      status == other.status &&
      transports.length == other.transports.length &&
      transports.every(other.transports.contains);
  @override
  int get hashCode => Object.hash(status, Object.hashAllUnordered(transports));
}

enum NetworkUploadPolicy {
  wifiAndEthernet,
  anyKnownNetwork;

  bool allows(NetworkSnapshot snapshot) =>
      snapshot.status == NetworkStatus.connected &&
      snapshot.transports.isNotEmpty &&
      (this == anyKnownNetwork ||
          snapshot.transports.every(
            (type) =>
                type == NetworkTransport.wifi ||
                type == NetworkTransport.ethernet,
          ));
}

abstract interface class NetworkMonitor {
  NetworkSnapshot get current;
  Stream<NetworkSnapshot> get changes;
  Future<void> start();
  Future<void> refresh();
  Future<void> close();
}
