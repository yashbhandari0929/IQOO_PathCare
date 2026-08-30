// lib/screens/patient/appointment_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/booking_service.dart';
import '../../services/navigation_service.dart';

final supabase = Supabase.instance.client;

class AppointmentDetailScreen extends StatefulWidget {
  final String appointmentId;

  const AppointmentDetailScreen({Key? key, required this.appointmentId})
    : super(key: key);

  @override
  State<AppointmentDetailScreen> createState() =>
      _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  Map<String, dynamic>? _appointment;
  List<Map<String, dynamic>> _tests = [];
  bool _isLoading = true;
  final BookingService _bookingService = BookingService();
  final NavigationService _navigationService = NavigationService();

  // Queue position tracking for each test
  Map<String, int> _testQueuePositions = {}; // testId -> position

  @override
  void initState() {
    super.initState();
    _loadAppointmentDetails();
  }

  Future<void> _loadAppointmentDetails() async {
    setState(() => _isLoading = true);

    try {
      // Load appointment
      final appointmentData = await supabase
          .from('appointments')
          .select()
          .eq('id', widget.appointmentId)
          .single();

      // Load appointment tests with test details and room info
      final appointmentTests = await supabase
          .from('appointment_tests')
          .select(
            '*, tests(*), test_rooms!appointment_tests_assigned_room_id_fkey(*)',
          )
          .eq('appointment_id', widget.appointmentId)
          .order('test_order');

      // Load queue positions for all reached tests
      Map<String, int> positions = {};
      for (var test in appointmentTests) {
        final testStatus = test['status'] as String?;
        if (testStatus == 'reached') {
          final roomId = test['assigned_room_id'] as String?;
          final testId = test['id'] as String;

          if (roomId != null) {
            final result = await _navigationService.computeQueuePosition(
              roomId: roomId,
              appointmentTestId: testId,
            );
            positions[testId] = result.position;
          }
        }
      }

      setState(() {
        _appointment = appointmentData;
        _tests = List<Map<String, dynamic>>.from(appointmentTests);
        _testQueuePositions = positions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markTestAsCompleted(
    String appointmentTestId,
    int testIndex,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark Test as Completed?'),
        content: Text(
          'Have you completed this test? This will update the test status.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Yes, Completed',
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator()),
      );

      final success = await _bookingService.completeTest(
        appointmentTestId: appointmentTestId,
        appointmentId: widget.appointmentId,
      );

      Navigator.pop(context);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test marked as completed ✓'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        await _loadAppointmentDetails();

        if (_appointment?['status'] == 'completed') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '🎉 All tests completed! Appointment is now complete.',
              ),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 3),
            ),
          );

          await Future.delayed(Duration(seconds: 2));
          Navigator.pop(context, true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update test status'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${date.day} ${months[date.month - 1]}, ${date.year}';
  }

  String _formatTime(String timeStr) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'in_progress':
      case 'reached':
        return Colors.blue;
      default:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      case 'pending':
        return Icons.hourglass_empty;
      case 'in_progress':
      case 'reached':
        return Icons.play_circle;
      default:
        return Icons.schedule;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Appointment Details'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_appointment == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Appointment Details'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: Center(child: Text('Appointment not found')),
      );
    }

    final status = _appointment!['status'] as String;
    final statusColor = _getStatusColor(status);
    final isAppointmentActive =
        status == 'scheduled' || status == 'in_progress';

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Appointment Details'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _loadAppointmentDetails,
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: statusColor, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getStatusIcon(status), color: statusColor),
                      SizedBox(width: 8),
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24),

              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue, Colors.blue.shade300],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: Colors.white,
                          size: 28,
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Appointment Date',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                _formatDate(_appointment!['appointment_date']),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.access_time, color: Colors.white, size: 28),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Start Time',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                _formatTime(_appointment!['appointment_time']),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),

              if (isAppointmentActive) ...[
                _buildProgressIndicator(),
                SizedBox(height: 24),
              ],

              Text(
                'Tests (${_tests.length})',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: 12),

              ...List.generate(_tests.length, (index) {
                final appointmentTest = _tests[index];
                final test = appointmentTest['tests'] as Map<String, dynamic>?;
                final testStatus =
                    appointmentTest['status'] as String? ?? 'pending';
                final testStatusColor = _getStatusColor(testStatus);
                final testId = appointmentTest['id'] as String;

                final queuePosition = _testQueuePositions[testId] ?? 999;
                final isFirstInQueue = queuePosition == 1;

                final canMarkComplete =
                    isAppointmentActive &&
                    testStatus == 'reached' &&
                    isFirstInQueue;

                return Container(
                  margin: EdgeInsets.only(bottom: 12),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: testStatusColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: testStatusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: testStatus == 'completed'
                                  ? Icon(
                                      Icons.check,
                                      color: Colors.green,
                                      size: 24,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  test?['name'] ?? 'Unknown Test',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                if (test?['description'] != null) ...[
                                  SizedBox(height: 4),
                                  Text(
                                    test!['description'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: testStatusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              testStatus.toUpperCase(),
                              style: TextStyle(
                                color: testStatusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Divider(),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          SizedBox(width: 4),
                          Text(
                            test?['room_number'] ?? 'TBD',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                          SizedBox(width: 16),
                          Icon(Icons.stairs, size: 16, color: Colors.grey[600]),
                          SizedBox(width: 4),
                          Text(
                            test?['floor'] ?? 'TBD',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                          Spacer(),
                          if (test?['price'] != null)
                            Text(
                              '₹${(test!['price'] as num).toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                        ],
                      ),

                      if (testStatus == 'reached' && queuePosition != 999) ...[
                        SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isFirstInQueue
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isFirstInQueue
                                  ? Colors.green.shade300
                                  : Colors.orange.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isFirstInQueue
                                    ? Icons.front_hand
                                    : Icons.people,
                                color: isFirstInQueue
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                isFirstInQueue
                                    ? 'You are next in queue'
                                    : 'Position $queuePosition in queue',
                                style: TextStyle(
                                  color: isFirstInQueue
                                      ? Colors.green.shade700
                                      : Colors.orange.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (canMarkComplete) ...[
                        SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _markTestAsCompleted(testId, index),
                            icon: Icon(Icons.check_circle_outline, size: 18),
                            label: Text('Mark as Completed'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],

                      if (testStatus == 'reached' && !isFirstInQueue) ...[
                        SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.lock_clock,
                                color: Colors.grey.shade600,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Wait for your turn - ${queuePosition - 1} patient(s) ahead',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (testStatus == 'completed') ...[
                        SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Test Completed',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),

              if (_appointment!['special_instructions'] != null &&
                  (_appointment!['special_instructions'] as String)
                      .isNotEmpty) ...[
                SizedBox(height: 24),
                Text(
                  'Special Instructions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Text(
                    _appointment!['special_instructions'],
                    style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                  ),
                ),
              ],

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final completedTests = _tests
        .where((test) => test['status'] == 'completed')
        .length;
    final totalTests = _tests.length;
    final progress = totalTests > 0 ? completedTests / totalTests : 0.0;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              Text(
                '$completedTests / $totalTests tests completed',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                progress == 1.0 ? Colors.green : Colors.blue,
              ),
            ),
          ),
          if (progress == 1.0) ...[
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.celebration, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  'All tests completed! 🎉',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
