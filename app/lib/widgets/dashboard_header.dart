import 'package:flutter/material.dart';

class DashboardHeader extends StatelessWidget {
  final String connectionStatus;

  const DashboardHeader({
    super.key,
    required this.connectionStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStatusIndicator(),
            const SizedBox(width: 8),
            Text(
              connectionStatus,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    Color color;
    switch (connectionStatus) {
      case 'Connected':
      case 'Receiving data':
        color = Colors.green;
        break;
      case 'Connecting...':
        color = Colors.orange;
        break;
      case 'Connection error':
      case 'Failed to connect':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}