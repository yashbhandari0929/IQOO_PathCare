import 'package:flutter/material.dart';
import 'hospital_3d_screen.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool notificationsEnabled = true;
  bool autoBackup = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings'), backgroundColor: Colors.orange),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _buildSectionHeader('General'),
          _buildSwitchTile(
            'Notifications',
            'Enable push notifications',
            Icons.notifications,
            notificationsEnabled,
            (value) {
              setState(() {
                notificationsEnabled = value;
              });
            },
          ),
          _buildSettingsTile(
            '3D Digital Twin',
            'View interactive 3D hospital model',
            Icons.view_in_ar,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const Hospital3DScreen()),
              );
            },
          ),

          SizedBox(height: 20),
          _buildSectionHeader('Data'),
          _buildSwitchTile(
            'Auto Backup',
            'Automatically backup data',
            Icons.backup,
            autoBackup,
            (value) {
              setState(() {
                autoBackup = value;
              });
            },
          ),
          _buildSettingsTile(
            'Clear Cache',
            'Free up storage space',
            Icons.delete_outline,
            () {
              _showClearCacheDialog();
            },
          ),
          SizedBox(height: 20),
          _buildSectionHeader('Account'),
          _buildSettingsTile(
            'Profile',
            'Edit your profile information',
            Icons.person,
            () {},
          ),

          SizedBox(height: 20),
          _buildSectionHeader('About'),
          _buildSettingsTile(
            'Version',
            'Blood Bank Management v1.0.0',
            Icons.info,
            null,
          ),

        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.orange,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    Function(bool) onChanged,
  ) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        secondary: Icon(icon, color: Colors.orange),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.orange,
      ),
    );
  }

  Widget _buildSettingsTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback? onTap,
  ) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.orange),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle),
        trailing: onTap != null
            ? Icon(Icons.arrow_forward_ios, size: 16)
            : null,
        onTap: onTap,
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Cache'),
        content: Text(
          'Are you sure you want to clear the cache? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Cache cleared successfully')),
              );
            },
            child: Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
