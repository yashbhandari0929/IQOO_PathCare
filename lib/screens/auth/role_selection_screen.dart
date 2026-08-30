// lib/screens/auth/role_selection_screen.dart
import 'package:flutter/material.dart';
import 'login_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Logo/Title
                  Icon(
                    Icons.local_hospital,
                    size: 80,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hospital Management',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select your role to continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 60),

                  // Patient Card
                  _buildRoleCard(
                    context: context,
                    title: 'Patient',
                    subtitle: 'Book appointments & manage health',
                    icon: Icons.person,
                    color: Colors.blue,
                    userType: 'patient',
                  ),
                  const SizedBox(height: 16),

                  // Doctor Card
                  _buildRoleCard(
                    context: context,
                    title: 'Doctor',
                    subtitle: 'Manage patients & appointments',
                    icon: Icons.medical_services,
                    color: Colors.pink,
                    userType: 'doctor',
                  ),
                  const SizedBox(height: 16),

                  // Supervisor Card
                  _buildRoleCard(
                    context: context,
                    title: 'Supervisor',
                    subtitle: 'Oversee operations & staff',
                    icon: Icons.supervisor_account,
                    color: Colors.teal,
                    userType: 'supervisor',
                  ),
                  const SizedBox(height: 16),

                  // Admin Card
                  _buildRoleCard(
                    context: context,
                    title: 'Admin',
                    subtitle: 'System management & analytics',
                    icon: Icons.admin_panel_settings,
                    color: Colors.orange,
                    userType: 'admin',
                  ),
                  const SizedBox(height: 40),

                  // Footer
                  Text(
                    'Secure & Confidential',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String userType,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LoginScreen(userType: userType),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.1),
                color.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              // Icon Container
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 16),
              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              // Arrow Icon
              Icon(Icons.arrow_forward_ios, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
