import 'light.dart';

/// A named brightness and colour temperature for every light.
class Preset {
  final String name;

  /// 1–100 %.
  final int level;
  final int kelvin;
  const Preset(this.name, this.level, this.kelvin);

  /// Reads a preset saved by [toJson]. Returns null if it is not one.
  static Preset? fromJson(Object? j) => switch (j) {
    {'name': final String name, 'level': final num level, 'kelvin': final num kelvin}
        when name.trim().isNotEmpty =>
      Preset(name.trim(), level.round().clamp(1, 100), kelvin.round().clamp(minKelvin, maxKelvin)),
    _ => null,
  };

  Map<String, Object?> toJson() => {'name': name, 'level': level, 'kelvin': kelvin};

  @override
  bool operator ==(Object other) =>
      other is Preset && other.name == name && other.level == level && other.kelvin == kelvin;

  @override
  int get hashCode => Object.hash(name, level, kelvin);
}

/// The built-in presets. Home-screen widgets and app shortcuts use these.
const presets = [
  Preset('Relax', 35, 2700),
  Preset('Read', 90, 4000),
  Preset('Daylight', 100, 6500),
  Preset('Night', 5, 2700),
];
