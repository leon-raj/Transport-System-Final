/// Build-time configuration.
///
/// ```
/// flutter run -d chrome                                           # API on localhost:8000
/// flutter run -d emulator-5554 --dart-define=API_BASE=http://10.0.2.2:8000
/// flutter run -d <phone> --dart-define=API_BASE=http://<laptop-LAN-IP>:8000
/// ```
abstract final class AppConfig {
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

  static String get wsBase => apiBase.replaceFirst(RegExp(r'^http'), 'ws');

  /// Map tiles. The OpenStreetMap public server is fine for development only (fair-use policy,
  /// attribution required). Before launch point this at MapTiler, Stadia or your own server:
  /// `--dart-define=TILE_URL=https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=KEY`
  /// Base URL of the Go bus-scheduler service.
  /// `flutter run --dart-define=SCHEDULER_BASE=http://10.0.2.2:8080`
  static const schedulerBase = String.fromEnvironment(
    'SCHEDULER_BASE',
    defaultValue: 'http://localhost:8080',
  );

  static const tileUrl = String.fromEnvironment(
    'TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Shown on every map, as the tile provider's licence requires.
  static const tileAttribution = String.fromEnvironment(
    'TILE_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );
}
