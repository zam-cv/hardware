import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum AlarmType { above, below }

class LocalAlarm {
  final String id;
  final String sensorType;
  final String source;
  final double threshold;
  final AlarmType type;
  final bool isEnabled;

  LocalAlarm({
    required this.id,
    required this.sensorType,
    required this.source,
    required this.threshold,
    required this.type,
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sensorType': sensorType,
      'source': source,
      'threshold': threshold,
      'type': type.name,
      'isEnabled': isEnabled,
    };
  }

  factory LocalAlarm.fromJson(Map<String, dynamic> json) {
    return LocalAlarm(
      id: json['id'],
      sensorType: json['sensorType'],
      source: json['source'],
      threshold: json['threshold'].toDouble(),
      type: AlarmType.values.firstWhere((e) => e.name == json['type']),
      isEnabled: json['isEnabled'] ?? true,
    );
  }

  LocalAlarm copyWith({
    String? id,
    String? sensorType,
    String? source,
    double? threshold,
    AlarmType? type,
    bool? isEnabled,
  }) {
    return LocalAlarm(
      id: id ?? this.id,
      sensorType: sensorType ?? this.sensorType,
      source: source ?? this.source,
      threshold: threshold ?? this.threshold,
      type: type ?? this.type,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

class LocalAlarmService {
  static const String _storageKey = 'local_alarms';
  static SharedPreferences? _prefs;
  static List<LocalAlarm> _alarms = [];

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadAlarms();
  }

  static Future<void> _loadAlarms() async {
    final String? alarmsJson = _prefs?.getString(_storageKey);
    if (alarmsJson != null) {
      final List<dynamic> alarmsData = json.decode(alarmsJson);
      _alarms = alarmsData.map((data) => LocalAlarm.fromJson(data)).toList();
    }
  }

  static Future<void> _saveAlarms() async {
    final String alarmsJson = json.encode(_alarms.map((alarm) => alarm.toJson()).toList());
    await _prefs?.setString(_storageKey, alarmsJson);
  }

  static Future<String> createAlarm({
    required String sensorType,
    required String source,
    required double threshold,
    required AlarmType type,
  }) async {
    final String id = DateTime.now().millisecondsSinceEpoch.toString();
    final LocalAlarm alarm = LocalAlarm(
      id: id,
      sensorType: sensorType,
      source: source,
      threshold: threshold,
      type: type,
    );

    _alarms.add(alarm);
    await _saveAlarms();
    return id;
  }

  static Future<void> updateAlarm(String id, {
    String? sensorType,
    String? source,
    double? threshold,
    AlarmType? type,
    bool? isEnabled,
  }) async {
    final int index = _alarms.indexWhere((alarm) => alarm.id == id);
    if (index != -1) {
      _alarms[index] = _alarms[index].copyWith(
        sensorType: sensorType,
        source: source,
        threshold: threshold,
        type: type,
        isEnabled: isEnabled,
      );
      await _saveAlarms();
    }
  }

  static Future<void> deleteAlarm(String id) async {
    _alarms.removeWhere((alarm) => alarm.id == id);
    await _saveAlarms();
  }

  static Future<void> toggleAlarm(String id) async {
    final int index = _alarms.indexWhere((alarm) => alarm.id == id);
    if (index != -1) {
      _alarms[index] = _alarms[index].copyWith(isEnabled: !_alarms[index].isEnabled);
      await _saveAlarms();
    }
  }

  static List<LocalAlarm> getAlarms({String? sensorType, String? source}) {
    return _alarms.where((alarm) {
      if (sensorType != null && alarm.sensorType != sensorType) return false;
      if (source != null && alarm.source != source) return false;
      return true;
    }).toList();
  }

  static LocalAlarm? getAlarm(String id) {
    try {
      return _alarms.firstWhere((alarm) => alarm.id == id);
    } catch (e) {
      return null;
    }
  }

  static List<LocalAlarm> checkMetricAgainstAlarms({
    required String sensorType,
    required String source,
    required double value,
  }) {
    return _alarms.where((alarm) {
      if (!alarm.isEnabled) return false;
      if (alarm.sensorType != sensorType) return false;
      if (alarm.source != source) return false;

      switch (alarm.type) {
        case AlarmType.above:
          return value > alarm.threshold;
        case AlarmType.below:
          return value < alarm.threshold;
      }
    }).toList();
  }

  static Future<void> clearAllAlarms() async {
    _alarms.clear();
    await _saveAlarms();
  }

  static int getAlarmsCount() {
    return _alarms.length;
  }
}