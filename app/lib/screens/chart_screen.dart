import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../services/api_service.dart';
import '../widgets/sensor_chart.dart';

enum TimeRange { hour24, days7, days30 }

class ChartScreen extends StatefulWidget {
  final String sensorType;

  const ChartScreen({super.key, required this.sensorType});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  List<SensorData> _data = [];
  bool _isLoading = true;
  String? _errorMessage;
  TimeRange _selectedRange = TimeRange.hour24;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      String? fromTime;
      int targetPoints;

      switch (_selectedRange) {
        case TimeRange.hour24:
          fromTime = now.subtract(const Duration(hours: 24)).toUtc().toIso8601String();
          targetPoints = 48; // 48 points distributed over 24 hours
          break;
        case TimeRange.days7:
          fromTime = now.subtract(const Duration(days: 7)).toUtc().toIso8601String();
          targetPoints = 168; // 168 points distributed over 7 days
          break;
        case TimeRange.days30:
          fromTime = now.subtract(const Duration(days: 30)).toUtc().toIso8601String();
          targetPoints = 60; // 60 points distributed over 30 days
          break;
      }

      final data = await ApiService.getHistoryData(
        sensor: widget.sensorType,
        fromTime: fromTime,
        targetPoints: targetPoints,
      );

      // Sort by timestamp (oldest first for proper chart display)
      data.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
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
              _buildAppBar(context),
              _buildTimeRangeSelector(),
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _getSensorDisplayName(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: TimeRange.values.map((range) {
          final isSelected = range == _selectedRange;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedRange = range;
                });
                _loadData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getRangeDisplayName(range),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load data',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SensorChart(
        initialData: _data,
        sensorType: widget.sensorType,
      ),
    );
  }

  String _getSensorDisplayName() {
    switch (widget.sensorType) {
      case 'temperature':
        return 'Temperature Chart';
      case 'humidity':
        return 'Humidity Chart';
      case 'light':
        return 'Light Chart';
      default:
        return '${widget.sensorType.toUpperCase()} Chart';
    }
  }

  String _getRangeDisplayName(TimeRange range) {
    switch (range) {
      case TimeRange.hour24:
        return '24 Hours';
      case TimeRange.days7:
        return '7 Days';
      case TimeRange.days30:
        return '30 Days';
    }
  }
}