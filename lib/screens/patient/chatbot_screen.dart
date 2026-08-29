// lib/screens/patient/chatbot_screen.dart
// GOOGLE GEMINI API - 100% FREE VERSION - FIXED

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
class ChatbotScreen extends StatefulWidget {
  final String patientName;

  const ChatbotScreen({Key? key, required this.patientName}) : super(key: key);

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

  // Removed Gemini API Key, backend handles LLM now.
  String _userRole = 'patient';
  String _userId = '';
  final _supabase = Supabase.instance.client;
  String? _pendingFilePath;
  String? _pendingFileName;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat();

    _initializeUserAndLoadHistory();
  }

  Future<void> _initializeUserAndLoadHistory() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      _userId = user.id;
      try {
        final tables = ['patients', 'doctors', 'admins', 'supervisors'];
        String foundRole = 'patient';
        for (final table in tables) {
          final res = await _supabase
              .from(table)
              .select('id')
              .eq('auth_id', _userId)
              .maybeSingle();
          if (res != null) {
            foundRole = table == 'patients'
                ? 'patient'
                : table == 'doctors'
                ? 'doctor'
                : table == 'admins'
                ? 'admin'
                : 'supervisor';
            break;
          }
        }
        _userRole = foundRole;
      } catch (e) {
        print("Error fetching role: $e");
      }
    }
    await _loadChatHistory();
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
        _messages.add(
          ChatMessage(
            text:
                'Hello ${widget.patientName}! 👋\n\nI\'m your healthcare assistant powered by Google Gemini. I can help you with:\n\n• Understanding your test results\n• Booking appointments\n• Health tips and advice\n• Medication information\n\nHow can I assist you today?',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
        _saveCurrentConversation();
      }
    });

    _scrollToBottom();
  }

  Future<void> _saveCurrentConversation() async {
    final prefs = await SharedPreferences.getInstance();
    final conversationIndex = _conversationHistory.indexWhere(
      (conv) => conv.id == _currentConversationId,
    );

    if (conversationIndex != -1) {
      _conversationHistory[conversationIndex].messages.clear();
      _conversationHistory[conversationIndex].messages.addAll(_messages);
      _conversationHistory[conversationIndex].date = DateTime.now()
          .toIso8601String();
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
      _messages.add(
        ChatMessage(
          text:
              'Hello ${widget.patientName}! 👋\n\nI\'m your healthcare assistant. How can I help you today?',
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
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
    final text = message.trim();
    final hasAttachment = _pendingFilePath != null && _pendingFileName != null;

    if (text.isEmpty && !hasAttachment) return;

    String combinedText = text;
    if (hasAttachment) {
      combinedText =
          '📄 ${_pendingFileName!}' + (text.isNotEmpty ? '\n$text' : '');
    }

    final userMessage = ChatMessage(
      text: combinedText,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isTyping = true;
    });

    try {
      await _supabase.from('chat_history').insert({
        'user_id': _userId,
        'role': _userRole,
        'sender': 'user',
        'message': combinedText,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Warning: Failed to save user message to Supabase: $e');
    }

    await _saveCurrentConversation();
    _messageController.clear();
    _scrollToBottom();

    try {
      String responseText;

      if (hasAttachment) {
        final filePath = _pendingFilePath!;
        final filename = _pendingFileName!;
        final file = File(filePath);
        final bytes = await file.readAsBytes();

        final storagePath =
            '$_userId/${DateTime.now().millisecondsSinceEpoch}_$filename';
        
        // Upload to Supabase
        await _supabase.storage
            .from('reports')
            .uploadBinary(storagePath, bytes);

        // Get public URL
        final publicUrl = _supabase.storage.from('reports').getPublicUrl(storagePath);

        // Call Hugging Face API
        responseText = await _callHuggingFaceAPI(text, imageUrl: publicUrl);

        if (mounted) {
          setState(() {
            _pendingFilePath = null;
            _pendingFileName = null;
          });
        }
      } else {
        responseText = await _callHuggingFaceAPI(text);
      }

      final botMessage = ChatMessage(
        text: responseText,
        isUser: false,
        timestamp: DateTime.now(),
      );

      if (!mounted) return;
      setState(() {
        _messages.add(botMessage);
        _isTyping = false;
      });

      try {
        await _supabase.from('chat_history').insert({
          'user_id': _userId,
          'role': _userRole,
          'sender': 'assistant',
          'message': responseText,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        print('Warning: Failed to save bot message to Supabase: $e');
      }

      await _saveCurrentConversation();
      _scrollToBottom();
    } catch (e) {
      print('❌ ERROR: $e');

      if (!mounted) return;

      if (hasAttachment) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to analyze document. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isTyping = false;
        });
      } else {
        final errorMsg = ChatMessage(
          text: _getErrorMessage(e.toString()),
          isUser: false,
          timestamp: DateTime.now(),
        );

        setState(() {
          _messages.add(errorMsg);
          _isTyping = false;
        });
      }

      await _saveCurrentConversation();
    }
  }

  String _getErrorMessage(String error) {
    if (error.contains('403') || error.contains('401')) {
      return '🔑 Invalid API Key!\n\nPlease check your .env configuration.';
    }
    if (error.contains('SocketException')) {
      return '📡 No Internet!\n\nCheck your connection and try again.';
    }
    return '❌ Error: ${error.substring(0, error.length > 150 ? 150 : error.length)}';
  }

  Future<String> _callHuggingFaceAPI(String userText, {String? imageUrl}) async {
    final apiKey = dotenv.env['HF_TOKEN'] ?? '';
    final url = dotenv.env['HF_ENDPOINT'] ?? 'https://api-inference.huggingface.co/models/Qwen/Qwen2.5-VL-7B-Instruct';

    List<Map<String, dynamic>> userContent = [];
    
    userContent.add({
      "type": "text",
      "text": userText.isNotEmpty ? userText : "Explain this medical report in simple English."
    });

    if (imageUrl != null) {
      userContent.add({
        "type": "image_url",
        "image_url": {
          "url": imageUrl
        }
      });
    }

    final body = {
      "model": dotenv.env['HF_MODEL'] ?? 'Qwen/Qwen2.5-VL-7B-Instruct',
      "messages": [
        {
          "role": "system",
          "content": "You are an expert healthcare AI assistant. Explain medical reports in simple English. Preserve numerical values and reference ranges. Highlight abnormal findings. Never diagnose. Never prescribe medicines. Return: Report Summary, Important Findings, Easy Explanation, Normal vs Abnormal Values, Home Care Advice, Disclaimer"
        },
        {
          "role": "user",
          "content": userContent
        }
      ],
      "stream": false,
      "max_tokens": 1024
    };

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty && data[0].containsKey('generated_text')) {
          // HF typically returns [{"generated_text": "..."}] for these endpoints
          return data[0]['generated_text'] ?? 'No response received.';
        } else if (data is Map && data.containsKey('choices')) {
          return data['choices'][0]['message']['content'] ?? 'No response received.';
        }
        return 'No response received.';
      } else {
        throw Exception('API Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('💥 Exception: $e');
      if (e.toString().contains('SocketException') || e.toString().contains('TimeoutException')) {
        throw Exception('AI service unavailable. Please check your connection.');
      }
      rethrow;
    }
  }

  Future<void> _pickFileAndAnalyze() async {
    // We do not gate upload behind the health check anymore as requested.

    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.photo_camera),
                title: Text('Camera'),
                onTap: () {
                  Navigator.of(context).pop();
                  _processAttachment(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.insert_drive_file),
                title: Text('Files / Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _processAttachment(null);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _processAttachment(ImageSource? source) async {
    try {
      String? filePath;
      String? filename;

      if (source != null) {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(source: source);
        if (pickedFile != null) {
          filePath = pickedFile.path;
          filename = pickedFile.name;
        }
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
          allowMultiple: false,
          withData: false,
        );
        if (result != null && result.files.single.path != null) {
          filePath = result.files.single.path;
          filename = result.files.single.name;
        }
      }

      if (filePath != null && filename != null) {
        if (!mounted) return;
        setState(() {
          _pendingFilePath = filePath;
          _pendingFileName = filename;
        });
      }
    } catch (e) {
      print('Attachment Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to attach document. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
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
              child: Icon(
                Icons.psychology_outlined,
                color: Colors.white,
                size: 24,
              ),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Health Assistant',
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
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
                      'Powered by Gemini',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.history, color: Colors.grey[800]),
            onPressed: () => setState(() => _showHistory = !_showHistory),
          ),
          IconButton(
            icon: Icon(Icons.add, color: Colors.grey[800]),
            onPressed: _createNewConversation,
          ),
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
          if (_showHistory)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: _buildHistorySidebar(),
            ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.all(12),
      child: SafeArea(
        child: Column(
          children: [
            if (_pendingFilePath != null && _pendingFileName != null)
              Container(
                margin: EdgeInsets.only(bottom: 12),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file, color: Colors.blue.shade700),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _pendingFileName!,
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _pendingFilePath = null;
                          _pendingFileName = null;
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.add, color: Colors.grey[700]),
                    onPressed: _showQuickActions,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: 'Ask me anything...',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            maxLines: null,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.attach_file,
                            color: Colors.grey[600],
                          ),
                          onPressed: _pickFileAndAnalyze,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.blue.shade700],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.send_rounded, color: Colors.white),
                    onPressed: () => _sendMessage(_messageController.text),
                  ),
                ),
              ],
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
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade400, Colors.blue.shade700],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.psychology_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.grey[800],
                      fontSize: 15,
                    ),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
          if (isUser) ...[
            SizedBox(width: 12),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                shape: BoxShape.circle,
              ),
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
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.blue.shade700],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.psychology_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          SizedBox(width: 12),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (i) => Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
                  child: _buildDot(i),
                ),
              ),
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
        final opacity = (value < 0.5 ? value * 2 : (1 - value) * 2).clamp(
          0.3,
          1.0,
        );
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(opacity),
            shape: BoxShape.circle,
          ),
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
                Text(
                  'Chat History',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => setState(() => _showHistory = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: _conversationHistory.isEmpty
                ? Center(
                    child: Text(
                      'No previous chats',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _conversationHistory.length,
                    itemBuilder: (context, index) =>
                        _buildConversationTile(_conversationHistory[index]),
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
      leading: Icon(
        Icons.chat_bubble_outline,
        color: isActive ? Colors.blue : Colors.grey,
      ),
      title: Text(
        conversation.title,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
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
            Text(
              'Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            _buildQuickActionButton(
              'Book Appointment',
              Icons.calendar_today,
              'I want to book an appointment',
            ),
            _buildQuickActionButton(
              'Health Tips',
              Icons.favorite,
              'Give me some health tips',
            ),
            _buildQuickActionButton(
              'Medication Info',
              Icons.medical_services,
              'Tell me about medications',
            ),
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

  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

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

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

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

  ChatConversation({
    required this.id,
    required this.title,
    required this.date,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatConversation.fromJson(Map<String, dynamic> json) =>
      ChatConversation(
        id: json['id'],
        title: json['title'],
        date: json['date'],
        messages: (json['messages'] as List)
            .map((m) => ChatMessage.fromJson(m))
            .toList(),
      );
}
