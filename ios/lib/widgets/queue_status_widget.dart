// lib/widgets/queue_status_widget.dart

import 'package:flutter/material.dart';
import '../services/navigation_service.dart';

class QueueStatusWidget extends StatefulWidget {
  final String roomNumber;

  const QueueStatusWidget({
    Key? key,
    required this.roomNumber,
  }) : super(key: key);

  @override
  State<QueueStatusWidget> createState() => _QueueStatusWidgetState();
}

class _QueueStatusWidgetState extends State<QueueStatusWidget> {
  final NavigationService _navigationService = NavigationService();
  Map<String, dynamic>? _queueInfo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQueueInfo();
  }

  Future<void> _loadQueueInfo() async {
    setState(() => _isLoading = true);

    final info = await _navigationService.getRoomQueueInfo(widget.roomNumber);

    setState(() {
      _queueInfo = info;
      _isLoading = false;
    });
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'normal':
        return Colors.green;
      case 'busy':
        return Colors.orange;
      case 'very_busy':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'normal':
        return Icons.check_circle;
      case 'busy':
        return Icons.warning;
      case 'very_busy':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'normal':
        return 'Available';
      case 'busy':
        return 'Busy';
      case 'very_busy':
        return 'Very Busy';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Checking queue...', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    if (_queueInfo == null) {
      return SizedBox.shrink();
    }

    final queueCount = _queueInfo!['current_queue'] as int? ?? 0;
    final waitMinutes = _queueInfo!['wait_minutes'] as int? ?? 5;
    final status = _queueInfo!['queue_status'] as String? ?? 'normal';

    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final statusText = _getStatusText(status);

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withOpacity(0.1),
            statusColor.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              SizedBox(width: 8),
              Text(
                'Queue Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Spacer(),
              GestureDetector(
                onTap: _loadQueueInfo,
                child: Icon(Icons.refresh, color: Colors.blue, size: 20),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _buildInfoCard(
                  icon: Icons.people,
                  label: 'Waiting',
                  value: '$queueCount ${queueCount == 1 ? 'person' : 'people'}',
                  color: statusColor,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard(
                  icon: Icons.access_time,
                  label: 'Est. Wait',
                  value: '$waitMinutes min',
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(statusIcon, color: statusColor, size: 16),
                SizedBox(width: 8),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}