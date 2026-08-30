// lib/screens/doctor/patient_list_screen_v3.dart
// TIER 3 VERSION - With quick actions, priority management, and time tracking
//
// CHANGE LOG (this version):
// ✅ NEW: Tracks _completedTodayCount (patients with ALL tests done today)
//         and passes it to DoctorAnalysisScreen via liveCompletedToday param.
//         Both the Done chip in the top panel AND the Analysis screen now
//         always show the same up-to-date number. All existing features kept.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/doctor_service.dart';
import 'doctor_analysis_screen.dart';
import 'patient_detail_screen_v3.dart';

class PatientListScreen extends StatefulWidget {
  final String roomNumber;
  final String roomName;
  final String floor;

  const PatientListScreen({
    Key? key,
    required this.roomNumber,
    required this.roomName,
    required this.floor,
  }) : super(key: key);

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen>
    with SingleTickerProviderStateMixin {
  final DoctorService _doctorService = DoctorService();
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allPatients = [];
  List<Map<String, dynamic>> _activePatients = [];
  List<Map<String, dynamic>> _completedPatients = [];
  Map<String, dynamic>? _doctorProfile;
  Map<String, dynamic>? _activeSession;
  Map<String, dynamic>? _analytics;

  String _selectedFilter = 'All';
  String _selectedSort = 'priority';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _showCompleted = false;
  String? _suggestedRoom;

  // ── NEW: tracks how many patients have had ALL their tests completed
  //        in this room session today. Passed to DoctorAnalysisScreen so the
  //        analysis "Today" tab immediately reflects what the Done chip shows.
  int _completedTodayCount = 0;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadDoctorProfile();
    await _loadPatients();
    await _loadAnalytics();
    await _checkForSuggestions();
  }

  Future<void> _loadDoctorProfile() async {
    try {
      _doctorProfile = await _doctorService.getCurrentDoctor();

      if (_doctorProfile == null) {
        debugPrint(
          '[PatientList] Doctor profile not found — check auth_id column in doctors table',
        );
        return;
      }

      final doctorId = _doctorProfile!['id'] as String;

      // Always check for an active session first
      _activeSession = await _doctorService.getActiveSession(doctorId);

      if (_activeSession == null) {
        // No active session — start one for this room
        final sessionId = await _doctorService.startSession(
          doctorId,
          widget.roomNumber,
        );

        if (sessionId != null) {
          // Re-fetch so we have the full session row (id, room_number, etc.)
          _activeSession = await _doctorService.getActiveSession(doctorId);
        }

        if (_activeSession == null) {
          debugPrint(
            '[PatientList] Could not start/find session for doctor $doctorId in room ${widget.roomNumber}',
          );
        }
      }

      debugPrint(
        '[PatientList] Doctor: ${_doctorProfile!['full_name']}  Session: ${_activeSession?['id']}',
      );
    } catch (e) {
      debugPrint('[PatientList] Error loading doctor profile: $e');
    }
  }

