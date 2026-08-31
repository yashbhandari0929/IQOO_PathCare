// lib/screens/patient/chatbot_screen.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../services/gemini_rag_service.dart';

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
  String _loadingText = '';
  late AnimationController _animationController;
  List<ChatConversation> _conversationHistory = [];
  String _currentConversationId = '';
  bool _showHistory = false;

  // Backend handles LLM via Gemini RAG
  String _userRole = 'patient';
  String _userId = '';
  final _supabase = Supabase.instance.client;
  String? _pendingFilePath;
  String? _pendingFileName;
  late final GeminiRAGService _geminiRAGService;

  @override
  void initState() {
    super.initState();
    _geminiRAGService = GeminiRAGService();
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
      } catch (e) {}
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
                'Hello ${widget.patientName}! 👋\n\nI\'m your healthcare assistant. I can help you with:\n\n• Understanding your test results\n• Booking appointments\n• Health tips and advice\n• Medication information\n\nHow can I assist you today?',
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

    final filePath = _pendingFilePath;
    final filename = _pendingFileName;

    setState(() {
      _messages.add(userMessage);
      _isTyping = true;
      _loadingText = hasAttachment ? 'Extracting report...' : 'Thinking...';
      _pendingFilePath = null;
      _pendingFileName = null;
    });

    try {
      await _supabase.from('chat_history').insert({
        'user_id': _userId,
        'role': _userRole,
        'sender': 'user',
        'message': combinedText,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {}

    await _saveCurrentConversation();
    _messageController.clear();
    _scrollToBottom();

    try {
      String responseText;
      String? documentText;

      if (hasAttachment) {
        final file = File(filePath!);
        final bytes = await file.readAsBytes();

        final storagePath =
            '$_userId/${DateTime.now().millisecondsSinceEpoch}_$filename';

        // Upload to Supabase for history
        await _supabase.storage
            .from('reports')
            .uploadBinary(storagePath, bytes);

        // Perform local OCR
        documentText = await _performLocalOCR(filePath);

        if (mounted) {
          setState(() {
            _loadingText = 'Retrieving medical context...';
          });
        }

        // Process for RAG embeddings
        await _geminiRAGService.processDocument(
          _userId,
          documentText,
          storagePath,
        );

        if (mounted) {
          setState(() {
            _loadingText = 'Analyzing report...';
          });
        }
      }

      // Call Gemini RAG API
      responseText = await _geminiRAGService.generateResponse(
        userId: _userId,
        userRole: _userRole,
        userMessage: text,
        currentDocumentText: documentText,
      );

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
      } catch (e) {}

      await _saveCurrentConversation();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      String errorMsg = e.toString().contains('OCR Failed')
          ? 'Unable to read this document.'
          : 'Unable to generate AI response. Please try again.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );

      setState(() {
        _isTyping = false;
        if (text.isNotEmpty && _messageController.text.isEmpty) {
          _messageController.text = text;
        }
        if (filePath != null && filename != null) {
          _pendingFilePath = filePath;
          _pendingFileName = filename;
        }
      });
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
                  child: isUser
                      ? Text(
                          message.text,
                          style: TextStyle(color: Colors.white, fontSize: 15),
                        )
                      : MarkdownBody(
                          data: message.text,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(color: Colors.grey[800], fontSize: 15),
                            h1: TextStyle(
                              color: Colors.grey[900],
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            h2: TextStyle(
                              color: Colors.grey[900],
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            h3: TextStyle(
                              color: Colors.grey[900],
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            listBullet: TextStyle(color: Colors.grey[800]),
                            tableBody: TextStyle(color: Colors.grey[800]),
                            tableHead: TextStyle(
                              color: Colors.grey[900],
                              fontWeight: FontWeight.bold,
                            ),
                            horizontalRuleDecoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: Colors.grey[300]!,
                                  width: 1.0,
                                ),
                              ),
                            ),
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
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              _loadingText.isEmpty ? 'Typing...' : _loadingText,
              style: TextStyle(
                color: Colors.grey[700],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
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

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<String> _performLocalOCR(String filePath) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    String extractedText = '';

    try {
      if (filePath.toLowerCase().endsWith('.pdf')) {
        final document = await PdfDocument.openFile(filePath);
        final tempDir = await getTemporaryDirectory();

        for (int i = 1; i <= document.pagesCount; i++) {
          final page = await document.getPage(i);
          final pageImage = await page.render(
            width: page.width * 4.0, // approx 300 DPI scaling
            height: page.height * 4.0,
            format: PdfPageImageFormat.png,
          );

          if (pageImage != null) {
            final tempFile = File('${tempDir.path}/temp_page_$i.png');
            await tempFile.writeAsBytes(pageImage.bytes);

            final inputImage = InputImage.fromFilePath(tempFile.path);
            final RecognizedText recognizedText = await textRecognizer
                .processImage(inputImage);
            extractedText += recognizedText.text + '\n\n';

            await tempFile.delete();
          }
          await page.close();
        }
        await document.close();
      } else {
        final inputImage = InputImage.fromFilePath(filePath);
        final RecognizedText recognizedText = await textRecognizer.processImage(
          inputImage,
        );
        extractedText = recognizedText.text;
      }
    } catch (e) {
      throw Exception('OCR Failed');
    } finally {
      textRecognizer.close();
    }

    return extractedText;
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
