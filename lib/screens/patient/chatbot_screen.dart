// lib/screens/patient/chatbot_screen.dart
// GOOGLE GEMINI API - 100% FREE VERSION - FIXED

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ChatbotScreen extends StatefulWidget {
  final String patientName;

  const ChatbotScreen({
    Key? key,
    required this.patientName,
  }) : super(key: key);

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  late AnimationController _animationController;
  List<ChatConversation> _conversationHistory = [];
  String _currentConversationId = '';
  bool _showHistory = false;

  // ============= GOOGLE GEMINI API KEY =============
  // Get your FREE API key from: https://aistudio.google.com/app/apikey
  // Replace the key below (it should start with "AIzaSy")
  final String _geminiApiKey = 'AIzaSyC2CUUHFECAuaQKhDx6NgWLPL5yj0LiDBw'; // PUT YOUR KEY HERE
  // =================================================

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat();

    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final conversationsJson = prefs.getStringList('chat_conversations') ?? [];

    setState(() {
      _conversationHistory = conversationsJson
          .map((json) => ChatConversation.fromJson(jsonDecode(json)))
          .toList();

      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final todayConversation = _conversationHistory.firstWhere(
            (conv) => conv.date.startsWith(todayStr),
        orElse: () {
          final newConv = ChatConversation(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: 'Chat - $todayStr',
            date: DateTime.now().toIso8601String(),
            messages: [],
          );
          _conversationHistory.insert(0, newConv);
          return newConv;
        },
      );

      _currentConversationId = todayConversation.id;
      _messages.clear();
      _messages.addAll(todayConversation.messages);

      if (_messages.isEmpty) {
        _messages.add(ChatMessage(
          text:
          'Hello ${widget.patientName}! 👋\n\nI\'m your healthcare assistant powered by Google Gemini. I can help you with:\n\n• Understanding your test results\n• Booking appointments\n• Health tips and advice\n• Medication information\n\nHow can I assist you today?',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _saveCurrentConversation();
      }
    });

    _scrollToBottom();
  }

  Future<void> _saveCurrentConversation() async {
    final prefs = await SharedPreferences.getInstance();
    final conversationIndex = _conversationHistory
        .indexWhere((conv) => conv.id == _currentConversationId);

    if (conversationIndex != -1) {
      _conversationHistory[conversationIndex].messages.clear();
      _conversationHistory[conversationIndex].messages.addAll(_messages);
      _conversationHistory[conversationIndex].date =
          DateTime.now().toIso8601String();
    }

    final conversationsJson = _conversationHistory
        .map((conv) => jsonEncode(conv.toJson()))
        .toList();

    await prefs.setStringList('chat_conversations', conversationsJson);
  }

  Future<void> _createNewConversation() async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final newConversation = ChatConversation(
      id: now.millisecondsSinceEpoch.toString(),
      title: 'Chat - $dateStr $timeStr',
      date: now.toIso8601String(),
      messages: [],
    );

    setState(() {
      _conversationHistory.insert(0, newConversation);
      _currentConversationId = newConversation.id;
      _messages.clear();
      _messages.add(ChatMessage(
        text:
        'Hello ${widget.patientName}! 👋\n\nI\'m your healthcare assistant. How can I help you today?',
        isUser: false,
        timestamp: DateTime.now(),
      ));
      _showHistory = false;
    });

    await _saveCurrentConversation();
    _scrollToBottom();
  }

  Future<void> _loadConversation(String conversationId) async {
    final conversation = _conversationHistory.firstWhere(
          (conv) => conv.id == conversationId,
      orElse: () => _conversationHistory.first,
    );

    setState(() {
      _currentConversationId = conversationId;
      _messages.clear();
      _messages.addAll(conversation.messages);
      _showHistory = false;
    });

    _scrollToBottom();
  }

  Future<void> _deleteConversation(String conversationId) async {
    setState(() {
      _conversationHistory.removeWhere((conv) => conv.id == conversationId);
      if (_currentConversationId == conversationId) {
        if (_conversationHistory.isNotEmpty) {
          _currentConversationId = _conversationHistory.first.id;
          _messages.clear();
          _messages.addAll(_conversationHistory.first.messages);
        } else {
          _createNewConversation();
        }
      }
    });

    await _saveCurrentConversation();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Conversation deleted'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    final userMessage = ChatMessage(
      text: message,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isTyping = true;
    });

    await _saveCurrentConversation();
    _messageController.clear();
    _scrollToBottom();

    try {
      final response = await _callGeminiAPI(message);
      final botMessage = ChatMessage(
        text: response,
        isUser: false,
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(botMessage);
        _isTyping = false;
      });

      await _saveCurrentConversation();
      _scrollToBottom();
    } catch (e) {
      print('❌ ERROR: $e');

      final errorMsg = ChatMessage(
        text: _getErrorMessage(e.toString()),
        isUser: false,
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(errorMsg);
        _isTyping = false;
      });

      await _saveCurrentConversation();
    }
  }

  String _getErrorMessage(String error) {
    if (_geminiApiKey == 'AIzaSyDxxxxxxxxxxxxxxxxxxxxxxxxxxxxx') {
      return '⚠️ Please Add Your API Key!\n\nSteps:\n1. Go to https://aistudio.google.com/app/apikey\n2. Click "Create API Key"\n3. Copy the key (starts with AIzaSy)\n4. Replace line 26 in chatbot_screen.dart\n5. Hot restart the app';
    }

    if (!_geminiApiKey.startsWith('AIzaSy')) {
      return '⚠️ Wrong API Key!\n\nYou\'re using a Grok key (xai-...) but this app needs a Gemini key (AIzaSy...).\n\nGet FREE Gemini key:\nhttps://aistudio.google.com/app/apikey';
    }

    if (error.contains('403') || error.contains('400')) {
      return '🔑 Invalid API Key!\n\nYour Gemini API key is not working.\n\nSolution:\n1. Go to https://aistudio.google.com/app/apikey\n2. Create a NEW API key\n3. Update the key in the code';
    }

    if (error.contains('404')) {
      return '⚠️ Model Not Found!\n\nThe API endpoint has been updated. Please check the code for the latest model name.';
    }

    if (error.contains('429')) {
      return '⏱️ Rate Limit!\n\nToo many requests. Wait 1 minute and try again.';
    }

    if (error.contains('SocketException')) {
      return '📡 No Internet!\n\nCheck your connection and try again.';
    }

    return '❌ Error: ${error.substring(0, error.length > 150 ? 150 : error.length)}';
  }

  Future<String> _callGeminiAPI(String userMessage) async {
    print('\n🚀 Calling Gemini API...');
    print('Key starts with: ${_geminiApiKey.substring(0, 7)}...');

    if (_geminiApiKey == 'AIzaSyDxxxxxxxxxxxxxxxxxxxxxxxxxxxxx') {
      throw Exception('Please add your Gemini API key');
    }

    if (!_geminiApiKey.startsWith('AIzaSy')) {
      throw Exception('Invalid API key format. Gemini keys start with AIzaSy');
    }

    // ✅ WORKING: Updated to Gemini 2.5 Flash (gemini-1.5-flash is deprecated)
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey';

    final body = {
      'contents': [
        {
          'parts': [
            {
              'text': 'You are a helpful healthcare assistant. Provide accurate, caring medical information. Keep responses concise. Always remind users to consult healthcare professionals.\n\nUser: $userMessage'
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 1000,
      }
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(Duration(seconds: 30));

      print('Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates'][0]['content']['parts'][0]['text'];
        print('✅ Success!');
        return text;
      } else {
        print('❌ Error: ${response.body}');
        throw Exception('API Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('💥 Exception: $e');
      rethrow;
    }
  }

  void _scrollToBottom() {
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.grey[800]),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade400, Colors.blue.shade700],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.psychology_outlined, color: Colors.white, size: 24),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Health Assistant', style: TextStyle(color: Colors.grey[800], fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    SizedBox(width: 6),
                    Text('Powered by Gemini', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(icon: Icon(Icons.history, color: Colors.grey[800]), onPressed: () => setState(() => _showHistory = !_showHistory)),
          IconButton(icon: Icon(Icons.add, color: Colors.grey[800]), onPressed: _createNewConversation),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.all(16),
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length && _isTyping) {
                      return _buildTypingIndicator();
                    }
                    return _buildMessageBubble(_messages[index]);
                  },
                ),
              ),
              _buildInputArea(),
            ],
          ),
          if (_showHistory) Positioned(top: 0, right: 0, bottom: 0, child: _buildHistorySidebar()),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
      ),
      padding: EdgeInsets.all(12),
      child: SafeArea(
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
              child: IconButton(icon: Icon(Icons.add, color: Colors.grey[700]), onPressed: _showQuickActions),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(24)),
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Ask me anything...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  maxLines: null,
                ),
              ),
            ),
            SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade700]),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.send_rounded, color: Colors.white),
                onPressed: () => _sendMessage(_messageController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade700]),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.psychology_outlined, color: Colors.white, size: 20),
            ),
            SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser ? Colors.blue : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isUser ? 20 : 4),
                      topRight: Radius.circular(isUser ? 4 : 20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2))],
                  ),
                  child: Text(message.text, style: TextStyle(color: isUser ? Colors.white : Colors.grey[800], fontSize: 15)),
                ),
                SizedBox(height: 4),
                Text(_formatTime(message.timestamp), style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
          if (isUser) ...[
            SizedBox(width: 12),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: Colors.blue.shade100, shape: BoxShape.circle),
              child: Icon(Icons.person, color: Colors.blue.shade700, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade700]),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.psychology_outlined, color: Colors.white, size: 20),
          ),
          SizedBox(width: 12),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => Padding(
                padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
                child: _buildDot(i),
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final value = ((_animationController.value - index * 0.2) % 1.0);
        final opacity = (value < 0.5 ? value * 2 : (1 - value) * 2).clamp(0.3, 1.0);
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: Colors.grey.withOpacity(opacity), shape: BoxShape.circle),
        );
      },
    );
  }

  Widget _buildHistorySidebar() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.75,
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.history, color: Colors.blue),
                SizedBox(width: 12),
                Text('Chat History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Spacer(),
                IconButton(icon: Icon(Icons.close), onPressed: () => setState(() => _showHistory = false)),
              ],
            ),
          ),
          Expanded(
            child: _conversationHistory.isEmpty
                ? Center(child: Text('No previous chats', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
              itemCount: _conversationHistory.length,
              itemBuilder: (context, index) => _buildConversationTile(_conversationHistory[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(ChatConversation conversation) {
    final isActive = conversation.id == _currentConversationId;
    return ListTile(
      tileColor: isActive ? Colors.blue.shade50 : null,
      leading: Icon(Icons.chat_bubble_outline, color: isActive ? Colors.blue : Colors.grey),
      title: Text(conversation.title, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text('${conversation.messages.length} messages'),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, color: Colors.red[300]),
        onPressed: () => _showDeleteConfirmation(conversation.id),
      ),
      onTap: () => _loadConversation(conversation.id),
    );
  }

  void _showDeleteConfirmation(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Conversation'),
        content: Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteConversation(id);
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showQuickActions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            _buildQuickActionButton('Book Appointment', Icons.calendar_today, 'I want to book an appointment'),
            _buildQuickActionButton('Health Tips', Icons.favorite, 'Give me some health tips'),
            _buildQuickActionButton('Medication Info', Icons.medical_services, 'Tell me about medications'),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(String title, IconData icon, String message) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(title),
      trailing: Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        Navigator.pop(context);
        _sendMessage(message);
      },
    );
  }

  String _formatTime(DateTime time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) return 'Today';
    if (messageDate == yesterday) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }
}

// Models
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({required this.text, required this.isUser, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text'],
    isUser: json['isUser'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}

class ChatConversation {
  final String id;
  final String title;
  String date;
  final List<ChatMessage> messages;

  ChatConversation({required this.id, required this.title, required this.date, required this.messages});

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatConversation.fromJson(Map<String, dynamic> json) => ChatConversation(
    id: json['id'],
    title: json['title'],
    date: json['date'],
    messages: (json['messages'] as List).map((m) => ChatMessage.fromJson(m)).toList(),
  );
}