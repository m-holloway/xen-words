/// Metadata for a tunable parameter in the Director system
class TunableParameter {
  final String name;
  final String director;
  final ParameterType type;
  final double min;
  final double max;
  final dynamic defaultValue;
  final String? unit;
  final String? description;
  
  const TunableParameter({
    required this.name,
    required this.director,
    required this.type,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.unit,
    this.description,
  });
  
  /// Get current value (from tuner if overridden, otherwise default)
  dynamic getCurrentValue(Map<String, dynamic> overrides) {
    return overrides[name] ?? defaultValue;
  }
  
  /// Validate a value is within range
  bool isValidValue(dynamic value) {
    if (value is double) {
      return value >= min && value <= max;
    } else if (value is int) {
      return value >= min && value <= max;
    } else if (value is bool) {
      return type == ParameterType.bool;
    }
    return false;
  }
  
  /// Clamp a value to valid range
  dynamic clampValue(dynamic value) {
    if (value is num) {
      return (value < min) ? min : ((value > max) ? max : value);
    }
    return value;
  }
}

enum ParameterType {
  double,
  int,
  bool,
  vector3X,
  vector3Y,
  vector3Z,
  duration,
}

