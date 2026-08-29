// lib/screens/doctor/patient_detail_screen_v3.dart
// TIER 3 VERSION - Enhanced with priority management, time tracking, and advanced features

import 'package:flutter/material.dart';
import '../../services/doctor_service.dart';

class PatientDetailScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic>? doctorProfile;
  final Map<String, dynamic>? activeSession;
  final VoidCallback onComplete;

  const PatientDetailScreen({
    Key? key,
    required this.patient,
    this.doctorProfile,
    this.activeSession,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen>
    with SingleTickerProviderStateMixin {
  final DoctorService _doctorService = DoctorService();
  final TextEditingController _notesController = TextEditingController();

  late TabController _tabController;
  bool _isSavingNotes = false;
  bool _isTimerRunning = false;
  int _timeWithPatient = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // NEW: 3 tabs
    _calculateTimeWithPatient();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // NEW: Calculate time with patient
  void _calculateTimeWithPatient() {
    _timeWithPatient = _doctorService.getTimeWithPatient(widget.patient);

    final tests = widget.patient['tests_in_room'] as List? ?? [];
    _isTimerRunning = tests.any(
          (t) => t['status'] == 'in_progress' || t['status'] == 'reached',
    );
  }

  void _addQuickNote(String note) {
    if (_notesController.text.isNotEmpty) {
      _notesController.text += '\n• $note';
    } else {
      _notesController.text = '• $note';
    }
  }

  // NEW: Show priority dialog
  Future<void> _showChangePriorityDialog() async {
    final appointmentId = widget.patient['appointment_id'] as String;
    final currentPriority = widget.patient['priority_level'] as String? ?? 'normal';

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Priority Level'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('🔴 Urgent'),
              subtitle: const Text('Highest priority - attend immediately'),
              value: 'urgent',
              groupValue: currentPriority,
              onChanged: (value) => Navigator.pop(context, value),
            ),
            RadioListTile<String>(
              title: const Text('🟠 High'),
              subtitle: const Text('Medium priority - attend soon'),
              value: 'high',
              groupValue: currentPriority,
              onChanged: (value) => Navigator.pop(context, value),
            ),
            RadioListTile<String>(
              title: const Text('⚪ Normal'),
              subtitle: const Text('Standard priority'),
              value: 'normal',
              groupValue: currentPriority,
              onChanged: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null && selected != currentPriority) {
      try {
        final success = await _doctorService.updatePatientPriority(
          appointmentId,
          selected,
        );

        if (success && mounted) {
          _showSuccessSnackbar('Priority updated to $selected');
          Navigator.pop(context);
          widget.onComplete();
        }
      } catch (e) {
        _showErrorSnackbar('Error updating priority: $e');
      }
    }
  }

  // NEW: Start patient timer
  Future<void> _startPatientTimer() async {
    if (widget.doctorProfile == null) return;

    final appointmentId = widget.patient['appointment_id'] as String;

    try {
      final success = await _doctorService.startPatientTimer(
        appointmentId,
        widget.doctorProfile!['id'],
      );

      if (success && mounted) {
        setState(() {
          _isTimerRunning = true;
        });
        _showSuccessSnackbar('⏱️ Timer started');
      }
    } catch (e) {
      _showErrorSnackbar('Error starting timer: $e');
    }
  }

  Future<void> _completeNextTest() async {
    final tests = widget.patient['tests_in_room'] as List? ?? [];
    final nextTest = _doctorService.getNextPendingTest(tests);

    if (nextTest == null || widget.doctorProfile == null || widget.activeSession == null) {
      return;
    }

    try {
      final success = await _doctorService.completeTest(
        testId: nextTest['test_id'],
        doctorId: widget.doctorProfile!['id'],
        sessionId: widget.activeSession!['id'],
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      if (success) {
        _showSuccessSnackbar('✅ ${nextTest['test_name']} completed');
        Navigator.pop(context);
        widget.onComplete();
      }
    } catch (e) {
      _showErrorSnackbar('Error: $e');
    }
  }

  Future<void> _completeAllTests() async {
    final tests = widget.patient['tests_in_room'] as List? ?? [];
    final pendingTests = tests.where((t) => t['status'] != 'completed').toList();

    if (pendingTests.isEmpty || widget.doctorProfile == null || widget.activeSession == null) {
      return;
    }

    final confirmed = await _showConfirmDialog(
      title: 'Complete All Tests?',
      message: 'This will complete all ${pendingTests.length} pending test(s).',
    );

    if (confirmed != true) return;

    try {
      final testIds = pendingTests.map((t) => t['test_id'].toString()).toList();

      final success = await _doctorService.completeMultipleTests(
        testIds: testIds,
        doctorId: widget.doctorProfile!['id'],
        sessionId: widget.activeSession!['id'],
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      if (success) {
        _showSuccessSnackbar('✅ All tests completed');
        Navigator.pop(context);
        widget.onComplete();
      }
    } catch (e) {
      _showErrorSnackbar('Error: $e');
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientName = widget.patient['patient_name'] as String? ?? 'Unknown';
    final patientAge = widget.patient['patient_age'] as int? ?? 0;
    final patientGender = widget.patient['patient_gender'] as String? ?? '';
    final patientBloodGroup =
        widget.patient['patient_blood_group'] as String? ?? '';
    final patientPhone = widget.patient['patient_phone'] as String? ?? '';
    final patientId = widget.patient['patient_id'] as String? ?? '';
    final scheduledTime = widget.patient['scheduled_time'] as String? ?? '';
    final tests = widget.patient['tests_in_room'] as List? ?? [];
    final specialInstructions =
        widget.patient['special_instructions'] as String? ?? '';
    final priorityLevel = widget.patient['priority_level'] as String? ?? 'normal';

    final testCounts = _doctorService.countTestsByStatus(tests);
    final completedCount = testCounts['completed'] ?? 0;
    final totalCount = tests.length;
    final progressPercent =
    totalCount > 0 ? (completedCount / totalCount * 100).round() : 0;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Patient Details'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // NEW: Priority button
          IconButton(
            icon: Icon(
              priorityLevel == 'urgent'
                  ? Icons.priority_high
                  : priorityLevel == 'high'
                  ? Icons.flag
                  : Icons.flag_outlined,
              color: priorityLevel == 'urgent'
                  ? Colors.red
                  : priorityLevel == 'high'
                  ? Colors.orange
                  : Colors.white,
            ),
            onPressed: _showChangePriorityDialog,
            tooltip: 'Change Priority',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'change_priority') {
                _showChangePriorityDialog();
              } else if (value == 'start_timer') {
                _startPatientTimer();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'change_priority',
                child: Row(
                  children: [
                    Icon(Icons.flag, size: 20),
                    SizedBox(width: 8),
                    Text('Change Priority'),
                  ],
                ),
              ),
              if (!_isTimerRunning)
                const PopupMenuItem(
                  value: 'start_timer',
                  child: Row(
                    children: [
                      Icon(Icons.timer, size: 20),
                      SizedBox(width: 8),
                      Text('Start Timer'),
                    ],
                  ),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.person, size: 20)),
            Tab(text: 'Notes', icon: Icon(Icons.edit_note, size: 20)),
            Tab(text: 'Actions', icon: Icon(Icons.bolt, size: 20)), // NEW: Actions tab
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: Overview
          _buildOverviewTab(
            patientName: patientName,
            patientAge: patientAge,
            patientGender: patientGender,
            patientBloodGroup: patientBloodGroup,
            patientPhone: patientPhone,
            patientId: patientId,
            scheduledTime: scheduledTime,
            tests: tests,
            specialInstructions: specialInstructions,
            priorityLevel: priorityLevel,
            completedCount: completedCount,
            totalCount: totalCount,
            progressPercent: progressPercent,
          ),

          // TAB 2: Notes
          _buildNotesTab(),

          // TAB 3: Quick Actions (NEW)
          _buildActionsTab(tests, testCounts),
        ],
      ),

      // Bottom Action Buttons
      bottomNavigationBar: _buildBottomActions(tests, testCounts),
    );
  }

  Widget _buildOverviewTab({
    required String patientName,
    required int patientAge,
    required String patientGender,
    required String patientBloodGroup,
    required String patientPhone,
    required String patientId,
    required String scheduledTime,
    required List tests,
    required String specialInstructions,
    required String priorityLevel,
    required int completedCount,
    required int totalCount,
    required int progressPercent,
  }) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Patient Header Card
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade300, Colors.blue.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        patientGender.toLowerCase() == 'male'
                            ? Icons.person
                            : patientGender.toLowerCase() == 'female'
                            ? Icons.person_outline
                            : Icons.person,
                        size: 35,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Basic Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  patientName,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              // Priority Badge
                              if (priorityLevel == 'urgent')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'URGENT',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else if (priorityLevel == 'high')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'HIGH',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$patientGender, $patientAge years  •  $patientBloodGroup',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Quick Info Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoChip(
                        icon: Icons.phone,
                        label: 'Phone',
                        value: patientPhone,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoChip(
                        icon: Icons.access_time,
                        label: 'Scheduled',
                        value: _doctorService.formatTime(scheduledTime),
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoChip(
                        icon: Icons.badge,
                        label: 'Patient ID',
                        value: patientId.substring(0, 8),
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // NEW: Time with patient chip
                    Expanded(
                      child: _buildInfoChip(
                        icon: Icons.timelapse,
                        label: 'Time Spent',
                        value: _timeWithPatient > 0
                            ? '${_timeWithPatient}m'
                            : '--',
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Tests Progress Card
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tests Progress',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: progressPercent == 100
                            ? Colors.green.shade100
                            : Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isTimerRunning ? Icons.timer : Icons.check_circle_outline,
                            size: 16,
                            color: progressPercent == 100
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$completedCount/$totalCount ($progressPercent%)',
                            style: TextStyle(
                              fontSize: 13,
                              color: progressPercent == 100
                                  ? Colors.green.shade700
                                  : Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: totalCount > 0 ? completedCount / totalCount : 0,
                    minHeight: 10,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      completedCount == totalCount
                          ? Colors.green
                          : Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Tests List Card
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📋 Tests in This Room',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ...tests.map((test) => _buildEnhancedTestItem(test)).toList(),
              ],
            ),
          ),

          // Special Instructions
          if (specialInstructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📝 Special Instructions',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200, width: 2),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.amber.shade900,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            specialInstructions,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.amber.shade900,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 80), // Space for bottom buttons
        ],
      ),
    );
  }

  Widget _buildNotesTab() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '🗒️ Doctor Notes',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // NEW: Character count
              Text(
                '${_notesController.text.length} chars',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Notes Input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _notesController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'Add your notes here...\n\nTip: Use bullet points for clarity',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                  hintStyle: TextStyle(color: Colors.grey[400]),
                ),
                style: const TextStyle(fontSize: 15, height: 1.5),
                onChanged: (value) {
                  setState(() {}); // Update char count
                },
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Quick Note Templates
          const Text(
            'Quick templates:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQuickNoteChip('Normal results ✓', Icons.check_circle),
              _buildQuickNoteChip('Repeat test needed', Icons.repeat),
              _buildQuickNoteChip('Consultation required', Icons.medical_services),
              _buildQuickNoteChip('Patient cooperative', Icons.thumb_up),
              _buildQuickNoteChip('Follow-up in 1 week', Icons.calendar_today),
              _buildQuickNoteChip('Fasting required', Icons.no_meals),
              _buildQuickNoteChip('Send report via email', Icons.email),
              _buildQuickNoteChip('Abnormal values detected', Icons.warning),
            ],
          ),
        ],
      ),
    );
  }

  // NEW: Quick Actions Tab
  Widget _buildActionsTab(List tests, Map<String, int> testCounts) {
    final appointmentId = widget.patient['appointment_id'] as String;
    final patientName = widget.patient['patient_name'] as String;
    final priorityLevel = widget.patient['priority_level'] as String? ?? 'normal';
    final allCompleted = testCounts['completed'] == tests.length;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Priority Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🚩 Priority Management',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                _buildActionCard(
                  icon: Icons.priority_high,
                  title: 'Mark as Urgent',
                  subtitle: 'Set highest priority',
                  color: Colors.red,
                  enabled: priorityLevel != 'urgent',
                  onTap: () async {
                    final success = await _doctorService.updatePatientPriority(
                      appointmentId,
                      'urgent',
                    );
                    if (success && mounted) {
                      _showSuccessSnackbar('Priority set to URGENT');
                      Navigator.pop(context);
                      widget.onComplete();
                    }
                  },
                ),

                const SizedBox(height: 12),

                _buildActionCard(
                  icon: Icons.flag,
                  title: 'Mark as High Priority',
                  subtitle: 'Set medium priority',
                  color: Colors.orange,
                  enabled: priorityLevel != 'high',
                  onTap: () async {
                    final success = await _doctorService.updatePatientPriority(
                      appointmentId,
                      'high',
                    );
                    if (success && mounted) {
                      _showSuccessSnackbar('Priority set to HIGH');
                      Navigator.pop(context);
                      widget.onComplete();
                    }
                  },
                ),

                const SizedBox(height: 12),

                _buildActionCard(
                  icon: Icons.remove_circle_outline,
                  title: 'Set Normal Priority',
                  subtitle: 'Remove high priority',
                  color: Colors.grey,
                  enabled: priorityLevel != 'normal',
                  onTap: () async {
                    final success = await _doctorService.updatePatientPriority(
                      appointmentId,
                      'normal',
                    );
                    if (success && mounted) {
                      _showSuccessSnackbar('Priority set to NORMAL');
                      Navigator.pop(context);
                      widget.onComplete();
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Patient Management Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚡ Quick Actions',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                _buildActionCard(
                  icon: Icons.timer,
                  title: 'Start Timer',
                  subtitle: 'Begin tracking time with patient',
                  color: Colors.purple,
                  enabled: !_isTimerRunning,
                  onTap: _startPatientTimer,
                ),

                const SizedBox(height: 12),

                _buildActionCard(
                  icon: Icons.skip_next,
                  title: 'Skip Patient',
                  subtitle: 'Move to end of queue',
                  color: Colors.blue,
                  enabled: !allCompleted,
                  onTap: () async {
                    final reason = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Skip Patient'),
                        content: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Reason (optional)',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (value) => Navigator.pop(context, value),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, 'Skipped by doctor'),
                            child: const Text('Skip'),
                          ),
                        ],
                      ),
                    );

                    if (reason != null) {
                      final success = await _doctorService.skipPatient(
                        appointmentId,
                        reason,
                      );
                      if (success && mounted) {
                        _showSuccessSnackbar('Patient skipped');
                        Navigator.pop(context);
                        widget.onComplete();
                      }
                    }
                  },
                ),

                const SizedBox(height: 12),

                _buildActionCard(
                  icon: Icons.cancel,
                  title: 'Mark as No-Show',
                  subtitle: 'Patient didn\'t arrive',
                  color: Colors.red,
                  enabled: !allCompleted,
                  onTap: () async {
                    final confirmed = await _showConfirmDialog(
                      title: 'Mark as No-Show?',
                      message: '$patientName will be removed from queue.',
                    );

                    if (confirmed == true) {
                      final success = await _doctorService.markNoShow(appointmentId);
                      if (success && mounted) {
                        _showSuccessSnackbar('Marked as no-show');
                        Navigator.pop(context);
                        widget.onComplete();
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: enabled ? color.withOpacity(0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? color.withOpacity(0.3) : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: enabled ? color : Colors.grey,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: enabled ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    enabled ? subtitle : 'Already applied',
                    style: TextStyle(
                      fontSize: 13,
                      color: enabled ? Colors.grey[600] : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: enabled ? color : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedTestItem(Map<String, dynamic> test) {
    final testName = test['test_name'] as String? ?? 'Unknown';
    final status = test['status'] as String? ?? 'pending';
    final completedAt = test['completed_at'] as String?;
    final reachedAt = test['reached_at'] as String?;
    final completedByRole = test['completed_by_role'] as String?;

    IconData icon;
    Color color;
    String statusText;
    String? timestamp;

    switch (status) {
      case 'completed':
        icon = Icons.check_circle;
        color = Colors.green;
        if (completedByRole == 'patient') {
          statusText = 'Patient marked this test as complete';
        } else if (completedByRole == 'doctor') {
          statusText = 'You marked this test as complete';
        } else {
          statusText = 'Completed';
        }
        timestamp = completedAt;
        break;
      case 'in_progress':
        icon = Icons.pending;
        color = Colors.blue;
        statusText = 'In Progress';
        timestamp = reachedAt;
        break;
      case 'reached':
        icon = Icons.schedule;
        color = Colors.orange;
        statusText = 'Pending';
        timestamp = reachedAt;
        break;
      default:
        icon = Icons.radio_button_unchecked;
        color = Colors.grey;
        statusText = 'Pending';
        timestamp = null;
    }

    String? formattedTime;
    if (timestamp != null) {
      try {
        final time = DateTime.parse(timestamp);
        formattedTime = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        // Keep null
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  testName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: status == 'completed'
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (formattedTime != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'at $formattedTime',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickNoteChip(String label, IconData icon) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: Colors.blue.shade700),
      label: Text(
        label,
        style: const TextStyle(fontSize: 13),
      ),
      onPressed: () => _addQuickNote(label),
      backgroundColor: Colors.blue.shade50,
      side: BorderSide(color: Colors.blue.shade200),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildBottomActions(List tests, Map<String, int> testCounts) {
    final nextTest = _doctorService.getNextPendingTest(tests);
    final allCompleted = testCounts['completed'] == tests.length;
    final hasPending =
        testCounts['pending']! > 0 || testCounts['reached']! > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!allCompleted && nextTest != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _completeNextTest,
                  icon: const Icon(Icons.check_circle),
                  label: Text('Complete: ${nextTest['test_name']}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            if (!allCompleted && tests.length > 1 && hasPending) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _completeAllTests,
                  icon: const Icon(Icons.done_all),
                  label: const Text('Complete All Tests in Room'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Colors.blue, width: 2),
                  ),
                ),
              ),
            ],
            if (allCompleted)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'All tests completed',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}