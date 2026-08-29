// lib/screens/patient/patient_appointments_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/booking_service.dart';
import 'appointment_detail_screen.dart';

final supabase = Supabase.instance.client;

class PatientAppointmentsScreen extends StatefulWidget {
  const PatientAppointmentsScreen({Key? key}) : super(key: key);

  @override
  State<PatientAppointmentsScreen> createState() =>
      _PatientAppointmentsScreenState();
}

class _PatientAppointmentsScreenState extends State<PatientAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final BookingService _bookingService = BookingService();

  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _completedAppointments = [];
  List<Map<String, dynamic>> _cancelledAppointments = [];

  bool _isLoading = true;
  String? _patientId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPatientId();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPatientId() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final patientData = await supabase
            .from('patients')
            .select('id')
            .eq('auth_id', userId)
            .single();

        setState(() {
          _patientId = patientData['id'] as String;
        });

        await _loadAppointments();
      }
    } catch (e) {
      print('Error loading patient ID: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAppointments() async {
    if (_patientId == null) return;

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Load all appointments
      final appointments = await _bookingService.getPatientAppointments(
        patientId: _patientId!,
      );

      List<Map<String, dynamic>> upcoming = [];
      List<Map<String, dynamic>> completed = [];
      List<Map<String, dynamic>> cancelled = [];

      for (var appointment in appointments) {
        final appointmentDate = DateTime.parse(appointment['appointment_date'] as String);
        final status = appointment['status'] as String;

        if (status == 'cancelled') {
          // Only show cancelled from last 7 days
          final cancelledAt = appointment['cancelled_at'] != null
              ? DateTime.parse(appointment['cancelled_at'] as String)
              : null;

          if (cancelledAt != null &&
              now.difference(cancelledAt).inDays <= 7) {
            cancelled.add(appointment);
          }
        } else if (status == 'completed') {
          completed.add(appointment);
        } else if (appointmentDate.isAfter(today) ||
            appointmentDate.isAtSameMomentAs(today)) {
          upcoming.add(appointment);
        }
      }

      setState(() {
        _upcomingAppointments = upcoming;
        _completedAppointments = completed;
        _cancelledAppointments = cancelled;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading appointments: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Appointment?'),
        content: Text(
          'Are you sure you want to cancel this appointment? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _bookingService.cancelAppointment(appointmentId);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Appointment cancelled successfully'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadAppointments();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel appointment'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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

  Future<void> _navigateToDetail(String appointmentId) async {
    // Navigate and wait for result
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AppointmentDetailScreen(
          appointmentId: appointmentId,
        ),
      ),
    );

    // If detail screen returns true, refresh the list
    if (result == true) {
      await _loadAppointments();
    }
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appointment, bool canCancel) {
    final appointmentTests = appointment['appointment_tests'] as List? ?? [];
    final testCount = appointmentTests.length;
    final status = appointment['status'] as String;

    // Count completed tests
    final completedTests = appointmentTests
        .where((test) => test['status'] == 'completed')
        .length;

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.blue;
        statusIcon = Icons.schedule;
    }

    return GestureDetector(
      onTap: () => _navigateToDetail(appointment['id']),
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: statusColor.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 24),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(appointment['appointment_date']),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey),
                          SizedBox(width: 4),
                          Text(
                            _formatTime(appointment['appointment_time']),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
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
                Icon(Icons.science, size: 16, color: Colors.grey[600]),
                SizedBox(width: 8),
                Text(
                  '$testCount test${testCount != 1 ? 's' : ''} scheduled',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
                if (status == 'scheduled' && completedTests > 0) ...[
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Text(
                      '$completedTests/$testCount done',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                Spacer(),
                TextButton(
                  onPressed: () => _navigateToDetail(appointment['id']),
                  child: Text('View Details'),
                ),
              ],
            ),
            if (canCancel) ...[
              SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelAppointment(appointment['id']),
                  icon: Icon(Icons.cancel_outlined, size: 18),
                  label: Text('Cancel Appointment'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[300]),
          SizedBox(height: 20),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.blue,
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : RefreshIndicator(
            onRefresh: _loadAppointments,
            child: TabBarView(
              controller: _tabController,
              children: [
                // Upcoming Tab
                _upcomingAppointments.isEmpty
                    ? _buildEmptyState(
                  'No upcoming appointments',
                  Icons.calendar_today,
                )
                    : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _upcomingAppointments.length,
                  itemBuilder: (context, index) {
                    return _buildAppointmentCard(
                      _upcomingAppointments[index],
                      true, // Can cancel
                    );
                  },
                ),

                // Completed Tab
                _completedAppointments.isEmpty
                    ? _buildEmptyState(
                  'No completed appointments',
                  Icons.check_circle_outline,
                )
                    : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _completedAppointments.length,
                  itemBuilder: (context, index) {
                    return _buildAppointmentCard(
                      _completedAppointments[index],
                      false, // Cannot cancel
                    );
                  },
                ),

                // Cancelled Tab
                _cancelledAppointments.isEmpty
                    ? _buildEmptyState(
                  'No cancelled appointments',
                  Icons.cancel_outlined,
                )
                    : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _cancelledAppointments.length,
                  itemBuilder: (context, index) {
                    return _buildAppointmentCard(
                      _cancelledAppointments[index],
                      false, // Cannot cancel
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}