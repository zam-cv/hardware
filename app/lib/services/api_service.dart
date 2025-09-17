import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/sensor_data.dart';
import '../models/prediction_data.dart';

class ApiService {
  static String get _baseUrl => dotenv.env['SERVER_HOST']!;
  static bool get _useEncryption => dotenv.env['USE_ENCRYPTION']?.toLowerCase() == 'true';

  static Map<String, String> get _authHeaders => {
    'protected': dotenv.env['AUTH_TOKEN'] ?? '',
  };
  
  static Future<List<SensorData>> getHistoryData({
    required String sensor,
    String? fromTime,
    String? toTime,
    int targetPoints = 60,
  }) async {
    final queryParams = <String, String>{
      'sensor': sensor,
      'target_points': targetPoints.toString(),
    };
    
    if (fromTime != null) queryParams['from_time'] = fromTime;
    if (toTime != null) queryParams['to_time'] = toTime;
    
    final uri = _useEncryption
        ? Uri.https(_baseUrl, '/metrics/history', queryParams)
        : Uri.http(_baseUrl, '/metrics/history', queryParams);
    
    try {
      final response = await http.get(uri, headers: _authHeaders);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> metrics = data['data'];
        
        return metrics.map((metric) => SensorData(
          id: metric['timestamp'], // Use timestamp as ID for history data
          source: metric['source'] ?? 'unknown',
          sensor: metric['sensor'],
          value: metric['value'].toDouble(),
          timestamp: DateTime.parse(metric['timestamp']),
        )).toList();
      } else {
        throw Exception('Failed to load history data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  static Future<PredictionData> getPredictions(String sensor, {List<int>? horizons}) async {
    final queryParams = <String, String>{};
    
    if (horizons != null && horizons.isNotEmpty) {
      queryParams['horizons'] = horizons.join(',');
    }
    
    final uri = _useEncryption
        ? Uri.https(_baseUrl, '/predict/$sensor', queryParams)
        : Uri.http(_baseUrl, '/predict/$sensor', queryParams);
    
    try {
      final response = await http.get(uri, headers: _authHeaders);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return PredictionData.fromJson(data);
      } else {
        throw Exception('Failed to load predictions: ${response.statusCode}');
      }
    } catch (e) {
      return PredictionData(
        sensor: sensor,
        predictions: {},
        error: 'Failed to connect: $e',
      );
    }
  }
}