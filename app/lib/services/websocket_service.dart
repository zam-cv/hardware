import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/sensor_data.dart';

class WebSocketService {
  static String get _baseUrl => dotenv.env['SERVER_HOST']!;
  static bool get _useEncryption => dotenv.env['USE_ENCRYPTION']?.toLowerCase() == 'true';
  static const String _endpoint = 'ws-metrics';
  
  WebSocketChannel? _channel;
  final StreamController<SensorData> _sensorDataController = StreamController<SensorData>.broadcast();
  final StreamController<String> _connectionStatusController = StreamController<String>.broadcast();
  
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;
  Stream<String> get connectionStatusStream => _connectionStatusController.stream;
  
  bool get isConnected => _channel != null;

  Future<void> connect() async {
    try {
      debugPrint('Attempting to connect to WebSocket...');
      _connectionStatusController.add('Connecting...');
      
      final authToken = dotenv.env['AUTH_TOKEN'] ?? '';
      final protocol = _useEncryption ? 'wss' : 'ws';
      _channel = WebSocketChannel.connect(
        Uri.parse('$protocol://$_baseUrl/$_endpoint'),
        protocols: null,
      );
      
      // Send auth token after connection
      _channel!.sink.add(json.encode({'auth': authToken}));
      
      _connectionStatusController.add('Connected');
      
      _channel!.stream.listen(
        _onDataReceived,
        onError: _onError,
        onDone: _onDone,
      );
      
      debugPrint('WebSocket connected successfully');
    } catch (e) {
      debugPrint('Failed to connect to WebSocket: $e');
      _connectionStatusController.add('Failed to connect');
      rethrow;
    }
  }

  void _onDataReceived(dynamic data) {
    try {
      debugPrint('Received WebSocket data: $data');
      final jsonData = json.decode(data);
      final sensor = SensorData.fromJson(jsonData);
      _sensorDataController.add(sensor);
      _connectionStatusController.add('Receiving data');
    } catch (e) {
      debugPrint('Error parsing sensor data: $e');
    }
  }

  void _onError(error) {
    debugPrint('WebSocket error: $error');
    _connectionStatusController.add('Connection error');
  }

  void _onDone() {
    debugPrint('WebSocket connection closed');
    _connectionStatusController.add('Disconnected');
    _channel = null;
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _connectionStatusController.add('Disconnected');
  }

  void dispose() {
    disconnect();
    _sensorDataController.close();
    _connectionStatusController.close();
  }
}