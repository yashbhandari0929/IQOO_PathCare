// lib/screens/admin/manage_doctors_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'edit_doctor_screen.dart';

final supabase = Supabase.instance.client;

class ManageDoctorsScreen extends StatefulWidget {
  const ManageDoctorsScreen({Key? key}) : super(key: key);

  @override
  State<ManageDoctorsScreen> createState() => _ManageDoctorsScreenState();
}

class _ManageDoctorsScreenState extends State<ManageDoctorsScreen> {
  List<dynamic> doctors = [];
  bool isLoading = true;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    try {
      setState(() => isLoading = true);

      // Select all columns to see what's available
      final data = await supabase.from('doctors').select();

      print('Doctor data: $data'); // Debug print to see column names

      setState(() {
        doctors = data;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading doctors: $e');
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load doctors: $e')));
      }
    }
  }

  Future<void> _deleteDoctor(Map<String, dynamic> doctor) async {
    final doctorName = doctor['full_name'] ?? doctor['name'] ?? 'this doctor';

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Doctor'),
        content: Text(
          'Are you sure you want to remove Dr. $doctorName from the system?\n\n'
          'This will:\n'
          '• Delete their account\n'
          '• Remove all their data\n'
          '• Cancel their appointments\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
                SizedBox(width: 16),
                Text('Deleting doctor...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      final doctorId = doctor['id'];
      final authId = doctor['auth_id'];

      // Step 1: Delete from doctors table
      await supabase.from('doctors').delete().eq('id', doctorId);

      // Step 2: Delete auth user if auth_id exists
      if (authId != null) {
        try {
          await supabase.rpc('delete_user', params: {'user_id': authId});
        } catch (e) {
          print('Could not delete auth user: $e');
        }
      }

      // Reload the list
      await _loadDoctors();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dr. $doctorName has been removed'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error deleting doctor: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete doctor: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<dynamic> get filteredDoctors {
    if (searchQuery.isEmpty) return doctors;

    return doctors.where((doctor) {
      final name = (doctor['full_name'] ?? doctor['name'] ?? '')
          .toString()
          .toLowerCase();
      final email = (doctor['email'] ?? '').toString().toLowerCase();
      final specialization = (doctor['specialization'] ?? '')
          .toString()
          .toLowerCase();
      final query = searchQuery.toLowerCase();

      return name.contains(query) ||
          email.contains(query) ||
          specialization.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Doctors'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDoctors),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search doctors...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => searchQuery = ''),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (value) => setState(() => searchQuery = value),
            ),
          ),

          // Doctors list
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredDoctors.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          searchQuery.isNotEmpty
                              ? Icons.search_off
                              : Icons.person_off,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'No doctors found matching "$searchQuery"'
                              : 'No doctors in the system',
                          style: TextStyle(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadDoctors,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredDoctors.length,
                      itemBuilder: (context, index) {
                        final doctor = filteredDoctors[index];
                        return _buildDoctorCard(doctor);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorCard(Map<String, dynamic> doctor) {
    final doctorName = doctor['full_name'] ?? doctor['name'] ?? 'Unknown';
    final firstLetter = doctorName.toString().substring(0, 1).toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    firstLetter,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Doctor info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dr. $doctorName',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (doctor['specialization'] != null)
                        Text(
                          doctor['specialization'],
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      if (doctor['email'] != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.email,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                doctor['email'],
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (doctor['phone'] != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.phone,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              doctor['phone'],
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditDoctorScreen(doctor: doctor),
                      ),
                    );

                    if (result == true) {
                      _loadDoctors();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Doctor updated successfully'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _deleteDoctor(doctor),
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
