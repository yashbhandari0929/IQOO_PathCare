import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/doctor_service.dart'; // Ensure this path is correct

final _supabase = Supabase.instance.client;

class DoctorSettingsScreen extends StatefulWidget {
  const DoctorSettingsScreen({Key? key}) : super(key: key);

  @override
  State<DoctorSettingsScreen> createState() => _DoctorSettingsScreenState();
}

class _DoctorSettingsScreenState extends State<DoctorSettingsScreen> {
  final DoctorService _doctorService = DoctorService();

  Map<String, dynamic>? _doctorData;
  Map<String, dynamic>? _dailyStats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ── Loaders ────────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    // Fetch profile and daily stats in parallel
    await _loadDoctorData();
    if (_doctorData != null) {
      await _loadDailyStats(_doctorData!['id']);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadDoctorData() async {
    try {
      // Uses the getCurrentDoctor method from your DoctorService
      final data = await _doctorService.getCurrentDoctor();
      if (mounted) setState(() => _doctorData = data);
    } catch (e) {
      debugPrint('Error loading doctor data: $e');
    }
  }

  Future<void> _loadDailyStats(String doctorId) async {
    try {
      // Uses the getDailyStats method from your DoctorService
      final stats = await _doctorService.getDailyStats(doctorId);
      if (mounted) setState(() => _dailyStats = stats);
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/role-selection',
          (route) => false,
        );
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Map data from DB columns shown in your image
    final String fullName = _doctorData?['full_name'] ?? 'Doctor';
    final String specialization = _doctorData?['specialization'] ?? 'General';
    final String email = _doctorData?['email'] ?? 'N/A';
    final String phone = _doctorData?['phone'] ?? 'N/A';
    final String license = _doctorData?['license_number'] ?? 'N/A';
    final String department = _doctorData?['department'] ?? 'N/A';

    // Stats from daily_stats RPC
    final int attendedToday = _dailyStats?['patients_attended'] ?? 0;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // ── Profile Header ───────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue, Colors.blue.shade800],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.person,
                              size: 50,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Dr. $fullName',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            specialization,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Stats Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$attendedToday patients attended today',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Detailed Info Cards ──────────────────────────────────
                    _buildInfoCard('Email', email, Icons.email_outlined),
                    _buildInfoCard('Phone', phone, Icons.phone_outlined),
                    _buildInfoCard(
                      'License No.',
                      license,
                      Icons.badge_outlined,
                    ),
                    _buildInfoCard(
                      'Department',
                      department,
                      Icons.local_hospital_outlined,
                    ),

                    // Display status if active
                    if (_doctorData?['is_active'] == true)
                      _buildInfoCard(
                        'Status',
                        'Active Profile',
                        Icons.check_circle_outline,
                      ),

                    const SizedBox(height: 24),

                    // ── Logout ──────────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
