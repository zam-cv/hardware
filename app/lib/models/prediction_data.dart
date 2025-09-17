class PredictionData {
  final String sensor;
  final Map<String, PredictionValue> predictions;
  final String? modelTrained;
  final String? error;

  PredictionData({
    required this.sensor,
    required this.predictions,
    this.modelTrained,
    this.error,
  });

  factory PredictionData.fromJson(Map<String, dynamic> json) {
    if (json['error'] != null) {
      return PredictionData(
        sensor: json['sensor'] ?? '',
        predictions: {},
        error: json['error'],
      );
    }

    final predictionsMap = <String, PredictionValue>{};
    final predictions = json['predictions'] as Map<String, dynamic>? ?? {};
    
    for (final entry in predictions.entries) {
      predictionsMap[entry.key] = PredictionValue.fromJson(entry.value);
    }

    return PredictionData(
      sensor: json['sensor'] ?? '',
      predictions: predictionsMap,
      modelTrained: json['model_trained'],
    );
  }

  bool get hasError => error != null;
  bool get hasPredictions => predictions.isNotEmpty && !hasError;
}

class PredictionValue {
  final double value;
  final DateTime timestamp;
  final double confidence;

  PredictionValue({
    required this.value,
    required this.timestamp,
    required this.confidence,
  });

  factory PredictionValue.fromJson(Map<String, dynamic> json) {
    return PredictionValue(
      value: (json['value'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  String get confidenceText {
    if (confidence >= 0.8) return 'High';
    if (confidence >= 0.6) return 'Medium';
    return 'Low';
  }

  String get timeFromNow {
    final now = DateTime.now();
    final diff = timestamp.difference(now);
    
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}min';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h';
    } else {
      return '${diff.inDays}d';
    }
  }
}