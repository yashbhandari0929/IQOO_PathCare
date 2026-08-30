import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../chat/ChatScreen.dart';

class PatientHelpChatScreen extends StatefulWidget {
  const PatientHelpChatScreen({Key? key}) : super(key: key);

  @override
  State<PatientHelpChatScreen> createState() => _PatientHelpChatScreenState();
}

class _PatientHelpChatScreenState extends State<PatientHelpChatScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  Map<String, dynamic>? _patientData;
  Map<String, dynamic>? _supervisorData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final authUser = supabase.auth.currentUser;
      if (authUser == null) return;

      // Get patient data
      final patient = await supabase
          .from('patients')
          .select('id, full_name')
          .eq('auth_id', authUser.id)
          .single();

      setState(() {
        _patientData = patient;
      });

      // Get first available supervisor (or you can assign specific supervisor)
      final supervisor = await supabase
          .from('supervisors')
          .select('id, name')
          .limit(1)
          .single();

      setState(() {
        _supervisorData = supervisor;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackbar('Unable to connect to support', isError: true);
    }
  }

  void _startChat() {
    if (_patientData == null || _supervisorData == null) {
      _showSnackbar('Unable to start chat', isError: true);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          senderId: _patientData!['id'],
          senderName: _patientData!['full_name'],
          receiverId: _supervisorData!['id'],
          receiverName: _supervisorData!['name'],
        ),
      ),
    );
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.support_agent,
                      size: 80,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Need Help?',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Chat with our support team for assistance with:\n• Report access\n• Appointment queries\n• Technical issues\n• General help',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _startChat,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Chat with Supervisor',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