  Future<void> _loadPatients() async {
    setState(() => _isLoading = true);

    try {
      final roomId = _activeSession?['room_id'] as String?;
      if (roomId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final patients = await _doctorService.getPatientsForRoom(roomId);

      if (mounted) {
        setState(() {
          _allPatients = patients;
          _separatePatients();
          // Re-apply active filters on top of freshly loaded data
          _applyFiltersAndSortOnFresh();

          // ── SYNC _completedTodayCount with the DB-loaded completed list ──
          // Use the larger of: what we already counted in this session vs
          // what the DB says is completed. This prevents the count going
          // backwards if a refresh re-fetches data mid-session.
          final dbCompleted = _completedPatients.length;
          if (dbCompleted > _completedTodayCount) {
            _completedTodayCount = dbCompleted;
          }
        });
      }
    } catch (e) {
      debugPrint('[PatientList] Error loading patients: $e');
      if (mounted) {
        _showErrorSnackbar('Error loading patients: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAnalytics() async {
    if (_doctorProfile == null) return;

    try {
      final analytics = await _doctorService.getDetailedAnalytics(
        _doctorProfile!['id'],
      );

      setState(() {
        _analytics = analytics;
      });
    } catch (e) {}
  }

  Future<void> _checkForSuggestions() async {
    try {
      final roomId = _activeSession?['room_id'] as String?;
      if (roomId == null) return;

      final hasPending = await _doctorService.roomHasPendingPatients(roomId);

      if (!hasPending) {
        final suggested = await _doctorService.getSuggestedNextRoom(
          widget.roomNumber,
        );

        setState(() {
          _suggestedRoom = suggested;
        });
      }
    } catch (e) {}
  }

  void _separatePatients() {
    _completedPatients = _allPatients.where((patient) {
      final tests = patient['tests_in_room'] as List? ?? [];
      return tests.isNotEmpty && tests.every((t) => t['status'] == 'completed');
    }).toList();

    _activePatients = _allPatients.where((patient) {
      final tests = patient['tests_in_room'] as List? ?? [];
      return tests.isEmpty || tests.any((t) => t['status'] != 'completed');
    }).toList();
  }

  // Called after fresh data load — works from the just-separated _activePatients
  void _applyFiltersAndSortOnFresh() {
    List<Map<String, dynamic>> result = List.from(_activePatients);

    if (_searchQuery.isNotEmpty) {
      result = _doctorService.searchPatients(result, _searchQuery);
    }

    if (_selectedFilter != 'All') {
      result = _doctorService.filterPatientsByStatus(
        result,
        _selectedFilter.toLowerCase().replaceAll(' ', '_'),
      );
    }

    result = _doctorService.sortPatients(result, _selectedSort);
    _activePatients = result;
  }

  void _applyFiltersAndSort() {
    // Always re-separate from full list before filtering so we don't lose data
    _separatePatients();
    _applyFiltersAndSortOnFresh();
    setState(() {});
  }

  // ── NEW HELPER: call after any successful test-completion to check whether
  //    the patient is now fully done, and if so increment _completedTodayCount.
  //    Re-loads patients first so _completedPatients is up to date.
  Future<void> _refreshAndUpdateCompletedCount() async {
    await _loadPatients();
    await _loadAnalytics();
    // _loadPatients already syncs _completedTodayCount with DB; done here.
  }

  Future<void> _showQuickActionsMenu(Map<String, dynamic> patient) async {
    final appointmentId = patient['appointment_id'] as String;
    final patientName = patient['patient_name'] as String;
    final priorityLevel = patient['priority_level'] as String? ?? 'normal';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Quick Actions: $patientName',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.flag, color: Colors.red),
                title: const Text('Mark as Urgent'),
                subtitle: Text(
                  priorityLevel == 'urgent'
                      ? 'Already urgent'
                      : 'Set high priority',
                ),
                enabled: priorityLevel != 'urgent',
                onTap: () {
                  Navigator.pop(context);
                  _updatePriority(appointmentId, 'urgent');
                },
              ),
              ListTile(
                leading: const Icon(Icons.priority_high, color: Colors.orange),
                title: const Text('Mark as High Priority'),
                subtitle: Text(
                  priorityLevel == 'high'
                      ? 'Already high priority'
                      : 'Set medium priority',
                ),
                enabled: priorityLevel != 'high',
                onTap: () {
                  Navigator.pop(context);
                  _updatePriority(appointmentId, 'high');
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle, color: Colors.grey),
                title: const Text('Set Normal Priority'),
                subtitle: Text(
                  priorityLevel == 'normal'
                      ? 'Already normal'
                      : 'Remove high priority',
                ),
                enabled: priorityLevel != 'normal',
                onTap: () {
                  Navigator.pop(context);
                  _updatePriority(appointmentId, 'normal');
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.skip_next, color: Colors.blue),
                title: const Text('Skip Patient'),
                subtitle: const Text('Move to end of queue'),
                onTap: () {
                  Navigator.pop(context);
                  _skipPatient(appointmentId, patientName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.red),
                title: const Text('Mark as No-Show'),
                subtitle: const Text('Patient didn\'t arrive'),
                onTap: () {
                  Navigator.pop(context);
                  _markNoShow(appointmentId, patientName);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updatePriority(String appointmentId, String priority) async {
    try {
      final success = await _doctorService.updatePatientPriority(
        appointmentId,
        priority,
      );

      if (success) {
        _showSuccessSnackbar('✅ Priority updated to $priority');
        await _loadPatients();
      }
    } catch (e) {
      _showErrorSnackbar('Error updating priority: $e');
    }
  }

  Future<void> _skipPatient(String appointmentId, String patientName) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip Patient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Skip $patientName?'),
            const SizedBox(height: 16),
            const Text(
              'Reason (optional):',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'e.g., Patient requested',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
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
      try {
        final success = await _doctorService.skipPatient(appointmentId, reason);

        if (success) {
          _showSuccessSnackbar('✅ Patient skipped');
          await _loadPatients();
        }
      } catch (e) {
        _showErrorSnackbar('Error skipping patient: $e');
      }
    }
  }

  Future<void> _markNoShow(String appointmentId, String patientName) async {
    final confirmed = await _showConfirmDialog(
      title: 'Mark as No-Show?',
      message:
          '$patientName will be marked as no-show and removed from the queue.',
    );

    if (confirmed == true) {
      try {
        final success = await _doctorService.markNoShow(appointmentId);

        if (success) {
          _showSuccessSnackbar('✅ Marked as no-show');
          await _loadPatients();
        }
      } catch (e) {
        _showErrorSnackbar('Error marking no-show: $e');
      }
    }
  }

  Future<void> _handleCompleteTest(
    String testId,
    Map<String, dynamic> patient,
  ) async {
    if (_doctorProfile == null) {
      _showErrorSnackbar('Doctor profile not loaded. Please restart.');
      return;
    }

    // If session is missing, attempt to recover it before giving up
    if (_activeSession == null) {
      await _loadDoctorProfile();
      if (mounted) setState(() {});
    }

    if (_activeSession == null) {
      _showErrorSnackbar('Could not start a session. Check your connection.');
      return;
    }

    try {
      final success = await _doctorService.completeTest(
        testId: testId,
        doctorId: _doctorProfile!['id'],
        sessionId: _activeSession!['id'],
      );

      if (success) {
        _showSuccessSnackbar('✅ Test completed successfully');
        // ── Use unified refresh so _completedTodayCount stays in sync ──
        await _refreshAndUpdateCompletedCount();
      } else {
        _showErrorSnackbar('Failed to complete test. Please try again.');
      }
    } catch (e) {
      debugPrint('[PatientList] completeTest error: $e');
      _showErrorSnackbar('Error completing test: $e');
    }
  }

  Future<void> _handleCompleteAllTests(
    List pendingTests,
    Map<String, dynamic> patient,
  ) async {
    if (_doctorProfile == null) return;

    if (_activeSession == null) {
      await _loadDoctorProfile();
      if (mounted) setState(() {});
    }

    if (_activeSession == null) {
      _showErrorSnackbar('Could not start a session. Check your connection.');
      return;
    }

    final confirmed = await _showConfirmDialog(
      title: 'Complete All Tests?',
      message:
          'Mark all ${pendingTests.length} tests as completed for ${patient['patient_name']}?',
    );

    if (confirmed != true) return;

    try {
      // Extract test_id strings from the list of test objects
      final testIdStrings = pendingTests
          .map((t) => (t as Map<String, dynamic>)['test_id']?.toString())
          .whereType<String>()
          .toList();

      if (testIdStrings.isEmpty) {
        _showWarningSnackbar('No valid test IDs found');
        return;
      }

      final success = await _doctorService.completeMultipleTests(
        testIds: testIdStrings,
        doctorId: _doctorProfile!['id'],
        sessionId: _activeSession!['id'],
      );

      if (success) {
        _showSuccessSnackbar('✅ All tests completed successfully');
        // ── Unified refresh keeps _completedTodayCount in sync ──
        await _refreshAndUpdateCompletedCount();
      } else {
        _showErrorSnackbar('Failed to complete tests. Please try again.');
      }
    } catch (e) {
      debugPrint('[PatientList] completeAllTests error: $e');
      _showErrorSnackbar('Error completing tests: $e');
    }
  }

  Future<void> _handleMarkAttended(Map<String, dynamic> patient) async {
    if (_doctorProfile == null) return;

    if (_activeSession == null) {
      await _loadDoctorProfile();
      if (mounted) setState(() {});
    }

    if (_activeSession == null) {
      _showErrorSnackbar('Could not start a session. Check your connection.');
      return;
    }

    final tests = patient['tests_in_room'] as List? ?? [];
    final pendingTests = tests
        .where((t) => t['status'] != 'completed')
        .toList();

    if (pendingTests.isEmpty) {
      _showWarningSnackbar('All tests already completed');
      return;
    }

    final confirmed = await _showConfirmDialog(
      title: 'Mark Patient Attended?',
      message:
          'Patient: ${patient['patient_name']}\n\nThis will mark ${pendingTests.length} remaining test(s) as completed.\n\nPatient will be moved to completed section.',
    );

    if (confirmed != true) return;

    try {
      final testIds = pendingTests.map((t) => t['test_id'].toString()).toList();

      final success = await _doctorService.markPatientAttended(
        testIds: testIds,
        doctorId: _doctorProfile!['id'],
        sessionId: _activeSession!['id'],
      );

      if (success) {
        _showSuccessSnackbar('✅ ${patient['patient_name']} marked as attended');
        // ── Unified refresh keeps _completedTodayCount in sync ──
        await _refreshAndUpdateCompletedCount();
      }
    } catch (e) {
      _showErrorSnackbar('Error: $e');
    }
  }

  // ── FIXED: Pop back to dashboard (avoids black screen on room change) ────
  Future<void> _handleBackToRooms() async {
    if (_activeSession != null) {
      await _doctorService.endSession(_activeSession!['id']);
    }
    if (mounted) {
      // Simply pop – the dashboard is still on the stack and will refresh
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleChangeRoom() async {
    final confirmed = await _showConfirmDialog(
      title: 'Change Room?',
      message: 'This will end your current session in this room. Continue?',
    );

    if (confirmed != true) return;

    if (_activeSession != null) {
      await _doctorService.endSession(_activeSession!['id']);
    }

    if (mounted) {
      // Pop back to dashboard – it will re-open RoomSelectionScreen from there
      Navigator.of(context).pop();
    }
  }

  Future<void> _switchToSuggestedRoom() async {
    if (_suggestedRoom == null) return;

    final confirmed = await _showConfirmDialog(
      title: 'Switch to $_suggestedRoom?',
      message:
          'This room has the most patients waiting. Do you want to switch?',
    );

    if (confirmed != true) return;

    if (_activeSession != null) {
      await _doctorService.endSession(_activeSession!['id']);
    }

    if (mounted) {
      // Pop back to dashboard first, then push new PatientListScreen from there
      Navigator.of(context).pop(_suggestedRoom);
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
        duration: const Duration(seconds: 2),
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
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showWarningSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
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
    final activeStats = _doctorService.calculateRoomStats(_activePatients);
    final totalStats = _doctorService.calculateRoomStats(_allPatients);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        // ── ADDED: Back arrow → RoomSelectionScreen ───────────────────────
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Room Selection',
          onPressed: () async {
            final confirmed = await _showConfirmDialog(
              title: 'Leave Room?',
              message:
                  'Going back will end your current session in this room. Continue?',
            );
            if (confirmed == true) {
              await _handleBackToRooms();
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🏥 ${widget.roomNumber}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (widget.floor.isNotEmpty)
              Text(widget.floor, style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _loadPatients();
                _loadAnalytics();
                _checkForSuggestions();
              },
              tooltip: 'Refresh',
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'change_room') {
                await _handleChangeRoom();
              } else if (value == 'refresh') {
                await _loadPatients();
                await _loadAnalytics();
              } else if (value == 'analytics') {
                _showAnalyticsDialog();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20),
                    SizedBox(width: 8),
                    Text('Refresh'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'analytics',
                child: Row(
                  children: [
                    Icon(Icons.analytics, size: 20),
                    SizedBox(width: 8),
                    Text('View Analytics'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'change_room',
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, size: 20),
                    SizedBox(width: 8),
                    Text('Change Room'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildEnhancedQuickStats(activeStats, totalStats),

          if (_suggestedRoom != null) _buildSuggestionBanner(),

          _buildFiltersAndSearch(),

          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _allPatients.isEmpty
                ? _buildEmptyState()
                : FadeTransition(
                    opacity: _fadeAnimation,
                    child: RefreshIndicator(
                      onRefresh: () async {
                        await _loadPatients();
                        await _loadAnalytics();
                        await _checkForSuggestions();
                      },
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_activePatients.isNotEmpty) ...[
                            _buildSectionHeader(
                              'Active Patients',
                              _activePatients.length,
                              Icons.people,
                              Colors.blue,
                            ),
                            const SizedBox(height: 8),
                            ..._activePatients.asMap().entries.map((entry) {
                              return _buildPatientCard(
                                entry.value,
                                entry.key,
                                isActive: true,
                              );
                            }).toList(),
                          ],

                          if (_completedPatients.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildCollapsibleCompletedSection(),
                          ],

                          if (_activePatients.isEmpty &&
                              _completedPatients.isEmpty &&
                              _searchQuery.isNotEmpty)
                            _buildNoResultsState(),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showAnalyticsDialog() {
    if (_analytics == null) {
      _showWarningSnackbar('Analytics not loaded yet');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📊 Today\'s Analytics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAnalyticRow(
              'Tests Completed',
              '${_analytics!['total_tests_completed']}',
              Icons.check_circle,
              Colors.green,
            ),
            _buildAnalyticRow(
              'Average Time/Test',
              _doctorService.formatDuration(_analytics!['average_test_time']),
              Icons.access_time,
              Colors.blue,
            ),
            _buildAnalyticRow(
              'Total Working Time',
              _doctorService.formatDuration(_analytics!['total_time_minutes']),
              Icons.timelapse,
              Colors.orange,
            ),
            _buildAnalyticRow(
              'Efficiency Score',
              '${_analytics!['efficiency_score']}%',
              Icons.speed,
              Colors.purple,
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            _buildAnalyticRow(
              'Sessions Today',
              '${_analytics!['total_sessions']}',
              Icons.meeting_room,
              Colors.teal,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionBanner() {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade400, Colors.purple.shade600],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Suggestion',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Switch to $_suggestedRoom (more patients waiting)',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _switchToSuggestedRoom,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.purple.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedQuickStats(
    Map<String, int> activeStats,
    Map<String, int> totalStats,
  ) {
    final totalPatients = totalStats['total'] ?? 0;
    // ── CHANGED: use _completedTodayCount (live) instead of totalStats['completed']
    //    so the Done chip always matches what the analysis screen shows.
    final completedPatients = _completedTodayCount;
    final progressPercent = totalPatients > 0
        ? (completedPatients / totalPatients * 100).round()
        : 0;

    // ── FIX: "Waiting" = patients who have ARRIVED at the room (reached/in_progress).
    //    Previously used activeStats['waiting'] which counted ALL non-completed
    //    patients including those who only booked but haven't arrived yet.
    //    Now we count only patients whose at least one test is 'reached' or 'in_progress'.
    final arrivedWaitingCount = _activePatients.where((patient) {
      final tests = patient['tests_in_room'] as List? ?? [];
      return tests.any(
        (t) => t['status'] == 'reached' || t['status'] == 'in_progress',
      );
    }).length;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatChip(
                    '${activeStats['total']}',
                    'Active',
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatChip(
                    '$arrivedWaitingCount',
                    'Waiting',
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatChip(
                    '${activeStats['in_progress']}',
                    'Progress',
                    Colors.orange,
                  ),
                ),
                // ── Done chip — tapping navigates to analysis with live count ──
                Expanded(
                  child: GestureDetector(
                    onTap: _doctorProfile != null
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DoctorAnalysisScreen(
                                doctorProfile: _doctorProfile!,
                                // Pass live count so analysis screen shows it
                                // immediately on the Today tab.
                                liveCompletedToday: _completedTodayCount,
                              ),
                            ),
                          )
                        : null,
                    child: Column(
                      children: [
                        Text(
                          '$completedPatients',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Done',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (_completedTodayCount > 0) ...[
                              const SizedBox(width: 2),
                              Icon(
                                Icons.open_in_new,
                                size: 10,
                                color: Colors.grey[500],
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (totalPatients > 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Today\'s Progress',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$completedPatients / $totalPatients patients ($progressPercent%)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: totalPatients > 0
                          ? (completedPatients / totalPatients).clamp(0.0, 1.0)
                          : 0.0,
                      minHeight: 6,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progressPercent == 100
                            ? Colors.green
                            : progressPercent > 50
                            ? Colors.blue
                            : Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildFiltersAndSearch() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search patient name or ID...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                          _applyFiltersAndSort();
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _applyFiltersAndSort();
              });
            },
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All'),
                      _buildFilterChip('Waiting'),
                      _buildFilterChip('In Progress'),
                      _buildFilterChip('Scheduled'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort by',
                onSelected: (value) {
                  setState(() {
                    _selectedSort = value;
                    _applyFiltersAndSort();
                  });
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'priority',
                    child: Row(
                      children: [
                        Icon(
                          Icons.flag,
                          size: 18,
                          color: _selectedSort == 'priority'
                              ? Colors.blue
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Priority',
                          style: TextStyle(
                            fontWeight: _selectedSort == 'priority'
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'time',
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 18,
                          color: _selectedSort == 'time' ? Colors.blue : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Time',
                          style: TextStyle(
                            fontWeight: _selectedSort == 'time'
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'name',
                    child: Row(
                      children: [
                        Icon(
                          Icons.sort_by_alpha,
                          size: 18,
                          color: _selectedSort == 'name' ? Colors.blue : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Name',
                          style: TextStyle(
                            fontWeight: _selectedSort == 'name'
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'status',
                    child: Row(
                      children: [
                        Icon(
                          Icons.pending_actions,
                          size: 18,
                          color: _selectedSort == 'status' ? Colors.blue : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Status',
                          style: TextStyle(
                            fontWeight: _selectedSort == 'status'
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = label;
            _applyFiltersAndSort();
          });
        },
        backgroundColor: Colors.grey[200],
        selectedColor: Colors.blue,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        checkmarkColor: Colors.white,
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    int count,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleCompletedSection() {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _showCompleted = !_showCompleted;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Completed Patients',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _completedPatients.length.toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _showCompleted
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
        if (_showCompleted) ...[
          const SizedBox(height: 8),
          ..._completedPatients.asMap().entries.map((entry) {
            return _buildPatientCard(entry.value, entry.key, isActive: false);
          }).toList(),
        ],
      ],
    );
  }

  Widget _buildPatientCard(
    Map<String, dynamic> patient,
    int index, {
    required bool isActive,
  }) {
    final patientName = patient['patient_name'] as String? ?? 'Unknown';
    final scheduledTime = patient['scheduled_time'] as String? ?? '';
    final tests = patient['tests_in_room'] as List? ?? [];
    final specialInstructions =
        patient['special_instructions'] as String? ?? '';
    final priorityLevel = patient['priority_level'] as String? ?? 'normal';

    final status = _doctorService.getPatientStatusText(tests);
    final testCounts = _doctorService.countTestsByStatus(tests);

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'Waiting':
        statusColor = Colors.green;
        statusIcon = Icons.schedule;
        break;
      case 'In Progress':
        statusColor = Colors.blue;
        statusIcon = Icons.pending_actions;
        break;
      case 'Completed':
        statusColor = Colors.grey;
        statusIcon = Icons.check_circle;
        break;
      case 'Scheduled':
        statusColor = Colors.orange;
        statusIcon = Icons.event;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    final isPriority = priorityLevel == 'urgent' || priorityLevel == 'high';
    final completedCount = testCounts['completed'] ?? 0;
    final totalTests = tests.length;

    final timeWithPatient = status == 'In Progress' || status == 'Waiting'
        ? _doctorService.getTimeWithPatient(patient)
        : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isActive && isPriority ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPriority
            ? BorderSide(color: Colors.red.shade300, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PatientDetailScreen(
                patient: patient,
                doctorProfile: _doctorProfile,
                activeSession: _activeSession,
                onComplete: () {
                  _refreshAndUpdateCompletedCount();
                },
              ),
            ),
          );
        },
        onLongPress: isActive ? () => _showQuickActionsMenu(patient) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

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
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (priorityLevel == 'urgent')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'URGENT',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else if (priorityLevel == 'high')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'HIGH',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _doctorService.formatTime(scheduledTime),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(statusIcon, size: 14, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 13,
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (timeWithPatient > 0) ...[
                              const SizedBox(width: 16),
                              Icon(
                                Icons.timelapse,
                                size: 14,
                                color: Colors.purple[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${timeWithPatient}m',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.purple[600],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (isActive)
                    IconButton(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onPressed: () => _showQuickActionsMenu(patient),
                      color: Colors.grey[600],
                      tooltip: 'Quick Actions',
                    ),
                ],
              ),

              const SizedBox(height: 12),

              if (totalTests > 1)
                _buildTestProgress(completedCount, totalTests, statusColor),

              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),

              _buildTestsList(tests),

              if (specialInstructions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          specialInstructions,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (isActive) ...[
                const SizedBox(height: 12),
                _buildActionButtons(patient, tests, testCounts),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestProgress(int completed, int total, Color color) {
    final percent = (completed / total * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$completed/$total tests ($percent%)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: completed / total,
                    minHeight: 4,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      completed == total ? Colors.green : color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestsList(List tests) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.medical_services, size: 16),
            const SizedBox(width: 6),
            Text(
              '📋 ${tests.length} test${tests.length != 1 ? 's' : ''} in this room:',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...tests.asMap().entries.map((entry) {
          final index = entry.key;
          final test = entry.value;
          final testName = test['test_name'] as String? ?? 'Unknown Test';
          final testStatus = test['status'] as String? ?? 'pending';
          final completedAt = test['completed_at'] as String?;

          IconData icon;
          Color color;
          String statusText;

          switch (testStatus) {
            case 'completed':
              icon = Icons.check_circle;
              color = Colors.green;
              statusText = 'Done';
              if (completedAt != null) {
                try {
                  final time = DateTime.parse(completedAt);
                  statusText +=
                      ' ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
                } catch (e) {
                  // Keep default
                }
              }
              break;
            case 'in_progress':
              icon = Icons.pending;
              color = Colors.blue;
              statusText = 'In Progress';
              break;
            case 'reached':
              icon = Icons.schedule;
              color = Colors.orange;
              statusText = 'Pending';
              break;
            default:
              icon = Icons.radio_button_unchecked;
              color = Colors.grey;
              statusText = 'Pending';
          }

          final isLast = index == tests.length - 1;

          return Padding(
            padding: EdgeInsets.only(left: 8, bottom: isLast ? 0 : 4),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    testName,
                    style: TextStyle(
                      fontSize: 13,
                      decoration: testStatus == 'completed'
                          ? TextDecoration.lineThrough
                          : null,
                      color: testStatus == 'completed'
                          ? Colors.grey[600]
                          : Colors.black87,
                    ),
                  ),
                ),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildActionButtons(
    Map<String, dynamic> patient,
    List tests,
    Map<String, int> testCounts,
  ) {
    final nextTest = _doctorService.getNextPendingTest(tests);
    final allCompleted = testCounts['completed'] == tests.length;
    final hasPending = testCounts['pending']! > 0 || testCounts['reached']! > 0;

    if (allCompleted) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Text(
              'All tests completed',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () {
              if (nextTest != null) {
                _handleCompleteTest(nextTest['test_id'], patient);
              }
            },
            icon: const Icon(Icons.check, size: 18),
            label: Text(
              nextTest != null ? 'Complete Test' : 'No Pending Test',
              style: const TextStyle(fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        if (tests.length > 1 && hasPending)
          Expanded(
            child: OutlinedButton(
              onPressed: () => _handleCompleteAllTests(
                tests.where((t) => t['status'] != 'completed').toList(),
                patient,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('All', style: TextStyle(fontSize: 13)),
            ),
          ),

        const SizedBox(width: 8),

        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PatientDetailScreen(
                  patient: patient,
                  doctorProfile: _doctorProfile,
                  activeSession: _activeSession,
                  onComplete: () {
                    _refreshAndUpdateCompletedCount();
                  },
                ),
              ),
            );
          },
          icon: const Icon(Icons.arrow_forward_ios, size: 16),
          color: Colors.grey[600],
          tooltip: 'View Details',
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading patients...',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No patients today',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later or change room',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term or filter',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// NOTE: Add this import at the top of this file:
// import 'doctor_analysis_screen.dart';
// (or wherever DoctorAnalysisScreen lives in your project)
