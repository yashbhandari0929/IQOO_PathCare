// lib/services/doctor_service_v2.dart
// TIER 3 VERSION - Enhanced with time tracking, analytics, and priority management

import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ============================================================================
  // AUTHENTICATION & PROFILE (from Tier 1)
  // ============================================================================

  Future<Map<String, dynamic>?> getCurrentDoctor() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final response = await _supabase
          .from('doctors')
          .select('*')
          .eq('auth_id', user.id)
          .single();

      return response;
    } catch (e) {
      print('Error getting current doctor: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getDoctorById(String doctorId) async {
    try {
      final response = await _supabase
          .from('doctors')
          .select('*')
          .eq('id', doctorId)
          .single();

      return response;
    } catch (e) {
      print('Error getting doctor: $e');
      return null;
    }
  }

  // ============================================================================
  // DASHBOARD STATISTICS (from Tier 1)
  // ============================================================================

  Future<Map<String, dynamic>?> getDailyStats(String doctorId) async {
    try {
      final response = await _supabase.rpc(
        'get_doctor_daily_stats',
        params: {
          'p_doctor_id': doctorId,
          'p_date': DateTime.now().toIso8601String().split('T')[0],
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        return response[0] as Map<String, dynamic>;
      }

      return {
        'total_patients': 0,
        'patients_attended': 0,
        'patients_pending': 0,
        'total_time_minutes': 0,
        'active_session_room': null,
        'active_session_start': null,
      };
    } catch (e) {
      print('Error getting daily stats: $e');
      return null;
    }
  }

  // ============================================================================
  // TIER 3 NEW: ENHANCED ANALYTICS
  // ============================================================================

  /// Get detailed analytics for doctor's performance
  Future<Map<String, dynamic>> getDetailedAnalytics(String doctorId) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      // Get session data
      final sessions = await _supabase
          .from('doctor_room_sessions')
          .select('*')
          .eq('doctor_id', doctorId)
          .eq('session_date', today);

      // Get all tests completed today
      final completedTests = await _supabase
          .from('appointment_tests')
          .select('test_duration_minutes, completed_at')
          .eq('attended_by_doctor_id', doctorId)
          .gte('completed_at', '${today}T00:00:00')
          .lte('completed_at', '${today}T23:59:59');

      // Calculate metrics
      int totalTests = 0;
      int totalMinutes = 0;
      int shortestTest = 999999;
      int longestTest = 0;
      List<int> testDurations = [];

      if (completedTests is List) {
        totalTests = completedTests.length;

        for (var test in completedTests) {
          final duration = test['test_duration_minutes'] as int? ?? 0;
          if (duration > 0) {
            testDurations.add(duration);
            totalMinutes += duration;
            if (duration < shortestTest) shortestTest = duration;
            if (duration > longestTest) longestTest = duration;
          }
        }
      }

      final avgTestTime = testDurations.isNotEmpty
          ? (testDurations.reduce((a, b) => a + b) / testDurations.length)
                .round()
          : 0;

      return {
        'total_sessions': sessions is List ? sessions.length : 0,
        'total_tests_completed': totalTests,
        'total_time_minutes': totalMinutes,
        'average_test_time': avgTestTime,
        'shortest_test': shortestTest == 999999 ? 0 : shortestTest,
        'longest_test': longestTest,
        'efficiency_score': _calculateEfficiencyScore(totalTests, totalMinutes),
      };
    } catch (e) {
      print('Error getting detailed analytics: $e');
      return {
        'total_sessions': 0,
        'total_tests_completed': 0,
        'total_time_minutes': 0,
        'average_test_time': 0,
        'shortest_test': 0,
        'longest_test': 0,
        'efficiency_score': 0,
      };
    }
  }

  int _calculateEfficiencyScore(int testsCompleted, int totalMinutes) {
    if (testsCompleted == 0 || totalMinutes == 0) return 0;

    // Score based on tests per hour
    final testsPerHour = (testsCompleted / (totalMinutes / 60));

    // Scale to 0-100
    // Assuming 8 tests/hour is excellent
    final score = ((testsPerHour / 8) * 100).round();
    return score > 100 ? 100 : score;
  }

  // ============================================================================
  // TIER 3 NEW: TIME TRACKING
  // ============================================================================

  /// Start time tracking for a specific patient
  Future<bool> startPatientTimer(String appointmentId, String doctorId) async {
    try {
      // Update all tests for this appointment to in_progress
      await _supabase
          .from('appointment_tests')
          .update({'status': 'in_progress', 'attended_by_doctor_id': doctorId})
          .eq('appointment_id', appointmentId)
          .neq('status', 'completed');

      return true;
    } catch (e) {
      print('Error starting patient timer: $e');
      return false;
    }
  }

  /// Get current time spent with patient
  int getTimeWithPatient(Map<String, dynamic> patient) {
    final tests = patient['tests_in_room'] as List? ?? [];

    DateTime? earliestStart;

    for (var test in tests) {
      final reachedAt = test['reached_at'] as String?;
      if (reachedAt != null) {
        final reachedTime = DateTime.parse(reachedAt);
        if (earliestStart == null || reachedTime.isBefore(earliestStart)) {
          earliestStart = reachedTime;
        }
      }
    }

    if (earliestStart == null) return 0;

    final now = DateTime.now();
    final difference = now.difference(earliestStart);
    return difference.inMinutes;
  }

  // ============================================================================
  // TIER 3 NEW: PRIORITY MANAGEMENT
  // ============================================================================

  /// Update patient priority level
  Future<bool> updatePatientPriority(
    String appointmentId,
    String priorityLevel, // 'normal', 'high', 'urgent'
  ) async {
    try {
      await _supabase
          .from('appointments')
          .update({'priority_level': priorityLevel})
          .eq('id', appointmentId);

      return true;
    } catch (e) {
      print('Error updating priority: $e');
      return false;
    }
  }

  /// Get patients by priority
  List<Map<String, dynamic>> filterByPriority(
    List<Map<String, dynamic>> patients,
    String priority,
  ) {
    return patients.where((patient) {
      final patientPriority = patient['priority_level'] as String? ?? 'normal';
      return patientPriority == priority;
    }).toList();
  }

  /// Sort patients by priority (urgent first)
  List<Map<String, dynamic>> sortByPriority(
    List<Map<String, dynamic>> patients,
  ) {
    final priorityOrder = {'urgent': 1, 'high': 2, 'normal': 3};

    patients.sort((a, b) {
      final priorityA = a['priority_level'] as String? ?? 'normal';
      final priorityB = b['priority_level'] as String? ?? 'normal';

      final orderA = priorityOrder[priorityA] ?? 4;
      final orderB = priorityOrder[priorityB] ?? 4;

      return orderA.compareTo(orderB);
    });

    return patients;
  }

  // ============================================================================
  // TIER 3 NEW: QUICK ACTIONS
  // ============================================================================

  /// Skip patient (postpone to end of queue)
  Future<bool> skipPatient(String appointmentId, String reason) async {
    try {
      // Update appointment with skip reason
      await _supabase
          .from('appointments')
          .update({'special_instructions': 'SKIPPED: $reason'})
          .eq('id', appointmentId);

      // Update all pending tests to scheduled status
      await _supabase
          .from('appointment_tests')
          .update({'status': 'pending'})
          .eq('appointment_id', appointmentId)
          .eq('status', 'reached');

      return true;
    } catch (e) {
      print('Error skipping patient: $e');
      return false;
    }
  }

  /// Mark patient as no-show
  Future<bool> markNoShow(String appointmentId) async {
    try {
      await _supabase
          .from('appointments')
          .update({'status': 'no_show'})
          .eq('id', appointmentId);

      return true;
    } catch (e) {
      print('Error marking no-show: $e');
      return false;
    }
  }

  // ============================================================================
  // TIER 3 NEW: SMART SUGGESTIONS
  // ============================================================================

  /// Get suggested next room based on queue
  Future<String?> getSuggestedNextRoom(String currentRoomNumber) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      // Get all rooms with their queue counts
      final response = await _supabase.rpc(
        'get_room_stats_for_doctor',
        params: {'p_date': today},
      );

      if (response == null || response is! List || response.isEmpty) {
        return null;
      }

      final rooms = List<Map<String, dynamic>>.from(response);

      // Filter out current room
      final otherRooms = rooms
          .where((r) => r['room_number'] != currentRoomNumber)
          .toList();

      if (otherRooms.isEmpty) return null;

      // Sort by queue count and total scheduled
      otherRooms.sort((a, b) {
        final queueA = a['current_queue'] as int? ?? 0;
        final queueB = b['current_queue'] as int? ?? 0;

        if (queueA != queueB) return queueB.compareTo(queueA);

        // If queue is same, sort by total scheduled
        final totalA = a['total_scheduled'] as int? ?? 0;
        final totalB = b['total_scheduled'] as int? ?? 0;
        return totalB.compareTo(totalA);
      });

      // Return room with highest queue
      return otherRooms.first['room_number'] as String?;
    } catch (e) {
      print('Error getting suggested room: $e');
      return null;
    }
  }

  /// Check if room has pending patients
  Future<bool> roomHasPendingPatients(String roomId) async {
    try {
      final patients = await getPatientsForRoom(roomId);

      // Check if any patient has pending or reached tests
      for (var patient in patients) {
        final tests = patient['tests_in_room'] as List? ?? [];
        final hasPending = tests.any(
          (t) => t['status'] == 'pending' || t['status'] == 'reached',
        );
        if (hasPending) return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  // ============================================================================
  // ROOM SELECTION (from Tier 1)
  // ============================================================================

  Future<List<Map<String, dynamic>>> getRoomStats() async {
    try {
      final response = await _supabase.rpc(
        'get_room_stats_for_doctor',
        params: {'p_date': DateTime.now().toIso8601String().split('T')[0]},
      );

      if (response != null && response is List) {
        return List<Map<String, dynamic>>.from(response);
      }

      return [];
    } catch (e) {
      print('Error getting room stats: $e');
      return [];
    }
  }

  Map<String, List<Map<String, dynamic>>> groupRoomsByFloor(
    List<Map<String, dynamic>> rooms,
  ) {
    final Map<String, List<Map<String, dynamic>>> grouped = {
      'Ground Floor': [],
      '1st Floor': [],
      '2nd Floor': [],
    };

    for (var room in rooms) {
      final floor = room['floor'] as String? ?? 'Ground Floor';
      if (grouped.containsKey(floor)) {
        grouped[floor]!.add(room);
      }
    }

    return grouped;
  }

  // ============================================================================
  // SESSION MANAGEMENT (from Tier 1)
  // ============================================================================

  Future<String?> startSession(String doctorId, String roomNumber) async {
    try {
      final response = await _supabase.rpc(
        'start_doctor_session',
        params: {'p_doctor_id': doctorId, 'p_room_number': roomNumber},
      );

      if (response != null) {
        return response.toString();
      }

      return null;
    } catch (e) {
      print('Error starting session: $e');
      return null;
    }
  }

  Future<bool> endSession(String sessionId) async {
    try {
      final response = await _supabase.rpc(
        'end_doctor_session',
        params: {'p_session_id': sessionId},
      );

      return response == true;
    } catch (e) {
      print('Error ending session: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getActiveSession(String doctorId) async {
    try {
      final response = await _supabase
          .from('doctor_room_sessions')
          .select('*')
          .eq('doctor_id', doctorId)
          .eq('session_date', DateTime.now().toIso8601String().split('T')[0])
          .eq('status', 'active')
          .order('start_time', ascending: false)
          .limit(1);

      if (response != null && response is List && response.isNotEmpty) {
        return response[0] as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('Error getting active session: $e');
      return null;
    }
  }

  // ============================================================================
  // PATIENT MANAGEMENT (from Tier 1)
  // ============================================================================

  Future<List<Map<String, dynamic>>> getPatientsForRoom(String roomId) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      final response = await _supabase
          .from('appointments')
          .select('''
            id,
            status,
            priority_level,
            patients ( full_name ),
            appointment_tests (
              id,
              status,
              test_id
            )
          ''')
          .eq('room_id', roomId)
          .eq('appointment_date', today)
          .inFilter('status', const ['scheduled', 'checked_in', 'in_progress']);

      final List<Map<String, dynamic>> result = [];
      for (var row in response as List) {
        final p = row['patients'] as Map<String, dynamic>?;
        result.add({
          'appointment_id': row['id'],
          'patient_name': p?['full_name'] ?? 'Unknown',
          'priority_level': row['priority_level'] ?? 'normal',
          'tests_in_room': row['appointment_tests'] ?? [],
        });
      }

      return result;
    } catch (e) {
      print('Error getting patients for room: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> filterPatientsByStatus(
    List<Map<String, dynamic>> patients,
    String status,
  ) {
    return patients.where((patient) {
      final tests = patient['tests_in_room'] as List?;
      if (tests == null || tests.isEmpty) return false;

      switch (status) {
        case 'waiting':
          return tests.any((t) => t['status'] == 'reached') &&
              !tests.any((t) => t['status'] == 'in_progress');
        case 'in_progress':
          return tests.any((t) => t['status'] == 'in_progress');
        case 'completed':
          return tests.every((t) => t['status'] == 'completed');
        case 'scheduled':
          return tests.every((t) => t['status'] == 'pending');
        default:
          return true;
      }
    }).toList();
  }

  List<Map<String, dynamic>> sortPatients(
    List<Map<String, dynamic>> patients,
    String sortBy,
  ) {
    switch (sortBy) {
      case 'time':
        patients.sort((a, b) {
          final timeA = a['scheduled_time'] as String? ?? '';
          final timeB = b['scheduled_time'] as String? ?? '';
          return timeA.compareTo(timeB);
        });
        break;

      case 'name':
        patients.sort((a, b) {
          final nameA = a['patient_name'] as String? ?? '';
          final nameB = b['patient_name'] as String? ?? '';
          return nameA.compareTo(nameB);
        });
        break;

      case 'status':
        final statusOrder = {
          'waiting': 1,
          'in_progress': 2,
          'scheduled': 3,
          'completed': 4,
        };

        patients.sort((a, b) {
          final statusA = _getPatientStatus(a['tests_in_room']);
          final statusB = _getPatientStatus(b['tests_in_room']);

          final orderA = statusOrder[statusA] ?? 5;
          final orderB = statusOrder[statusB] ?? 5;

          return orderA.compareTo(orderB);
        });
        break;

      case 'priority': // NEW in Tier 3
        return sortByPriority(patients);
    }

    return patients;
  }

  String _getPatientStatus(dynamic tests) {
    if (tests == null || tests is! List || tests.isEmpty) return 'unknown';

    final testsList = tests as List;

    if (testsList.any((t) => t['status'] == 'in_progress')) {
      return 'in_progress';
    } else if (testsList.any((t) => t['status'] == 'reached')) {
      return 'waiting';
    } else if (testsList.every((t) => t['status'] == 'completed')) {
      return 'completed';
    } else {
      return 'scheduled';
    }
  }

  // ============================================================================
  // TEST COMPLETION (from Tier 1)
  // ============================================================================

  Future<bool> completeTest({
    required String testId,
    required String doctorId,
    required String sessionId,
    String? notes,
  }) async {
    try {
      // First try the RPC if it exists in your Supabase project
      try {
        final response = await _supabase.rpc(
          'mark_test_completed',
          params: {
            'p_test_id': testId,
            'p_doctor_id': doctorId,
            'p_session_id': sessionId,
            'p_notes': notes,
          },
        );
        if (response == true) return true;
      } catch (rpcError) {
        // RPC may not exist — fall through to direct DB update
        print(
          '[DoctorService] mark_test_completed RPC not found, using direct update: $rpcError',
        );
      }

      // Direct DB update fallback — works without any custom RPC
      await _supabase
          .from('appointment_tests')
          .update({
            'status': 'completed',
            'attended_by_doctor_id': doctorId,
            'completed_at': DateTime.now().toIso8601String(),
            'completed_by_role': 'doctor',
            if (notes != null) 'notes': notes,
          })
          .eq('id', testId);

      return true;
    } catch (e) {
      print('[DoctorService] Error completing test: $e');
      return false;
    }
  }

  Future<bool> completeMultipleTests({
    required List<String> testIds,
    required String doctorId,
    required String sessionId,
    String? notes,
  }) async {
    try {
      for (final testId in testIds) {
        final success = await completeTest(
          testId: testId,
          doctorId: doctorId,
          sessionId: sessionId,
          notes: notes,
        );

        if (!success) {
          print('Failed to complete test: $testId');
          return false;
        }
      }

      return true;
    } catch (e) {
      print('Error completing multiple tests: $e');
      return false;
    }
  }

  Future<bool> markPatientAttended({
    required List<String> testIds,
    required String doctorId,
    required String sessionId,
    String? notes,
  }) async {
    return completeMultipleTests(
      testIds: testIds,
      doctorId: doctorId,
      sessionId: sessionId,
      notes: notes,
    );
  }

  // ============================================================================
  // PATIENT STATUS HELPERS (from Tier 1)
  // ============================================================================

  String getPatientStatusText(List tests) {
    if (tests.isEmpty) return 'No Tests';

    final hasInProgress = tests.any((t) => t['status'] == 'in_progress');
    final hasReached = tests.any((t) => t['status'] == 'reached');
    final allCompleted = tests.every((t) => t['status'] == 'completed');
    final allPending = tests.every((t) => t['status'] == 'pending');

    if (hasInProgress) return 'In Progress';
    if (hasReached) return 'Waiting';
    if (allCompleted) return 'Completed';
    if (allPending) return 'Scheduled';

    return 'Mixed Status';
  }

  Map<String, dynamic>? getNextPendingTest(List tests) {
    try {
      return tests.firstWhere(
        (t) => t['status'] == 'pending' || t['status'] == 'reached',
        orElse: () => null,
      );
    } catch (e) {
      return null;
    }
  }

  Map<String, int> countTestsByStatus(List tests) {
    final Map<String, int> counts = {
      'pending': 0,
      'reached': 0,
      'in_progress': 0,
      'completed': 0,
    };

    for (final test in tests) {
      final status = test['status'] as String? ?? 'pending';
      counts[status] = (counts[status] ?? 0) + 1;
    }

    return counts;
  }

  // ============================================================================
  // SEARCH & FILTER (from Tier 1)
  // ============================================================================

  List<Map<String, dynamic>> searchPatients(
    List<Map<String, dynamic>> patients,
    String query,
  ) {
    if (query.trim().isEmpty) return patients;

    final lowerQuery = query.toLowerCase();

    return patients.where((patient) {
      final name = (patient['patient_name'] as String? ?? '').toLowerCase();
      final id = (patient['patient_id'] as String? ?? '').toLowerCase();

      return name.contains(lowerQuery) || id.contains(lowerQuery);
    }).toList();
  }

  // ============================================================================
  // STATISTICS (from Tier 1)
  // ============================================================================

  Map<String, int> calculateRoomStats(List<Map<String, dynamic>> patients) {
    int waiting = 0;
    int inProgress = 0;
    int completed = 0;
    int scheduled = 0;

    for (final patient in patients) {
      final status = _getPatientStatus(patient['tests_in_room']);

      switch (status) {
        case 'waiting':
          waiting++;
          break;
        case 'in_progress':
          inProgress++;
          break;
        case 'completed':
          completed++;
          break;
        case 'scheduled':
          scheduled++;
          break;
      }
    }

    return {
      'total': patients.length,
      'waiting': waiting,
      'in_progress': inProgress,
      'completed': completed,
      'scheduled': scheduled,
    };
  }

  // ============================================================================
  // UTILITIES (from Tier 1)
  // ============================================================================

  String formatTime(String? timeString) {
    if (timeString == null) return '--:--';

    try {
      final time = DateTime.parse('2000-01-01 $timeString');
      final hour = time.hour;
      final minute = time.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

      return '$displayHour:$minute $period';
    } catch (e) {
      return timeString;
    }
  }

  String formatDuration(int? minutes) {
    if (minutes == null || minutes == 0) return '0 min';

    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
  }

  String getStatusColor(String status) {
    switch (status) {
      case 'normal':
        return 'green';
      case 'busy':
        return 'orange';
      case 'very_busy':
        return 'red';
      default:
        return 'gray';
    }
  }

  double calculateCompletionRate(int attended, int total) {
    if (total == 0) return 0.0;
    return (attended / total * 100).roundToDouble();
  }

  // ============================================================================
  // TIER 3 NEW: BATCH OPERATIONS
  // ============================================================================

  /// Complete all waiting patients in room (emergency/end of day)
  Future<int> completeAllWaitingPatients({
    required String roomId,
    required String doctorId,
    required String sessionId,
    String? batchNotes,
  }) async {
    try {
      final patients = await getPatientsForRoom(roomId);
      int completed = 0;

      for (var patient in patients) {
        final tests = patient['tests_in_room'] as List? ?? [];
        final pendingTests = tests
            .where((t) => t['status'] != 'completed')
            .toList();

        if (pendingTests.isNotEmpty) {
          final testIds = pendingTests
              .map((t) => t['test_id'].toString())
              .toList();

          final success = await completeMultipleTests(
            testIds: testIds,
            doctorId: doctorId,
            sessionId: sessionId,
            notes: batchNotes,
          );

          if (success) completed++;
        }
      }

      return completed;
    } catch (e) {
      print('Error completing all waiting patients: $e');
      return 0;
    }
  }
}
