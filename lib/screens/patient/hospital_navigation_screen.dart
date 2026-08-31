import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/navigation_service.dart';
import '../../widgets/interactive_floor_map.dart';
import '../../widgets/queue_status_widget.dart';

class HospitalNavigationScreen extends StatefulWidget {
  final String appointmentId;

  const HospitalNavigationScreen({
    Key? key,
    required this.appointmentId,
  }) : super(key: key);

  @override
  State<HospitalNavigationScreen> createState() =>
      _HospitalNavigationScreenState();
}

class _HospitalNavigationScreenState
    extends State<HospitalNavigationScreen>
    with TickerProviderStateMixin {

  final NavigationService _svc = NavigationService();

  // ── Navigation state ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> _allTests      = [];
  Map<String, dynamic>?      _currentTest;
  List<PathSegment>          _pathSegments  = [];
  String                     _currentLoc    = 'Main Entrance';
  String                     _selectedFloor = 'Ground Floor';
  bool                       _isLoading     = true;
  bool                       _hasReached    = false;

  List<Map<String, dynamic>> _testsInRoom      = [];
  int                        _testIndexInRoom  = 0;
  bool                       _showingRoomTests = false;

  // ── Queue state — SINGLE SOURCE OF TRUTH ─────────────────────────────────
  int  _myPosition        = 1;
  int  _totalInRoom       = 0;
  int  _estimatedWaitMins = 0;
  int  _preArrivalCount   = 0;

  // ── Realtime channel ──────────────────────────────────────────────────────
  String?          _currentRoomId;
  RealtimeChannel? _roomStream;
  Timer?           _fallbackTimer;
  DateTime?        _lastUpdated;
  bool             _realtimeFailed = false;

  // ── Doctor-completion listener ────────────────────────────────────────────
  // Watches the patient's OWN appointment_test row.
  // When the doctor marks it complete on their side, the status flips to
  // 'completed' in the DB → realtime fires → _checkIfDoctorCompleted() runs
  // → patient screen auto-advances to the next test, exactly as if the
  // patient had tapped "Mark as Completed" themselves.
  RealtimeChannel? _doctorCompletionStream;
  bool             _isAutoAdvancing = false; // guard against double-fire

  // ── Position-change overlay animation ────────────────────────────────────
  int?                   _prevPosition;
  OverlayEntry?          _positionOverlay;
  AnimationController?   _overlayCtrl;

  @override
  void initState() {
    super.initState();
    _loadNavigationData();
  }

  @override
  void dispose() {
    _roomStream?.unsubscribe();
    _doctorCompletionStream?.unsubscribe();
    _fallbackTimer?.cancel();
    _overlayCtrl?.dispose();
    _positionOverlay?.remove();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REALTIME SUBSCRIPTION
  // ─────────────────────────────────────────────────────────────────────────

  void _subscribeToRoomUpdates(String roomId) {
    _roomStream?.unsubscribe();
    _realtimeFailed = false;

    _roomStream = supabase
        .channel('room_queue_$roomId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'appointment_tests',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'assigned_room_id',
        value: roomId,
      ),
      callback: (_) => _recalcBadge(roomId),
    )
        .subscribe((status, [error]) {
      if (error != null) {
        print('⚠️ Realtime failed: $error — starting fallback poll');
        setState(() => _realtimeFailed = true);
        _startFallbackPoll(roomId);
      }
    });

    _recalcBadge(roomId);
  }

  void _startFallbackPoll(String roomId) {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(
      const Duration(seconds: 8),
          (_) => _recalcBadge(roomId),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DOCTOR-COMPLETION LISTENER
  // Subscribes to the patient's specific appointment_test row.
  // When the doctor marks it complete, status → 'completed' fires here
  // and _checkIfDoctorCompleted() auto-advances the patient to the next test.
  // ─────────────────────────────────────────────────────────────────────────
  void _subscribeToDoctorCompletion(String appointmentTestId) {
    _doctorCompletionStream?.unsubscribe();

    _doctorCompletionStream = supabase
        .channel('doctor_done_$appointmentTestId')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'appointment_tests',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: appointmentTestId,
      ),
      callback: (payload) => _checkIfDoctorCompleted(payload),
    )
        .subscribe();
  }

  Future<void> _checkIfDoctorCompleted(PostgresChangePayload payload) async {
    if (!mounted || _isAutoAdvancing) return;

    // Only react if the doctor flipped status to 'completed'
    final newRow = payload.newRecord;
    final newStatus = newRow['status'] as String?;
    if (newStatus != 'completed') return;

    // Guard: don't fire if the patient themselves just completed it
    final completedByRole = newRow['completed_by_role'] as String?;
    
    // If the patient marked it complete themselves, _completeCurrentTest 
    // will handle the UI and navigation. Ignore this event.
    if (completedByRole == 'patient') return;

    _isAutoAdvancing = true;

    final String messageText = '✓ Doctor marked this test complete';

    // Show a banner so the patient knows what's happening
    if (mounted) {
      _dismissOverlay(); // clear any existing queue overlay
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(messageText)),
        ]),
        backgroundColor: const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ));
    }

    // Small delay so snackbar is visible before screen reloads
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    // Advance exactly like _completeCurrentTest Step 3 does:
    // if more tests in this room → move to next; else reload navigation
    if (_showingRoomTests && _testIndexInRoom < _testsInRoom.length - 1) {
      setState(() {
        _testIndexInRoom++;
        _currentTest = _testsInRoom[_testIndexInRoom];
        _hasReached  = true;
      });
      // Subscribe to the next test's row for doctor completion
      _subscribeToDoctorCompletion(_currentTest!['id'] as String);
    } else {
      setState(() {
        _isLoading    = true;
        _hasReached   = false;
        _prevPosition = null;
      });
      await _loadNavigationData();
      if (mounted && _currentTest == null) _showCompletionDialog();
    }

    _isAutoAdvancing = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // _recalcBadge
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _recalcBadge(String roomId) async {
    if (!mounted) return;
    try {
      final preCount = await _svc.getRoomWaitingCount(roomId);

      if (!mounted) return;

      if (_hasReached && _currentTest != null) {
        final result = await _svc.computeQueuePosition(
          roomId: roomId,
          appointmentTestId: _currentTest!['id'] as String,
        );

        final smartEta = await _svc.computeSmartEta(
          roomId: roomId,
          patientsAhead: result.patientsAhead,
        );

        if (!mounted) return;

        final newPosition = result.position;
        final didImprove  = _prevPosition != null &&
            newPosition < _prevPosition! &&
            _hasReached;

        setState(() {
          _preArrivalCount   = preCount;
          _myPosition        = newPosition;
          _totalInRoom       = result.total;
          _estimatedWaitMins = smartEta;
          _lastUpdated       = DateTime.now();
        });

        if (didImprove) {
          _showPositionChangedOverlay(newPosition, result.total);
        }

        _prevPosition = newPosition;

      } else {
        if (!mounted) return;
        setState(() {
          _preArrivalCount = preCount;
          _lastUpdated     = DateTime.now();
        });
      }
    } catch (e) {
      print('❌ Error in _recalcBadge: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // POSITION CHANGE OVERLAY
  // ─────────────────────────────────────────────────────────────────────────
  void _showPositionChangedOverlay(int newPosition, int total) {
    _dismissOverlay();

    _overlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    final slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _overlayCtrl!, curve: Curves.easeOutCubic));

    final isNowNext = newPosition == 1;

    _positionOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        child: SlideTransition(
          position: slideAnim,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isNowNext
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (isNowNext
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF2563EB))
                        .withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.elasticOut,
                  builder: (_, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isNowNext
                          ? Icons.notifications_active_rounded
                          : Icons.arrow_upward_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNowNext
                              ? '🎉  You\'re next!'
                              : '⬆️  Queue update',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isNowNext
                              ? 'Please be ready — proceed inside soon'
                              : 'Now position $newPosition of $total',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.88),
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ]),
                ),
                GestureDetector(
                  onTap: _dismissOverlay,
                  child: Icon(Icons.close_rounded,
                      color: Colors.white.withOpacity(0.7), size: 18),
                ),
              ]),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_positionOverlay!);
    _overlayCtrl!.forward();

    Future.delayed(const Duration(milliseconds: 3500), _dismissOverlay);
  }

  void _dismissOverlay() {
    _overlayCtrl?.reverse().then((_) {
      _positionOverlay?.remove();
      _positionOverlay = null;
      _overlayCtrl?.dispose();
      _overlayCtrl = null;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOAD NAVIGATION DATA
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _subscribeForRoom(String roomNumber) async {
    try {
      final rows = await supabase
          .from('test_rooms')
          .select('id')
          .eq('room_number', roomNumber)
          .limit(1);

      if (!mounted) return;
      if ((rows as List).isEmpty) return;

      final roomId = rows[0]['id'] as String;
      _currentRoomId = roomId;
      _subscribeToRoomUpdates(roomId);
    } catch (e) {
      print('Error fetching room id: $e');
    }
  }

  Future<void> _loadNavigationData() async {
    setState(() => _isLoading = true);

    try {
      final tests = await _svc.getOptimalTestSequence(widget.appointmentId);

      if (tests.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final currentLoc = _svc.getCurrentLocation(tests);
      final nextTest   = _svc.getNextTest(tests);

      if (nextTest != null) {
        final tr        = nextTest['test_rooms'] as Map<String, dynamic>?;
        final toRoom    = tr?['room_number'] ?? 'Unknown';
        final toFloor   = tr?['floor']       ?? 'Ground Floor';
        final fromFloor = _getFloorForLocation(currentLoc);

        final segments = await _svc.getNavigationPathSegments(
          fromLocation: currentLoc,
          toLocation:   toRoom,
          fromFloor:    fromFloor,
          toFloor:      toFloor,
        );

        final testsInRoom = _svc.getPendingTestsForRoom(tests, toRoom);

        setState(() {
          _allTests        = tests;
          _currentTest     = nextTest;
          _currentLoc      = currentLoc;
          _pathSegments    = segments;
          _selectedFloor   = segments.isNotEmpty
              ? segments.first.floor : toFloor;
          _testsInRoom     = testsInRoom;
          _testIndexInRoom = 0;
          _showingRoomTests = testsInRoom.length > 1;
          _isLoading       = false;
          _hasReached      = false;
          _myPosition        = 1;
          _totalInRoom       = 0;
          _estimatedWaitMins = 0;
          _preArrivalCount   = 0;
          _prevPosition      = null;
          _realtimeFailed    = false;
        });

        _roomStream?.unsubscribe();
        _fallbackTimer?.cancel();
        _subscribeForRoom(toRoom);

        // Watch this specific test row — if doctor marks it complete,
        // _checkIfDoctorCompleted() will auto-advance the patient.
        _subscribeToDoctorCompletion(nextTest['id'] as String);

      } else {
        setState(() {
          _allTests    = tests;
          _currentTest = null;
          _isLoading   = false;
        });
      }
    } catch (e) {
      print('❌ Error loading navigation data: $e');
      setState(() => _isLoading = false);
    }
  }

  String _getFloorForLocation(String loc) {
    if (loc == 'Main Entrance' || loc == 'Lab A' ||
        loc == 'Lab B'         || loc == 'Elevator') return 'Ground Floor';
    if (loc.startsWith('Room 1')) return '1st Floor';
    if (loc.startsWith('Room 2')) return '2nd Floor';
    return 'Ground Floor';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MARK AS REACHED
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _markAsReached() async {
    if (_currentTest == null) return;

    final tr         = _currentTest!['test_rooms'] as Map<String, dynamic>?;
    final roomNumber = tr?['room_number'] ?? '';

    setState(() => _isLoading = true);

    final success = await _svc.updateTestStatus(
      appointmentTestId: _currentTest!['id'],
      status: 'reached',
    );

    if (!success || !mounted) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _hasReached = true;
      _isLoading  = false;
      _prevPosition = null;
    });

    if (_currentRoomId != null) {
      await _recalcBadge(_currentRoomId!);
    }

    if (!mounted) return;

    final ahead = _myPosition - 1;
    final snack = ahead == 0
        ? 'Added to queue — you are next!'
        : ahead == 1
        ? 'Added to queue — 1 patient waiting before you'
        : 'Added to queue — $ahead patients waiting before you';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(snack)),
      ]),
      backgroundColor: const Color(0xFF16A34A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));

    _prevPosition = _myPosition;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ NEW: Look up which doctor is currently in the given room
  //
  // Queries doctor_room_sessions for the active session in this room today.
  // Returns null if no doctor is assigned yet.
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> _getDoctorIdForRoom(String roomId) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final rows = await supabase
          .from('doctor_room_sessions')
          .select('doctor_id')
          .eq('room_id', roomId)         // room_id FK to test_rooms.id
          .eq('session_date', today)
          .eq('status', 'active')
          .order('start_time', ascending: false)
          .limit(1);

      if ((rows as List).isEmpty) return null;
      return rows[0]['doctor_id'] as String?;
    } catch (e) {
      print('❌ _getDoctorIdForRoom error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ NEW: Record a treatment entry in patient_treatments table
  //
  // Called for each appointment_test that is being completed.
  // Captures patient, doctor, room, and test at the moment of completion
  // so analytics are always historically accurate.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _recordTreatment({
    required String appointmentTestId,
    required String roomId,
    required String? doctorId,
  }) async {
    if (doctorId == null) {
      print('⚠️ No doctor found for room $roomId — skipping treatment record');
      return;
    }
    try {
      // NOTE: appointment_id is intentionally omitted.
      // _currentTest does not carry that field (getOptimalTestSequence
      // does not select it), so reading it always returns null.
      // A null FK value causes a silent insert failure.
      // We identify every treatment uniquely by appointment_test_id alone.
      await supabase.from('patient_treatments').insert({
        'appointment_test_id': appointmentTestId,
        'doctor_id':           doctorId,
        'room_id':             roomId,
        'completed_at':        DateTime.now().toUtc().toIso8601String(),
      });

      print('✅ Treatment recorded: test=$appointmentTestId doctor=$doctorId room=$roomId');
    } catch (e) {
      // Non-fatal — the core test completion already succeeded
      print('❌ Failed to record treatment: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPLETE CURRENT TEST
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _completeCurrentTest() async {
    if (_currentTest == null) return;

    if (!_hasReached) {
      await _svc.updateTestStatus(
          appointmentTestId: _currentTest!['id'], status: 'reached');
    }

    // ── Step 1: Mark the test as completed in appointment_tests ──────────
    final success = await _svc.updateTestStatus(
        appointmentTestId: _currentTest!['id'], status: 'completed');

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error updating test status'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    // ── Step 2: ✅ Record treatment snapshot (doctor captured at this moment) ─
    if (_currentRoomId != null) {
      final doctorId = await _getDoctorIdForRoom(_currentRoomId!);
      await _recordTreatment(
        appointmentTestId: _currentTest!['id'] as String,
        roomId: _currentRoomId!,
        doctorId: doctorId,
      );
    }

    // ── Step 3: Advance to next test or reload ────────────────────────────
    if (_showingRoomTests && _testIndexInRoom < _testsInRoom.length - 1) {
      setState(() {
        _testIndexInRoom++;
        _currentTest = _testsInRoom[_testIndexInRoom];
        _hasReached  = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Expanded(child: Text('✓ You marked this test as complete')),
        ]),
        backgroundColor: const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ));
    } else {
      _dismissOverlay();
      setState(() {
        _isLoading    = true;
        _hasReached   = false;
        _prevPosition = null;
      });
      await _loadNavigationData();
      if (mounted && _currentTest == null) _showCompletionDialog();
    }
  }

  // ── Complete all tests in room ────────────────────────────────────────────
  Future<void> _completeAllTestsInRoom() async {
    if (_testsInRoom.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Complete All Tests?'),
        content: Text(
            'Complete all ${_testsInRoom.length} tests in this room now?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green),
            child: const Text('Complete All'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
        const Center(child: CircularProgressIndicator()));

    // ── Step 1: Complete all tests via navigation service ─────────────────
    await _svc.completeAllTestsInRoom(_testsInRoom);

    // ── Step 2: ✅ Record a treatment entry for EACH completed test ────────
    if (_currentRoomId != null) {
      final doctorId = await _getDoctorIdForRoom(_currentRoomId!);
      for (final test in _testsInRoom) {
        final testId = test['id'] as String?;
        if (testId != null) {
          await _recordTreatment(
            appointmentTestId: testId,
            roomId: _currentRoomId!,
            doctorId: doctorId,
          );
        }
      }
    }

    Navigator.pop(context);
    _dismissOverlay();
    await _loadNavigationData();
    if (_currentTest == null) _showCompletionDialog();
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.celebration, color: Colors.green, size: 32),
          SizedBox(width: 12),
          Expanded(child: Text('All Tests Complete!')),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          const Text('Congratulations! 🎉',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('You have completed all your tests.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Results available within 24-48 hours',
              style: TextStyle(
                  fontSize: 13, color: Colors.blue[900]),
              textAlign: TextAlign.center,
            ),
          ),
        ]),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Done',
                style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation'),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentTest == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation'),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white),
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _svc.areAllTestsCompleted(_allTests)
                  ? Icons.celebration : Icons.info_outline,
              size: 80,
              color: _svc.areAllTestsCompleted(_allTests)
                  ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              _svc.areAllTestsCompleted(_allTests)
                  ? 'All tests completed!' : 'No pending tests',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to Home')),
          ],
        )),
      );
    }

    final tr         = _currentTest!['test_rooms'] as Map<String, dynamic>?;
    final testName   = _currentTest!['test_name'] ?? 'Unknown Test';
    final roomNumber = tr?['room_number'] ?? 'Unknown';
    final floor      = tr?['floor']       ?? 'Ground Floor';
    final progress   = _svc.getProgress(_allTests);

    final floors = _pathSegments.map((s) => s.floor).toSet().toList();
    if (!floors.contains(_selectedFloor)) floors.add(_selectedFloor);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Card 1: Room & Test Info ─────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.blue.shade100, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.blue.withOpacity(0.07),
                        blurRadius: 8,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _showingRoomTests
                            ? 'Test ${_testIndexInRoom + 1} of '
                            '${_testsInRoom.length} in this room'
                            : 'Test ${progress['completed']! + 1} of '
                            '${progress['total']}',
                        style: TextStyle(fontSize: 11,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      Text(testName,
                          style: const TextStyle(fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      const SizedBox(height: 8),
                      Row(children: [
                        _infoPill(Icons.meeting_room_outlined,
                            roomNumber, Colors.blue),
                        const SizedBox(width: 8),
                        _infoPill(Icons.layers_outlined,
                            floor, Colors.indigo),
                      ]),
                      if (_showingRoomTests) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.orange.shade200),
                          ),
                          child: Row(children: [
                            const Icon(Icons.info_outline,
                                color: Colors.orange, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${_testsInRoom.length} tests in this room',
                              style: TextStyle(fontSize: 12,
                                  color: Colors.orange[900],
                                  fontWeight: FontWeight.w600),
                            ),
                          ]),
                        ),
                      ],
                    ]),
              ),
              const SizedBox(height: 10),

              // ── Card 2: Queue Status ─────────────────────────────────
              if (_hasReached) ...[
                QueueStatusWidget(
                  roomNumber:            roomNumber,
                  mode:                  QueueWidgetMode.postArrival,
                  myPosition:            _myPosition,
                  totalInRoom:           _totalInRoom,
                  estimatedWaitMinutes:  _estimatedWaitMins,
                ),
              ] else ...[
                QueueStatusWidget(
                  roomNumber:      roomNumber,
                  mode:            QueueWidgetMode.preArrival,
                  preArrivalCount: _preArrivalCount,
                ),
              ],

              // ── Stale data warning ───────────────────────────────────
              if (_realtimeFailed && _lastUpdated != null)
                _buildStaleWarning(),

              const SizedBox(height: 16),

              // ── Floor toggle ─────────────────────────────────────────
              if (floors.length > 1) ...[
                const Text('Floor View',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 46,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: floors.length,
                    itemBuilder: (_, i) {
                      final f   = floors[i];
                      final sel = _selectedFloor == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f),
                          selected: sel,
                          onSelected: (v) {
                            if (v) {
                              setState(() => _selectedFloor = f);
                            }
                          },
                          selectedColor: Colors.blue,
                          backgroundColor: Colors.grey[200],
                          labelStyle: TextStyle(
                            color: sel ? Colors.white : Colors.black,
                            fontWeight: sel
                                ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Hospital map ─────────────────────────────────────────
              const Text('Hospital Map',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              InteractiveFloorMap(
                floor: _selectedFloor,
                currentLocation: _currentLoc,
                destination: roomNumber,
                pathSegments: _pathSegments,
              ),
              const SizedBox(height: 24),

              // ── Directions ───────────────────────────────────────────
              const Text('Step-by-Step Directions',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ..._buildDirections(),

              const SizedBox(height: 90),
            ]),
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WIDGET HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStaleWarning() {
    if (_lastUpdated == null) return const SizedBox.shrink();
    final ago = DateTime.now().difference(_lastUpdated!).inSeconds;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(children: [
        Icon(Icons.signal_wifi_off_rounded,
            size: 14, color: Colors.amber[800]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Live updates paused — last updated ${ago}s ago. '
                'Polling every 8s.',
            style: TextStyle(
                fontSize: 11, color: Colors.amber[900]),
          ),
        ),
      ]),
    );
  }

  Widget _infoPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }

  List<Widget> _buildDirections() {
    final destRoom = (_currentTest?['test_rooms']
    as Map<String, dynamic>?)?['room_number'] ?? 'Unknown';

    final seg = _pathSegments.firstWhere(
          (s) => s.floor == _selectedFloor,
      orElse: () => _pathSegments.isNotEmpty
          ? _pathSegments.first
          : PathSegment(
          floor: _selectedFloor,
          pathId: '',
          fromLocation: _currentLoc,
          toLocation: destRoom),
    );

    return _svc.generateFallbackDirections(
      fromRoom: seg.fromLocation,
      toRoom: seg.toLocation,
      fromFloor: seg.floor,
      toFloor: seg.floor,
    ).map((d) =>
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!)),
          child: Row(children: [
            Container(
                width: 26, height: 26,
                decoration: const BoxDecoration(
                    color: Colors.blue, shape: BoxShape.circle),
                child: Center(child: Text(d['step']!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11)))),
            const SizedBox(width: 12),
            Expanded(child: Text(d['instruction']!,
                style: const TextStyle(fontSize: 14))),
          ]),
        )).toList();
  }

  Widget _buildBottomActions() {
    final roomNumber = (_currentTest?['test_rooms']
    as Map<String, dynamic>?)?['room_number'] ?? 'Destination';

    final bool isMyTurn = _myPosition == 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2))],
      ),
      child: SafeArea(child: Column(
          mainAxisSize: MainAxisSize.min, children: [

        if (_hasReached && !isMyTurn) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(children: [
              Icon(Icons.lock_clock_rounded,
                  size: 16, color: Colors.amber[800]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Please wait — you are $_myPosition of $_totalInRoom in queue. '
                      'The button will unlock when it\'s your turn.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber[900],
                      fontWeight: FontWeight.w500),
                ),
              ),
            ]),
          ),
        ],

        if (_hasReached && _showingRoomTests &&
            _testsInRoom.length > 1) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isMyTurn ? _completeAllTestsInRoom : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                isMyTurn ? Colors.orange : Colors.grey[300],
                foregroundColor:
                isMyTurn ? Colors.white : Colors.grey[500],
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isMyTurn
                        ? Icons.done_all
                        : Icons.lock_outline_rounded),
                    const SizedBox(width: 8),
                    Text(
                      isMyTurn
                          ? 'Complete All ${_testsInRoom.length} Tests in Room'
                          : 'Waiting for your turn...',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ]),
            ),
          ),
          const SizedBox(height: 8),
          Text('or one by one:',
              style: TextStyle(fontSize: 12,
                  color: Colors.grey[600])),
          const SizedBox(height: 8),
        ],

        SizedBox(
          width: double.infinity,
          child: _hasReached

          // POST-ARRIVAL → Mark Completed (queue-locked)
              ? ElevatedButton(
            onPressed: isMyTurn ? _completeCurrentTest : null,
            style: ElevatedButton.styleFrom(
              backgroundColor:
              isMyTurn ? const Color(0xFF22C55E) : Colors.grey[300],
              foregroundColor:
              isMyTurn ? Colors.white : Colors.grey[500],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isMyTurn
                    ? Icons.check_circle_outline_rounded
                    : Icons.lock_outline_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isMyTurn
                      ? (_showingRoomTests
                      ? 'Mark Test ${_testIndexInRoom + 1}'
                      '/${_testsInRoom.length} as Completed'
                      : 'Mark Test as Completed')
                      : 'Not Your Turn Yet',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          )

          // PRE-ARRIVAL → I've Reached
              : ElevatedButton(
            onPressed: _markAsReached,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on_rounded),
                  const SizedBox(width: 8),
                  Text("I've Reached $roomNumber",
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
          ),
        ),
      ])),
    );
  }
}

// ── Pulsing live dot ──────────────────────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _a = Tween<double>(begin: 0.25, end: 1.0).animate(_c);
  }

  @override void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _a,
    child: Container(width: 8, height: 8,
        decoration: BoxDecoration(
            color: widget.color, shape: BoxShape.circle)),
  );
}