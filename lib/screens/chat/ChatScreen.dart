import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String senderId;
  final String senderName;
  final String receiverId;
  final String receiverName;

  const ChatScreen({
    Key? key,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.receiverName,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  late final RealtimeChannel _channel;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    supabase.removeChannel(_channel);
    super.dispose();
  }

  void _subscribeToMessages() {
    _channel = supabase
        .channel('messages_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final newMsg = payload.newRecord;
            if ((newMsg['sender_id'] == widget.senderId &&
                    newMsg['receiver_id'] == widget.receiverId) ||
                (newMsg['sender_id'] == widget.receiverId &&
                    newMsg['receiver_id'] == widget.senderId)) {
              setState(() {
                _messages.add(Map<String, dynamic>.from(newMsg));
              });
              _scrollToBottom();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final deletedId = payload.oldRecord['id'];
            setState(() {
              _messages.removeWhere((m) => m['id'] == deletedId);
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final updatedMsg = payload.newRecord;
            setState(() {
              final idx = _messages.indexWhere(
                (m) => m['id'] == updatedMsg['id'],
              );
              if (idx != -1) {
                _messages[idx] = Map<String, dynamic>.from(updatedMsg);
              }
            });
          },
        )
        .subscribe();
  }

  Future<void> _loadMessages() async {
    try {
      final response = await supabase
          .from('messages')
          .select()
          .or(
            'and(sender_id.eq.${widget.senderId},receiver_id.eq.${widget.receiverId}),and(sender_id.eq.${widget.receiverId},receiver_id.eq.${widget.senderId})',
          )
          .order('timestamp', ascending: true);

      setState(() {
        _messages = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackbar('Error loading messages', isError: true);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    final message = {
      'sender_id': widget.senderId,
      'sender_name': widget.senderName,
      'receiver_id': widget.receiverId,
      'receiver_name': widget.receiverName,
      'message_text': text,
      'timestamp': DateTime.now().toIso8601String(),
      'deleted_for': [],
    };

    try {
      await supabase.from('messages').insert(message);
    } catch (e) {
      _showSnackbar('Failed to send message', isError: true);
    }
  }

  /// Returns true if this message should be visible to the current user.
  bool _isVisibleToMe(Map<String, dynamic> msg) {
    final deletedFor = List<String>.from(msg['deleted_for'] ?? []);
    return !deletedFor.contains(widget.senderId);
  }

  /// Delete for Me — soft delete by adding current user's ID to deleted_for array.
  Future<void> _deleteForMe(Map<String, dynamic> msg) async {
    try {
      final deletedFor = List<String>.from(msg['deleted_for'] ?? []);
      if (!deletedFor.contains(widget.senderId)) {
        deletedFor.add(widget.senderId);
      }

      await supabase
          .from('messages')
          .update({'deleted_for': deletedFor})
          .eq('id', msg['id']);

      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == msg['id']);
        if (idx != -1) {
          _messages[idx] = {..._messages[idx], 'deleted_for': deletedFor};
        }
      });

      _showSnackbar('Message deleted for you');
    } catch (e) {
      _showSnackbar('Failed to delete message', isError: true);
    }
  }

  /// Delete for Everyone — hard delete from the database.
  Future<void> _deleteForEveryone(Map<String, dynamic> msg) async {
    try {
      await supabase.from('messages').delete().eq('id', msg['id']);

      setState(() {
        _messages.removeWhere((m) => m['id'] == msg['id']);
      });

      _showSnackbar('Message deleted for everyone');
    } catch (e) {
      _showSnackbar('Failed to delete message', isError: true);
    }
  }

  /// Shows the delete bottom sheet — WhatsApp style.
  void _showDeleteOptions(Map<String, dynamic> msg) {
    final isMe = msg['sender_id'] == widget.senderId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Message preview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                msg['message_text'] ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),

            const Divider(height: 1),

            // Delete for Me
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.orange),
              title: const Text(
                'Delete for Me',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Remove from your view only'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteForMe(msg);
              },
            ),

            // Delete for Everyone — only sender can do this
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  'Delete for Everyone',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
                subtitle: const Text('Permanently removes from all devices'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteForEveryone(msg);
                },
              ),

            // Cancel
            ListTile(
              leading: const Icon(Icons.close, color: Colors.grey),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Confirmation dialog before hard-deleting.
  void _confirmDeleteForEveryone(Map<String, dynamic> msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete for Everyone?'),
        content: const Text(
          'This will permanently delete the message for all participants. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteForEveryone(msg);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages = _messages
        .where((msg) => _isVisibleToMe(msg))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receiverName),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : visibleMessages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: visibleMessages.length,
                    itemBuilder: (context, index) {
                      final msg = visibleMessages[index];
                      final isMe = msg['sender_id'] == widget.senderId;
                      return _buildMessageBubble(msg, isMe);
                    },
                  ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    String timeStr = msg['timestamp'] ?? msg['created_at'] ?? '';

    // Convert Supabase UTC timestamps to local timezone
    if (timeStr.isNotEmpty &&
        !timeStr.endsWith('Z') &&
        !timeStr.contains('+')) {
      timeStr += 'Z'; // Force UTC if missing timezone indicator
    }

    final localTime = timeStr.isNotEmpty
        ? DateTime.parse(timeStr).toLocal()
        : DateTime.now();
    final formattedTime = DateFormat('HH:mm').format(localTime);

    return GestureDetector(
      onLongPress: () => _showDeleteOptions(msg),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isMe ? Colors.teal : Colors.grey[300],
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                msg['message_text'],
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formattedTime,
                style: TextStyle(
                  color: isMe ? Colors.white70 : Colors.grey[600],
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.teal,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
