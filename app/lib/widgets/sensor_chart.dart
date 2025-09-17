import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/sensor_data.dart';
import '../services/api_service.dart';

enum ChartResolution { min15, hour1, hour6, hour24, days7 }

class TimeLabel {
  final double position;
  final String label;
  
  TimeLabel({required this.position, required this.label});
}

class SensorChart extends StatefulWidget {
  final List<SensorData> initialData;
  final String sensorType;

  const SensorChart({
    super.key,
    required this.initialData,
    required this.sensorType,
  });

  @override
  State<SensorChart> createState() => _SensorChartState();
}

class _SensorChartState extends State<SensorChart> {
  List<SensorData> data = [];
  ChartResolution selectedResolution = ChartResolution.min15;
  bool isLoading = false;
  Timer? _autoUpdateTimer;

  @override
  void initState() {
    super.initState();
    // Don't use initialData as it might be from different resolution
    // Load data with correct resolution immediately
    _loadDataForResolution(selectedResolution);
    _startAutoUpdateTimer();
  }

  void _startAutoUpdateTimer() {
    _autoUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _loadDataForResolution(selectedResolution);
    });
  }

  @override
  void dispose() {
    _autoUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty && !isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: const Center(
          child: Text(
            'No data available',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getSensorDisplayName(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: isLoading 
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white70,
                    strokeWidth: 2,
                  ),
                ) 
              : LineChart(_buildChart()),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildResolutionSelector(),
            ],
          ),
        ],
      ),
    );
  }

  LineChartData _buildChart() {
    final spots = _generateSpots();
    final (minY, maxY) = _calculateYRange(spots);

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: (maxY - minY) / 4,
        getDrawingHorizontalLine: (value) => FlLine(
          color: Colors.white.withValues(alpha: 0.1),
          strokeWidth: 1,
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: (maxY - minY) / 4, // Forzar intervalo exacto para 5 valores
            getTitlesWidget: (value, meta) {
              // Solo mostrar si es uno de mis valores exactos
              final labelsToShow = _getYLabelsToShow(minY, maxY);
              
              // Buscar coincidencia exacta con tolerancia muy pequeña
              for (final label in labelsToShow) {
                if ((value - label).abs() < 0.001) {
                  return Text(
                    _formatYValue(label),
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  );
                }
              }
              
              return const SizedBox.shrink();
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 35,
            getTitlesWidget: (value, meta) {
              final timeLabelsToShow = _getXLabelsToShow();
              
              // Buscar si este valor coincide con uno de mis labels forzados
              for (final timeLabel in timeLabelsToShow) {
                if ((value - timeLabel.position).abs() < 0.1) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      timeLabel.label,
                      style: const TextStyle(color: Colors.white70, fontSize: 9),
                    ),
                  );
                }
              }
              
              return const SizedBox.shrink();
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: _getSensorColor(),
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: spots.length < 50,
            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
              radius: 3,
              color: _getSensorColor(),
              strokeWidth: 0,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            color: _getSensorColor().withValues(alpha: 0.1),
          ),
        ),
      ],
      minX: 0,
      maxX: 100,
      minY: minY,
      maxY: maxY,
    );
  }

  List<FlSpot> _generateSpots() {
    if (data.isEmpty) return [];
    
    // Use requested time range, not actual data range
    final now = DateTime.now();
    final (startRange, endRange) = _getRequestedTimeRange(now);
    final rangeDiff = endRange.difference(startRange).inMilliseconds;
    
    return data.map((sensorData) {
      // Convert UTC timestamp to local time for consistent mapping
      final localTimestamp = sensorData.timestamp.toLocal();
      final timeDiff = localTimestamp.difference(startRange).inMilliseconds;
      final xPosition = (timeDiff / rangeDiff) * 100;
      
      return FlSpot(xPosition.clamp(0, 100), sensorData.value);
    }).toList();
  }
  
  (DateTime, DateTime) _getRequestedTimeRange(DateTime now) {
    switch (selectedResolution) {
      case ChartResolution.min15:
        return (now.subtract(const Duration(minutes: 15)), now);
      case ChartResolution.hour1:
        return (now.subtract(const Duration(hours: 1)), now);
      case ChartResolution.hour6:
        return (now.subtract(const Duration(hours: 6)), now);
      case ChartResolution.hour24:
        return (now.subtract(const Duration(hours: 24)), now);
      case ChartResolution.days7:
        return (now.subtract(const Duration(days: 7)), now);
    }
  }


  (double, double) _calculateYRange(List<FlSpot> spots) {
    if (spots.isEmpty) return (0, 100);
    
    final values = spots.map((s) => s.y).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    
    // Si todos los valores son iguales, crear un rango artificial
    if (minVal == maxVal) {
      final baseValue = minVal;
      final range = baseValue == 0 ? 1.0 : baseValue.abs() * 0.1;
      return (baseValue - range, baseValue + range);
    }
    
    final padding = (maxVal - minVal) * 0.1;
    return (minVal - padding, maxVal + padding);
  }

  List<double> _getYLabelsToShow(double minY, double maxY) {
    if (minY == maxY) return [minY];
    
    // Crear exactamente 5 valores distribuidos uniformemente
    final labels = <double>[];
    for (int i = 0; i < 5; i++) {
      final value = minY + (maxY - minY) * i / 4;
      labels.add(value);
    }
    
    return labels;
  }


  String _formatYValue(double value) {
    // Siempre mostrar 1 decimal para todos los sensores
    return value.toStringAsFixed(1);
  }

  Widget _buildResolutionSelector() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ChartResolution.values.map((resolution) {
          final isSelected = resolution == selectedResolution;
          return GestureDetector(
            onTap: () {
              if (resolution != selectedResolution) {
                setState(() {
                  selectedResolution = resolution;
                });
                _loadDataForResolution(resolution);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected 
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _getResolutionDisplayName(resolution),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 11,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _loadDataForResolution(ChartResolution resolution) async {
    setState(() {
      isLoading = true;
    });

    try {
      final now = DateTime.now();
      String? fromTime;
      int targetPoints;

      switch (resolution) {
        case ChartResolution.min15:
          fromTime = now.subtract(const Duration(minutes: 15)).toUtc().toIso8601String();
          targetPoints = 15; // 15 points distributed over 15 minutes (1 per minute)
          break;
        case ChartResolution.hour1:
          fromTime = now.subtract(const Duration(hours: 1)).toUtc().toIso8601String();
          targetPoints = 60; // 60 points distributed over 1 hour
          break;
        case ChartResolution.hour6:
          fromTime = now.subtract(const Duration(hours: 6)).toUtc().toIso8601String();
          targetPoints = 60; // 60 points distributed over 6 hours
          break;
        case ChartResolution.hour24:
          fromTime = now.subtract(const Duration(hours: 24)).toUtc().toIso8601String();
          targetPoints = 48; // 48 points distributed over 24 hours
          break;
        case ChartResolution.days7:
          fromTime = now.subtract(const Duration(days: 7)).toUtc().toIso8601String();
          targetPoints = 168; // 168 points distributed over 7 days
          break;
      }

      final newData = await ApiService.getHistoryData(
        sensor: widget.sensorType,
        fromTime: fromTime,
        targetPoints: targetPoints,
      );

      newData.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      setState(() {
        data = newData;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      debugPrint('Failed to load chart data: $e');
    }
  }

  String _getResolutionDisplayName(ChartResolution resolution) {
    switch (resolution) {
      case ChartResolution.min15:
        return '15m';
      case ChartResolution.hour1:
        return '1h';
      case ChartResolution.hour6:
        return '6h';
      case ChartResolution.hour24:
        return '24h';
      case ChartResolution.days7:
        return '7d';
    }
  }



  List<TimeLabel> _getXLabelsToShow() {
    // Use requested time range for labels, not actual data range
    final now = DateTime.now();
    final (startRange, endRange) = _getRequestedTimeRange(now);
    final labels = <TimeLabel>[];
    
    final totalDuration = endRange.difference(startRange);
    final labelCount = _getLabelCount();
    
    for (int i = 0; i <= labelCount; i++) {
      final position = labelCount > 0 ? (100.0 * i / labelCount) : 50.0;
      final fraction = labelCount > 0 ? i / labelCount : 0.5;
      final timeAtPosition = startRange.add(Duration(
        milliseconds: (totalDuration.inMilliseconds * fraction).round()
      ));
      
      labels.add(TimeLabel(
        position: position,
        label: _formatTimeLabel(timeAtPosition, totalDuration)
      ));
    }
    
    return labels;
  }
  
  int _getLabelCount() {
    switch (selectedResolution) {
      case ChartResolution.min15:
      case ChartResolution.hour1:
      case ChartResolution.hour6:
        return 3; // 4 labels total (0, 33, 66, 100)
      case ChartResolution.hour24:
        return 4; // 5 labels total (0, 25, 50, 75, 100)
      case ChartResolution.days7:
        return 6; // 7 labels total
    }
  }
  
  String _formatTimeLabel(DateTime time, Duration totalDuration) {
    if (totalDuration.inDays >= 1) {
      // Show month and day for long periods
      final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[time.month]} ${time.day}';
    } else if (totalDuration.inHours >= 6) {
      // Show hour for medium periods
      return '${time.hour.toString().padLeft(2, '0')}:00';
    } else {
      // Show hour:minute for short periods
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  String _getSensorDisplayName() {
    switch (widget.sensorType) {
      case 'temperature':
        return 'Temperature (°C)';
      case 'humidity':
        return 'Humidity (%)';
      case 'light':
        return 'Light Level';
      default:
        return widget.sensorType.toUpperCase();
    }
  }

  Color _getSensorColor() {
    switch (widget.sensorType) {
      case 'temperature':
        return const Color(0xFFFF6B6B); // Red
      case 'humidity':
        return const Color(0xFF4ECDC4); // Teal
      case 'light':
        return const Color(0xFFFFD93D); // Yellow
      default:
        return Colors.white;
    }
  }
}