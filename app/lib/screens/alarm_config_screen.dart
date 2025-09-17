import 'package:flutter/material.dart';
import '../services/local_alarm_service.dart';
import '../models/sensor_data.dart';

class AlarmConfigScreen extends StatefulWidget {
  final SensorData sensor;

  const AlarmConfigScreen({super.key, required this.sensor});

  @override
  State<AlarmConfigScreen> createState() => _AlarmConfigScreenState();
}

class _AlarmConfigScreenState extends State<AlarmConfigScreen> {
  final TextEditingController _thresholdController = TextEditingController();
  AlarmType _selectedType = AlarmType.above;
  bool _isLoading = false;
  List<LocalAlarm> _existingAlarms = [];

  @override
  void initState() {
    super.initState();
    _loadExistingAlarms();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  void _loadExistingAlarms() {
    setState(() {
      _existingAlarms = LocalAlarmService.getAlarms(
        sensorType: widget.sensor.sensor,
        source: widget.sensor.source,
      );
    });
  }

  Future<void> _createAlarm() async {
    if (_thresholdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a threshold value')),
      );
      return;
    }

    final double? threshold = double.tryParse(_thresholdController.text);
    if (threshold == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid number')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await LocalAlarmService.createAlarm(
        sensorType: widget.sensor.sensor,
        source: widget.sensor.source,
        threshold: threshold,
        type: _selectedType,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarm created successfully')),
        );
        _thresholdController.clear();
        _loadExistingAlarms();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating alarm: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteAlarm(String alarmId) async {
    await LocalAlarmService.deleteAlarm(alarmId);
    _loadExistingAlarms();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Alarm deleted')));
    }
  }

  Future<void> _toggleAlarm(String alarmId) async {
    await LocalAlarmService.toggleAlarm(alarmId);
    _loadExistingAlarms();
  }

  String _getUnit(String sensor) {
    switch (sensor) {
      case 'temperature':
        return '°C';
      case 'humidity':
        return '%';
      case 'light':
        return 'lux';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () {
          // Dismiss keyboard when tapping outside
          FocusScope.of(context).unfocus();
        },
        child: Container(
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
                // Header
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${widget.sensor.displayName} Alarms',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Source: ${widget.sensor.source}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Create new alarm section
                        const Text(
                          'Create New Alarm',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Threshold input
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          child: TextField(
                            controller: _thresholdController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Threshold Value',
                              labelStyle: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                              suffixText: _getUnit(widget.sensor.sensor),
                              suffixStyle: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              hintText: 'Enter threshold value',
                              hintStyle: const TextStyle(
                                color: Colors.white54,
                                fontSize: 16,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Alarm type selection
                        const Text(
                          'Trigger When',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedType = AlarmType.above;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _selectedType == AlarmType.above
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _selectedType == AlarmType.above
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.3),
                                      width: 2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _selectedType == AlarmType.above
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Above',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedType = AlarmType.below;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _selectedType == AlarmType.below
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _selectedType == AlarmType.below
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.3),
                                      width: 2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _selectedType == AlarmType.below
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Below',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Create button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _createAlarm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF3B82F6),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF3B82F6),
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Create Alarm',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Existing alarms section
                        const Text(
                          'Existing Alarms',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Alarms list
                        Expanded(
                          child: _existingAlarms.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No alarms configured',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 16,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _existingAlarms.length,
                                  itemBuilder: (context, index) {
                                    final alarm = _existingAlarms[index];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${alarm.type.name.toUpperCase()} ${alarm.threshold.toStringAsFixed(1)}${_getUnit(alarm.sensorType)}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  alarm.isEnabled
                                                      ? 'Enabled'
                                                      : 'Disabled',
                                                  style: TextStyle(
                                                    color: alarm.isEnabled
                                                        ? Colors.green[300]
                                                        : Colors.red[300],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Switch(
                                            value: alarm.isEnabled,
                                            onChanged: (_) =>
                                                _toggleAlarm(alarm.id),
                                            activeThumbColor: Colors.white,
                                            activeTrackColor: Colors.white
                                                .withValues(alpha: 0.3),
                                            inactiveThumbColor: Colors.white54,
                                            inactiveTrackColor: Colors.white
                                                .withValues(alpha: 0.1),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _deleteAlarm(alarm.id),
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.red.withValues(
                                                    alpha: 0.3,
                                                  ),
                                                  width: 1,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.red,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
