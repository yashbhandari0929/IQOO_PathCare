// lib/screens/doctor/doctor_dashboard.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

final supabase = Supabase.instance.client;

class DoctorDashboard extends StatefulWidget {
  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  String doctorName = 'Doctor';
  String doctorId = '';
  String specialization = '';
  String department = '';
  List<dynamic> appointments = [];
  bool isLoading = true;
  RealtimeChannel? _appointmentsChannel;

  @override
  void initState() {
    super.initState();
    _loadDoctorData();
  }

  Future<void> _loadDoctorData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final data = await supabase
            .from('doctors')
            .select('id, full_name, specialization, department')
            .eq('auth_id', user.id)
            .single();

        setState(() {
          doctorName = data['full_name'] ?? 'Doctor';
          doctorId = data['id'];
          specialization = data['specialization'] ?? '';
          department = data['department'] ?? '';
        });

        await _loadAppointments();
        _setupRealtimeListener();
      }
    } catch (e) {
      print('Error loading doctor data: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadAppointments() async {
    try {
      print('🔵 Loading appointments...');

      // Load appointments with patient details
      final data = await supabase
          .from('appointments')
          .select('''
            *,
            patients (
              full_name,
              phone,
              email
            )
          ''')
          .eq('status', 'scheduled')
          .gte('appointment_date', DateTime.now().toIso8601String().split('T')[0])
          .order('appointment_date')
          .order('appointment_time');

      setState(() {
        appointments = data;
        isLoading = false;
      });

      print('✅ Loaded ${appointments.length} appointments');
    } catch (e) {
      print('❌ Error loading appointments: $e');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load appointments')),
      );
    }
  }

  void _setupRealtimeListener() {
    print('🔔 Setting up realtime listener...');

    _appointmentsChannel = supabase
        .channel('doctor_appointments_channel')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'appointments',
      callback: (payload) {
        print('🔔 NEW APPOINTMENT DETECTED!');
        print('Payload: $payload');

        // Reload appointments
        _loadAppointments();

        // Show notification
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.notifications_active, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'New appointment booked!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'appointments',
      callback: (payload) {
        print('🔄 Appointment updated');
        _loadAppointments();
      },
    )
        .subscribe();

    print('✅ Realtime listener setup complete');
  }

  @override
  void dispose() {
    print('🗑️ Cleaning up realtime listener');
    _appointmentsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _logout() async {
    _appointmentsChannel?.unsubscribe();
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/role-selection',
            (route) => false,
      );
    }
  }

  void _showAppointmentDetails(Map<String, dynamic> appointment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          final patient = appointment['patients'];
          final aptDate = DateTime.parse(appointment['appointment_date']);

          return SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  // Title
                  Text(
                    'Appointment Details',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 24),
                  // Patient info
                  _buildInfoRow(
                    Icons.person,
                    'Patient',
                    patient['full_name'] ?? 'N/A',
                  ),
                  SizedBox(height: 16),
                  _buildInfoRow(
                    Icons.phone,
                    'Phone',
                    patient['phone'] ?? 'N/A',
                  ),
                  SizedBox(height: 16),
                  _buildInfoRow(
                    Icons.email,
                    'Email',
                    patient['email'] ?? 'N/A',
                  ),
                  SizedBox(height: 16),
                  _buildInfoRow(
                    Icons.calendar_today,
                    'Date',
                    DateFormat('EEEE, MMMM d, y').format(aptDate),
                  ),
                  SizedBox(height: 16),
                  _buildInfoRow(
                    Icons.access_time,
                    'Time',
                    appointment['appointment_time'] ?? 'N/A',
                  ),
                  SizedBox(height: 16),
                  _buildInfoRow(
                    Icons.medical_services,
                    'Tests',
                    '${(appointment['test_ids'] as List?)?.length ?? 0} tests booked',
                  ),
                  if (appointment['special_instructions'] != null &&
                      appointment['special_instructions'].isNotEmpty) ...[
                    SizedBox(height: 16),
                    _buildInfoRow(
                      Icons.note,
                      'Instructions',
                      appointment['special_instructions'],
                    ),
                  ],
                  SizedBox(height: 24),
                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // TODO: Mark as completed
                            Navigator.pop(context);
                          },
                          icon: Icon(Icons.check_circle),
                          label: Text('Complete'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // TODO: Cancel appointment
                            Navigator.pop(context);
                          },
                          icon: Icon(Icons.cancel),
                          label: Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: BorderSide(color: Colors.red),
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.pink, size: 20),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Doctor Dashboard'),
        backgroundColor: Colors.pink,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadAppointments,
          ),
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.pink.shade400, Colors.red.shade400],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.medical_services,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dr. $doctorName',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              specialization,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            if (department.isNotEmpty) ...[
                              Text(
                                department,
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Stats
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      '${appointments.length}',
                      'Scheduled',
                      Icons.schedule,
                      Colors.blue,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      '0',
                      'Completed Today',
                      Icons.check_circle,
                      Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            // Appointments List
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Today\'s Appointments',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Live Updates',
                          style: TextStyle(
                            color: Colors.green.shade900,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            appointments.isEmpty
                ? Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_available,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No appointments scheduled',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
                : ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 16),
              itemCount: appointments.length,
              itemBuilder: (context, index) {
                final apt = appointments[index];
                final patient = apt['patients'];
                final aptDate = DateTime.parse(apt['appointment_date']);

                return Card(
                  margin: EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: () => _showAppointmentDetails(apt),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // Number badge
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.pink,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          SizedBox(width: 16),
                          // Patient info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patient['full_name'] ?? 'Unknown Patient',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                                    SizedBox(width: 4),
                                    Text(
                                      DateFormat('MMM dd').format(aptDate),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Icon(Icons.access_time, size: 14, color: Colors.grey),
                                    SizedBox(width: 4),
                                    Text(
                                      apt['appointment_time'] ?? 'N/A',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Tests badge
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${(apt['test_ids'] as List?)?.length ?? 0} tests',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String value, String label, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}