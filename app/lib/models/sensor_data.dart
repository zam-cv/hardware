enum SensorType { temperature, humidity, light }

class SensorData {
  final String id;
  final String source;
  final String sensor;
  final double value;
  final DateTime timestamp;

  SensorData({
    required this.id,
    required this.source,
    required this.sensor,
    required this.value,
    required this.timestamp,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      id: json['id'],
      source: json['source'],
      sensor: json['sensor'],
      value: json['value'].toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  String get displayValue {
    switch (sensor) {
      case 'temperature':
        return '${value.toStringAsFixed(1)}';
      case 'humidity':
        return '${value.toStringAsFixed(1)}';
      case 'light':
        return '${value.toStringAsFixed(1)}';
      default:
        return value.toStringAsFixed(1);
    }
  }

  String get displayName {
    switch (sensor) {
      case 'temperature':
        return 'Temperature';
      case 'humidity':
        return 'Humidity';
      case 'light':
        return 'Light';
      default:
        return sensor.toUpperCase();
    }
  }
}