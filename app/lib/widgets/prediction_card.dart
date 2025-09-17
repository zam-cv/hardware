import 'package:flutter/material.dart';
import '../models/prediction_data.dart';

class PredictionCard extends StatelessWidget {
  final PredictionData predictionData;

  const PredictionCard({
    super.key,
    required this.predictionData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - same design for all sensors
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getSensorTitle(predictionData.sensor),
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.auto_awesome,
                color: Colors.white.withValues(alpha: 0.6),
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Error state
          if (predictionData.hasError) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade300, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      predictionData.error!,
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]
          
          // Predictions Grid
          else if (predictionData.hasPredictions) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final itemWidth = (availableWidth - 8) / 2; // 2 columns with spacing
                
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: predictionData.predictions.entries.map((entry) {
                    final horizonKey = entry.key;
                    final prediction = entry.value;
                    return SizedBox(
                      width: itemWidth,
                      child: _buildPredictionTile(horizonKey, prediction),
                    );
                  }).toList(),
                );
              },
            ),
          ]
          
          // No predictions
          else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  'No predictions available',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPredictionTile(String horizonKey, PredictionValue prediction) {
    return Container(
      height: 70, // Fixed height to prevent overflow
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Time label
          Text(
            _formatTimeHorizon(horizonKey),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          
          // Predicted value
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    prediction.value.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Text(
                _getSensorUnit(predictionData.sensor),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          
          // Confidence indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: _getConfidenceColor(prediction.confidence),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                prediction.confidenceText,
                style: TextStyle(
                  color: _getConfidenceColor(prediction.confidence),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimeHorizon(String horizonKey) {
    switch (horizonKey) {
      case '15min':
        return '15m';
      case '60min':
        return '1h';
      case '360min':
        return '6h';
      case '1440min':
        return '24h';
      default:
        return horizonKey.replaceAll('min', 'm');
    }
  }

  String _getSensorTitle(String sensor) {
    switch (sensor.toLowerCase()) {
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

  String _getSensorUnit(String sensor) {
    switch (sensor.toLowerCase()) {
      case 'temperature':
        return '°C';
      case 'humidity':
        return '%';
      case 'light':
        return ' lux';
      default:
        return '';
    }
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return const Color.fromARGB(255, 67, 242, 195);
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }
}