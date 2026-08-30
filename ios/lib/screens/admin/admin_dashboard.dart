// lib/screens/admin/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_doctor_screen.dart';
import 'manage_doctors_screen.dart';

final supabase = Supabase.instance.client;

class AdminDashboard extends StatefulWidget {
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  String adminUsername = 'Admin';
  bool isLoading = true;

  // Stats
  int totalDoctors = 0;
  int totalPatients = 0;
  int totalAppointments = 0;
  int activeRooms = 0;

  @override
  void initState() {
    super.initState();
    _loadAdminData();
    _loadStats();
  }

  Future<void> _loadAdminData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final data = await supabase
            .from('admins')
            .select('username')
            .eq('auth_id', user.id)
            .single();

        setState(() {
          adminUsername = data['username'] ?? 'Admin';
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading admin data: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      // Load total doctors
      final doctorsData = await supabase.from('doctors').select('id');

      // Load total patients (if you have a patients table)
      final patientsData = await supabase
          .from('patients')
          .select('id')
          .catchError((e) {
            print('No patients table: $e');
            return [] as List<Map<String, dynamic>>;
          });

      // Load total appointments (if you have an appointments table)
      final appointmentsData = await supabase
          .from('appointments')
          .select('id')
          .catchError((e) {
            print('No appointments table: $e');
            return [] as List<Map<String, dynamic>>;
          });

      setState(() {
        totalDoctors = doctorsData.length;
        totalPatients = patientsData.length;
        totalAppointments = appointmentsData.length;
        activeRooms = 12; // You can update this based on your rooms table
      });
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/role-selection',
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Dashboard'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              _loadAdminData();
              _loadStats();
            },
          ),
          IconButton(icon: Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadAdminData();
                await _loadStats();
              },
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome Card
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.shade400,
                            Colors.amber.shade400,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, $adminUsername!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Hospital Management System',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24),

                    // Stats Grid
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: [
                        _buildStatCard(
                          totalDoctors.toString(),
                          'Total Doctors',
                          Colors.blue,
                        ),
                        _buildStatCard(
                          totalPatients.toString(),
                          'Patients',
                          Colors.green,
                        ),
                        _buildStatCard(
                          totalAppointments.toString(),
                          'Appointments',
                          Colors.purple,
                        ),
                        _buildStatCard(
                          activeRooms.toString(),
                          'Active Rooms',
                          Colors.orange,
                        ),
                      ],
                    ),
                    SizedBox(height: 24),

                    Text(
                      'Management',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),

                    // Add Doctor Card
                    _buildActionCard(
                      'Add New Doctor',
                      'Register a new doctor in the system',
                      Icons.person_add,
                      Colors.pink,
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddDoctorScreen(),
                          ),
                        );

                        if (result == true && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Doctor has been successfully added to the system!',
                              ),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          _loadStats(); // Refresh stats
                        }
                      },
                    ),

                    // Manage Doctors Card - NOW FUNCTIONAL
                    _buildActionCard(
                      'Manage Doctors',
                      'View, edit, or remove doctors',
                      Icons.people,
                      Colors.blue,
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ManageDoctorsScreen(),
                          ),
                        );

                        // Refresh stats when returning from manage doctors screen
                        if (mounted) {
                          _loadStats();
                        }
                      },
                    ),

                    // Other Management Cards
                    _buildActionCard(
                      'Manage Rooms',
                      'Configure test rooms',
                      Icons.door_front_door,
                      Colors.green,
                    ),
                    _buildActionCard(
                      'Analytics',
                      'View hospital statistics',
                      Icons.analytics,
                      Colors.purple,
                    ),
                    _buildActionCard(
                      'Settings',
                      'System configuration',
                      Icons.settings,
                      Colors.orange,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatCard(String number, String label, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            number,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.arrow_forward_ios, size: 16),
        onTap:
            onTap ??
            () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$title - Coming soon!')));
            },
      ),
    );
  }
}
