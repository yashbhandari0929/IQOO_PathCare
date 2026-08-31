import 'package:supabase_flutter/supabase_flutter.dart';
import 'booking_service.dart'; // ← ADDED: needed to trigger completion check

final supabase = Supabase.instance.client;

class PathSegment {
  final String floor;
  final String pathId;
  final String fromLocation;
  final String toLocation;

  PathSegment({
    required this.floor,
    required this.pathId,
    required this.fromLocation,
    required this.toLocation,
  });
}

// ── Queue position result ─────────────────────────────────────────────────────
// Encapsulates all queue data for a patient's current room.
// position  = 1-indexed rank by reached_at (arrival order)
// total     = how many patients currently have status='reached' in this room
// estimated = rough wait minutes based on room type and position
class QueuePositionResult {
  final int position;
  final int total;
  final int estimatedWaitMinutes;

  const QueuePositionResult({
    required this.position,
    required this.total,
    required this.estimatedWaitMinutes,
  });

  int get patientsAhead => position - 1;
  bool get isNext => position == 1;

  @override
  String toString() =>
      'QueuePositionResult(pos=$position, total=$total, est=${estimatedWaitMinutes}min)';
}

class NavigationService {
  // ── Optimal Test Sequence ─────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getOptimalTestSequence(
    String appointmentId,
  ) async {
    try {
      final result = await supabase.rpc(
        'get_optimal_test_order',
        params: {'p_appointment_id': appointmentId},
      );
      if (result != null && result is List) {
        return List<Map<String, dynamic>>.from(result);
      }
      return await getTestSequence(appointmentId);
    } catch (e) {
      return await getTestSequence(appointmentId);
    }
  }

  Future<List<Map<String, dynamic>>> getTestSequence(
    String appointmentId,
  ) async {
    try {
      final testsData = await supabase
          .from('appointment_tests')
          .select(
            '*,'
            'tests(*),'
            'appointments(*),'
            'test_rooms!appointment_tests_assigned_room_id_fkey(*)',
          )
          .eq('appointment_id', appointmentId)
          .order('test_order');
      for (var t in testsData) {}
      return List<Map<String, dynamic>>.from(testsData);
    } catch (e) {
      return [];
    }
  }

  // ── PRE-ARRIVAL: general room busyness ────────────────────────────────────
  Future<Map<String, dynamic>?> getRoomQueueInfo(String roomNumber) async {
    try {
      final result = await supabase.rpc(
        'get_room_queue_info',
        params: {'p_room_number': roomNumber},
      );
      if (result != null && result is List && result.isNotEmpty) {
        return result[0] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ── POST-ARRIVAL: compute position from reached_at order ─────────────────
  // Fetches all rows with status='reached' for the given room,
  // sorts them by reached_at ascending (arrival order),
  // then finds where this patient's appointmentTestId sits in that list.
  //
  // This is the SINGLE source of truth for queue position.
  // Called both on initial "Reached" tap and on every realtime event.
  //
  // Example with A (arrived 09:00), B (09:05), C (09:10):
  //   A → position=1, total=3, ahead=0
  //   B → position=2, total=3, ahead=1
  //   C → position=3, total=3, ahead=2
  // After A completes (removed from reached set):
  //   B → position=1, total=2, ahead=0  ("You are next!")
  //   C → position=2, total=2, ahead=1
  Future<QueuePositionResult> computeQueuePosition({
    required String roomId,
    required String appointmentTestId,
  }) async {
    try {
      // Fetch all patients currently waiting (status=reached) in this room,
      // ordered by when they physically arrived (reached_at ascending).
      final rows = await supabase
          .from('appointment_tests')
          .select('id, reached_at')
          .eq('assigned_room_id', roomId)
          .eq('status', 'reached')
          .order('reached_at', ascending: true);

      final list = rows as List;
      final total = list.length;

      // Find our index in the arrival-ordered list.
      int position = 1; // default: first (or alone)
      for (int i = 0; i < list.length; i++) {
        if (list[i]['id'] == appointmentTestId) {
          position = i + 1; // 1-indexed
          break;
        }
      }

      // If our row isn't in the list at all (edge case: status not yet
      // written to DB when realtime fires), default to last position.
      if (total > 0 &&
          position == 1 &&
          !list.any((r) => r['id'] == appointmentTestId)) {
        position = total + 1;
      }

      final effectiveTotal = total == 0 ? 1 : total;
      final waitMinutes = _estimateWaitMinutes(position - 1, roomId);

      final result = QueuePositionResult(
        position: position,
        total: effectiveTotal,
        estimatedWaitMinutes: waitMinutes,
      );
      return result;
    } catch (e) {
      // Safe fallback — show patient as first so they're not misled
      return const QueuePositionResult(
        position: 1,
        total: 1,
        estimatedWaitMinutes: 0,
      );
    }
  }

  // ── PRE-ARRIVAL waiting count for a room ─────────────────────────────────
  // Simpler than computeQueuePosition — just returns total reached count
  // so the pre-arrival badge can say "3 patients waiting now".
  Future<int> getRoomWaitingCount(String roomId) async {
    try {
      final rows = await supabase
          .from('appointment_tests')
          .select('id')
          .eq('assigned_room_id', roomId)
          .eq('status', 'reached');
      return (rows as List).length;
    } catch (e) {
      return 0;
    }
  }

  // ── Smart ETA using actual service times ──────────────────────────────────
  // Computes average minutes-per-patient from completed tests in this room
  // today. Falls back to hardcoded room-type defaults if insufficient data.
  Future<int> computeSmartEta({
    required String roomId,
    required int patientsAhead,
  }) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      final rows = await supabase
          .from('appointment_tests')
          .select('reached_at, completed_at')
          .eq('assigned_room_id', roomId)
          .eq('status', 'completed')
          .gte('completed_at', startOfDay.toIso8601String())
          .not('reached_at', 'is', null)
          .not('completed_at', 'is', null);

      final list = rows as List;

      if (list.length >= 3) {
        // Enough data: compute actual average service time in minutes
        double totalMinutes = 0;
        int counted = 0;
        for (final r in list) {
          final reached = DateTime.tryParse(r['reached_at'] as String? ?? '');
          final completed = DateTime.tryParse(
            r['completed_at'] as String? ?? '',
          );
          if (reached != null && completed != null) {
            final mins = completed.difference(reached).inSeconds / 60.0;
            if (mins > 0 && mins < 120) {
              // sanity check: ignore outliers
              totalMinutes += mins;
              counted++;
            }
          }
        }
        if (counted > 0) {
          final avgMins = (totalMinutes / counted).ceil();

          return patientsAhead * avgMins;
        }
      }

      // Fallback to hardcoded defaults
      return _estimateWaitMinutes(patientsAhead, roomId);
    } catch (e) {
      return _estimateWaitMinutes(patientsAhead, roomId);
    }
  }

  int _estimateWaitMinutes(int patientsAhead, String roomIdOrNumber) {
    int mpp;
    if (roomIdOrNumber.startsWith('Lab'))
      mpp = 5;
    else if (roomIdOrNumber.startsWith('Room 1'))
      mpp = 10;
    else if (roomIdOrNumber.startsWith('Room 2'))
      mpp = 15;
    else
      mpp = 8;
    return patientsAhead * mpp;
  }

  // ── Update Test Status ────────────────────────────────────────────────────
  // Everything here is identical to the original EXCEPT for the block
  // marked ADDED below — which calls BookingService after a test is
  // completed so the parent appointment row flips to 'completed' too.
  // Without this, completed appointments never appear in Completed section.
  Future<bool> updateTestStatus({
    required String appointmentTestId,
    required String status,
  }) async {
    try {
      final updates = <String, dynamic>{'status': status};
      if (status == 'reached') {
        updates['reached_at'] = DateTime.now().toIso8601String();
      } else if (status == 'completed') {
        updates['completed_at'] = DateTime.now().toIso8601String();
        updates['completed_by_role'] = 'patient';
      }

      final response = await supabase
          .from('appointment_tests')
          .update(updates)
          .eq('id', appointmentTestId)
          .select();

      if ((response.isEmpty)) {
        return false;
      }
      // ── ADDED ─────────────────────────────────────────────────────────────
      // After marking a test completed, check whether ALL tests in the
      // parent appointment are now done and flip appointment.status to
      // 'completed' if so. This is what makes the appointment appear in
      // the Completed section on the appointments screen.
      if (status == 'completed') {
        await BookingService().triggerCompletionCheckForTest(appointmentTestId);
      }
      // ─────────────────────────────────────────────────────────────────────

      return true;
    } catch (e) {
      return false;
    }
  }

  // ── All Queue Status ──────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getAllQueueStatus() async {
    try {
      final result = await supabase.from('current_queue_status').select();
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      return [];
    }
  }

  // ── Navigation Path Segments ──────────────────────────────────────────────
  Future<List<PathSegment>> getNavigationPathSegments({
    required String fromLocation,
    required String toLocation,
    required String fromFloor,
    required String toFloor,
  }) async {
    List<PathSegment> segments = [];
    try {
      if (fromFloor == toFloor) {
        final id = _getPathId(fromLocation, toLocation, fromFloor);
        if (id.isNotEmpty) {
          segments.add(
            PathSegment(
              floor: fromFloor,
              pathId: id,
              fromLocation: fromLocation,
              toLocation: toLocation,
            ),
          );
        }
      } else {
        final id1 = _getPathId(fromLocation, 'Elevator', fromFloor);
        if (id1.isNotEmpty) {
          segments.add(
            PathSegment(
              floor: fromFloor,
              pathId: id1,
              fromLocation: fromLocation,
              toLocation: 'Elevator',
            ),
          );
        }
        final id2 = _getPathId('Elevator', toLocation, toFloor);
        if (id2.isNotEmpty) {
          segments.add(
            PathSegment(
              floor: toFloor,
              pathId: id2,
              fromLocation: 'Elevator',
              toLocation: toLocation,
            ),
          );
        }
      }
      return segments;
    } catch (e) {
      return segments;
    }
  }

  String _getPathId(String from, String to, String floor) {
    final toNorm = to.toLowerCase().replaceAll(' ', '_');
    if (floor == 'Ground Floor') {
      if (from == 'Main Entrance' && to == 'Lab A')
        return 'path_entrance_to_lab_a';
      if (from == 'Main Entrance' && to == 'Lab B')
        return 'path_entrance_to_lab_b';
      if (from == 'Lab A' && to == 'Elevator') return 'path_lab_a_to_elevator';
      if (from == 'Lab B' && to == 'Elevator') return 'path_lab_b_to_elevator';
    } else if (floor == '1st Floor' || floor == '2nd Floor') {
      if (from == 'Elevator' && to.startsWith('Room'))
        return 'path_elevator_to_$toNorm';
    }
    return '';
  }

  // ── Test State Helpers ────────────────────────────────────────────────────
  String getCurrentLocation(List<Map<String, dynamic>> tests) {
    for (int i = tests.length - 1; i >= 0; i--) {
      final status = tests[i]['status'] as String?;
      if (status == 'reached' || status == 'completed') {
        final tr = tests[i]['test_rooms'] as Map<String, dynamic>?;
        return tr?['room_number'] ?? 'Main Entrance';
      }
    }
    return 'Main Entrance';
  }

  Map<String, dynamic>? getNextTest(List<Map<String, dynamic>> tests) {
    for (var t in tests) {
      if (t['status'] == 'pending') return t;
    }
    return null;
  }

  bool areAllTestsCompleted(List<Map<String, dynamic>> tests) =>
      tests.every((t) => t['status'] == 'completed');

  Map<String, int> getProgress(List<Map<String, dynamic>> tests) => {
    'completed': tests.where((t) => t['status'] == 'completed').length,
    'total': tests.length,
  };

  Map<String, List<Map<String, dynamic>>> groupTestsByRoom(
    List<Map<String, dynamic>> tests,
  ) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var t in tests) {
      final tr = t['test_rooms'] as Map<String, dynamic>?;
      final rn = tr?['room_number'] ?? 'Unknown';
      grouped.putIfAbsent(rn, () => []).add(t);
    }
    return grouped;
  }

  List<Map<String, dynamic>> getPendingTestsForRoom(
    List<Map<String, dynamic>> tests,
    String roomNumber,
  ) {
    return tests.where((t) {
      final tr = t['test_rooms'] as Map<String, dynamic>?;
      return tr?['room_number'] == roomNumber && t['status'] == 'pending';
    }).toList();
  }

  Future<bool> completeAllTestsInRoom(
    List<Map<String, dynamic>> testsInRoom,
  ) async {
    try {
      for (var t in testsInRoom) {
        await updateTestStatus(appointmentTestId: t['id'], status: 'completed');
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  List<Map<String, String>> generateFallbackDirections({
    required String fromRoom,
    required String toRoom,
    required String fromFloor,
    required String toFloor,
  }) {
    if (fromFloor == toFloor) {
      return [
        {'step': '1', 'instruction': 'Exit $fromRoom'},
        {'step': '2', 'instruction': 'Follow corridor signs'},
        {'step': '3', 'instruction': 'Look for $toRoom'},
      ];
    }
    return [
      {'step': '1', 'instruction': 'Exit $fromRoom'},
      {'step': '2', 'instruction': 'Walk to elevator'},
      {'step': '3', 'instruction': 'Take elevator to $toFloor'},
      {'step': '4', 'instruction': 'Exit elevator'},
      {'step': '5', 'instruction': 'Follow signs to $toRoom'},
    ];
  }
}
