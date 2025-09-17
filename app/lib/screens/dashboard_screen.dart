import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../services/websocket_service.dart';
import '../widgets/widgets.dart';
import '../widgets/sensor_chart.dart';
import '../widgets/prediction_card.dart';
import '../models/prediction_data.dart';
import '../services/api_service.dart';
import '../services/local_alarm_service.dart';
import '../services/local_notification_service.dart';
import '../screens/alarm_config_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late WebSocketService _webSocketService;
  final Map<String, SensorData> _sensorData = {};
  final Map<String, PredictionData> _predictionsData = {};
  String _connectionStatus = 'Connecting...';
  bool _isLoading = true;
  bool _predictionsLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeWebSocket();
  }

  void _initializeWebSocket() {
    _webSocketService = WebSocketService();
    
    // Listen to sensor data
    _webSocketService.sensorDataStream.listen((sensorData) {
      setState(() {
        _sensorData[sensorData.sensor] = sensorData;
        _isLoading = false;
      });

      // Check for alarms and send notifications
      _checkAlarmsForSensor(sensorData);

      // Load predictions for this sensor
      _loadPredictions(sensorData.sensor);
    });

    // Listen to connection status
    _webSocketService.connectionStatusStream.listen((status) {
      setState(() {
        _connectionStatus = status;
        if (status == 'Connection error' || status == 'Failed to connect') {
          _isLoading = false;
        }
      });
    });

    // Connect to WebSocket
    _webSocketService.connect().catchError((error) {
      setState(() {
        _isLoading = false;
        _connectionStatus = 'Failed to connect';
      });
    });
  }

  // Chart data loading is now handled by individual SensorChart widgets

  void _checkAlarmsForSensor(SensorData sensorData) {
    final triggeredAlarms = LocalAlarmService.checkMetricAgainstAlarms(
      sensorType: sensorData.sensor,
      source: sensorData.source,
      value: sensorData.value,
    );

    for (final alarm in triggeredAlarms) {
      LocalNotificationService.showAlarmNotification(
        sensorType: sensorData.sensor,
        source: sensorData.source,
        value: sensorData.value,
        threshold: alarm.threshold,
        isAbove: alarm.type == AlarmType.above,
      );
    }
  }

  Future<void> _loadPredictions(String sensor) async {
    if (_predictionsLoading) return;

    setState(() {
      _predictionsLoading = true;
    });

    try {
      final predictions = await ApiService.getPredictions(sensor);
      setState(() {
        _predictionsData[sensor] = predictions;
      });
    } catch (e) {
      // Handle error silently - predictions are optional
    } finally {
      setState(() {
        _predictionsLoading = false;
      });
    }
  }

  void _navigateToAlarmConfig(SensorData sensor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlarmConfigScreen(sensor: sensor),
      ),
    );
  }

  @override
  void dispose() {
    _webSocketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF3B82F6), // blue-500
              Color(0xFF8B5CF6), // purple-500
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: DashboardHeader(connectionStatus: _connectionStatus),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      _buildContent(),
                      const SizedBox(height: 32),
                      _buildChartsSection(),
                      const SizedBox(height: 10),
                      _buildPredictionsSection(),
                      const SizedBox(height: 24), // Bottom padding
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return _buildLoadingCards();
    }

    if (_sensorData.isEmpty) {
      return _buildEmptyState();
    }

    return _buildSensorCards();
  }

  Widget _buildLoadingCards() {
    return Column(
      children: List.generate(3, (index) => 
        Padding(
          padding: EdgeInsets.only(bottom: index < 2 ? 16 : 0),
          child: const LoadingCard(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 100), // Add some spacing
        Icon(
          Icons.sensors_off,
          size: 64,
          color: Colors.white54,
        ),
        SizedBox(height: 16),
        Text(
          'No sensor data available',
          style: TextStyle(
            fontSize: 18,
            color: Colors.white70,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Check your connection and try again',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white54,
          ),
        ),
        SizedBox(height: 100), // Add some spacing at bottom
      ],
    );
  }

  Widget _buildSensorCards() {
    final sortedSensors = _sensorData.values.toList()
      ..sort((a, b) {
        // Sort by sensor type for consistent order
        const order = ['temperature', 'humidity', 'light'];
        return order.indexOf(a.sensor).compareTo(order.indexOf(b.sensor));
      });

    return Column(
      children: sortedSensors.asMap().entries.map((entry) {
        final index = entry.key;
        final sensor = entry.value;
        return Padding(
          padding: EdgeInsets.only(bottom: index < sortedSensors.length - 1 ? 16 : 0),
          child: SensorCard(
            sensor: sensor,
            onAlarmTap: () => _navigateToAlarmConfig(sensor),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPredictionsSection() {
    if (_sensorData.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Predictions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_predictionsLoading) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        ..._buildPredictions(),
      ],
    );
  }

  Widget _buildChartsSection() {
    if (_sensorData.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sensor History',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._buildCharts(),
      ],
    );
  }

  List<Widget> _buildPredictions() {
    final predictions = <Widget>[];
    
    for (final sensorType in ['temperature', 'humidity', 'light']) {
      if (_sensorData.containsKey(sensorType)) {
        final predictionData = _predictionsData[sensorType];
        if (predictionData != null) {
          predictions.add(PredictionCard(predictionData: predictionData));
        }
      }
    }
    
    // Show message if no predictions are loaded yet
    if (predictions.isEmpty && !_predictionsLoading) {
      predictions.add(
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  'Collecting sensor data...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Predictions will appear when we have enough data',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return predictions;
  }

  List<Widget> _buildCharts() {
    final charts = <Widget>[];
    
    for (final sensorType in ['temperature', 'humidity', 'light']) {
      if (_sensorData.containsKey(sensorType)) {
        charts.add(_buildSensorChart(sensorType));
        charts.add(const SizedBox(height: 24));
      }
    }
    
    return charts;
  }

  Widget _buildSensorChart(String sensorType) {
    // Each chart loads its own data with correct resolution
    return SensorChart(initialData: const [], sensorType: sensorType);
  }

}