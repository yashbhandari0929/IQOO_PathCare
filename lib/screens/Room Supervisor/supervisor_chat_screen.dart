import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../chat/ChatScreen.dart';

class SupervisorChatScreen extends StatefulWidget {
  const SupervisorChatScreen({Key? key}) : super(key: key);

  @override
  State<SupervisorChatScreen> createState() => _SupervisorChatScreenState();
}

class _SupervisorChatScreenState extends State<SupervisorChatScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  Map<String, dynamic>? _supervisorData;
  List<Map<String, dynamic>> _patients = [];
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

      // Get supervisor data
      final supervisor = await supabase
          .from('supervisors')
          .select('id, name')
          .eq('auth_id', authUser.id)
          .single();

      setState(() {
        _supervisorData = supervisor;
      });

      await _loadPatients();
    } catch (e) {
      print('Error loading supervisor: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPatients() async {
    try {
      if (_supervisorData == null) return;

      // Get unique patients who messaged this supervisor
      final messages = await supabase
          .from('messages')
          .select('sender_id, sender_name')
          .eq('receiver_id', _supervisorData!['id'])
          .order('timestamp', ascending: false);

      final uniquePatients = <String, Map<String, dynamic>>{};
      for (var msg in messages) {
        uniquePatients[msg['sender_id']] = {
          'id': msg['sender_id'],
          'name': msg['sender_name'],
        };
      }

      setState(() {
        _patients = uniquePatients.values.toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading patients: $e');
      setState(() => _isLoading = false);
    }
  }

  void _startChat(Map<String, dynamic> patient) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          senderId: _supervisorData!['id'],
          senderName: _supervisorData!['name'],
          receiverId: patient['id'],
          receiverName: patient['name'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Messages'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPatients,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _patients.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: _loadPatients,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _patients.length,
          itemBuilder: (context, index) {
            final patient = _patients[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.withOpacity(0.2),
                  child: Text(
                    patient['name'][0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  patient['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: const Text('Tap to chat'),
                trailing: const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.teal,
                ),
                onTap: () => _startChat(patient),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadPatients,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When patients message you, they will appear here',
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadPatients,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}