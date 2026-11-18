/// Timeouts and delays. Tests shrink these.
class Timings {
  /// How long a connect looks for our proxies.
  final Duration scan;

  /// How long the Add a light sheet scans before starting a new scan.
  final Duration addLightScan;

  /// A scan's length when the caller gives none.
  final Duration defaultScan;

  /// How long to wait for the platform to report Bluetooth's state.
  final Duration bleStatus;

  /// The platform's own connection timeout.
  final Duration bleConnect;

  /// The longest wait for a connection, in case the platform's timeout
  /// does not fire.
  final Duration bleConnectGuard;

  /// Time for the notification (CCCD) write to land before the first
  /// request goes out.
  final Duration notifySettle;

  /// How long to wait for a new proxy to prove it is on our network.
  final Duration beacon;
  final Duration provReply;
  final Duration configReply;

  /// How long to wait for a light to confirm a Node Reset.
  /// (LightRepository's Node Reset wait still hardcodes 2 s; it should
  /// read this.)
  final Duration nodeReset;
  final Duration reconnectBase;
  final Duration reconnectStep;
  final Duration throttle;

  /// How long a widget tap waits for the running app to answer.
  final Duration askApp;

  /// Time for queued writes to go out before a widget tap closes the link.
  final Duration writeFlush;

  const Timings({
    this.scan = const Duration(seconds: 12),
    this.addLightScan = const Duration(seconds: 30),
    this.defaultScan = const Duration(seconds: 10),
    this.bleStatus = const Duration(seconds: 3),
    this.bleConnect = const Duration(seconds: 12),
    this.bleConnectGuard = const Duration(seconds: 15),
    this.notifySettle = const Duration(milliseconds: 400),
    this.beacon = const Duration(seconds: 3),
    this.provReply = const Duration(seconds: 15),
    this.configReply = const Duration(milliseconds: 3000),
    this.nodeReset = const Duration(seconds: 2),
    this.reconnectBase = const Duration(milliseconds: 1500),
    this.reconnectStep = const Duration(milliseconds: 1000),
    this.throttle = const Duration(milliseconds: 250),
    this.askApp = const Duration(seconds: 30),
    this.writeFlush = const Duration(milliseconds: 400),
  });

  Timings copyWith({
    Duration? scan,
    Duration? addLightScan,
    Duration? defaultScan,
    Duration? bleStatus,
    Duration? bleConnect,
    Duration? bleConnectGuard,
    Duration? notifySettle,
    Duration? beacon,
    Duration? provReply,
    Duration? configReply,
    Duration? nodeReset,
    Duration? reconnectBase,
    Duration? reconnectStep,
    Duration? throttle,
    Duration? askApp,
    Duration? writeFlush,
  }) => Timings(
    scan: scan ?? this.scan,
    addLightScan: addLightScan ?? this.addLightScan,
    defaultScan: defaultScan ?? this.defaultScan,
    bleStatus: bleStatus ?? this.bleStatus,
    bleConnect: bleConnect ?? this.bleConnect,
    bleConnectGuard: bleConnectGuard ?? this.bleConnectGuard,
    notifySettle: notifySettle ?? this.notifySettle,
    beacon: beacon ?? this.beacon,
    provReply: provReply ?? this.provReply,
    configReply: configReply ?? this.configReply,
    nodeReset: nodeReset ?? this.nodeReset,
    reconnectBase: reconnectBase ?? this.reconnectBase,
    reconnectStep: reconnectStep ?? this.reconnectStep,
    throttle: throttle ?? this.throttle,
    askApp: askApp ?? this.askApp,
    writeFlush: writeFlush ?? this.writeFlush,
  );
}
