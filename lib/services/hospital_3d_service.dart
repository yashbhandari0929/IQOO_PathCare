import 'package:supabase_flutter/supabase_flutter.dart';

class Hospital3DService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Watch for any changes in appointment_tests to broadcast room updates
  Stream<List<Map<String, dynamic>>> watchRoomUpdates() async* {
    // 1. Fetch room mappings statically
    final roomsRes = await _supabase.from('test_rooms').select('id, room_number, department, floor');
    final Map<String, Map<String, dynamic>> roomMap = {};
    for (final r in roomsRes as List) {
      roomMap[r['id'] as String] = r;
    }

    // 2. Stream all tests
    await for (final tests in _supabase.from('appointment_tests').stream(primaryKey: ['id'])) {
      final Map<String, Map<String, dynamic>> roomStats = {};

      // Initialize stats for all rooms
      for (final r in roomMap.values) {
        roomStats[r['room_number'] as String] = {
          'type': 'updateRoom',
          'room': r['room_number'],
          'department': r['department'],
          'waiting': 0,
          'inProgress': 0,
          'tests': <String>{},
        };
      }

      // Aggregate test data
      for (final test in tests) {
        final roomId = test['assigned_room_id'] as String?;
        final status = test['status'] as String? ?? '';
        final testName = test['test_name'] as String? ?? 'Unknown Test';
        
        if (roomId != null && roomMap.containsKey(roomId)) {
          final roomNumber = roomMap[roomId]!['room_number'] as String;
          final stats = roomStats[roomNumber]!;
          
          if (status == 'reached') {
            stats['waiting'] = (stats['waiting'] as int) + 1;
          } else if (status == 'in_progress') {
            stats['inProgress'] = (stats['inProgress'] as int) + 1;
          }
          
          // Add to today's tests if scheduled today (assuming all returned are today's tests for simplicity, or we can just list unique test types)
          (stats['tests'] as Set<String>).add(testName);
        }
      }

      // Convert Sets to Lists for JSON serialization
      final result = roomStats.values.map((stats) {
        return {
          ...stats,
          'tests': (stats['tests'] as Set<String>).toList(),
        };
      }).toList();

      yield result;
    }
  }

  // Get detailed information for the bottom sheet when a room is clicked
  Future<Map<String, dynamic>?> getRoomDetails(String roomNumber) async {
    try {
      // 1. Get room details
      final roomRes = await _supabase
          .from('test_rooms')
          .select('id, department, floor')
          .eq('room_number', roomNumber)
          .maybeSingle();

      if (roomRes == null) return null;
      final roomId = roomRes['id'] as String;

      // 2. Get today's tests for this room with patient details
      // Using rpc or direct query. We'll use direct query for simplicity and reliability
      final testsRes = await _supabase
          .from('appointment_tests')
          .select('''
            id,
            test_name,
            status,
            scheduled_time,
            completed_at,
            attended_by_doctor_id,
            appointments!inner(
              patient_id,
              patients(
                full_name
              )
            )
          ''')
          .eq('assigned_room_id', roomId)
          .order('scheduled_time', ascending: true);
          
      int waiting = 0;
      int inProgress = 0;
      int completed = 0;
      List<Map<String, dynamic>> queue = [];
      String? doctorId;

      for (var test in testsRes as List) {
        final status = test['status'] as String? ?? 'pending';
        if (status == 'reached') waiting++;
        else if (status == 'in_progress') {
          inProgress++;
          if (test['attended_by_doctor_id'] != null) {
            doctorId = test['attended_by_doctor_id'] as String;
          }
        }
        else if (status == 'completed') {
          completed++;
          if (test['attended_by_doctor_id'] != null) {
            doctorId = test['attended_by_doctor_id'] as String;
          }
        }
        
        final appointment = test['appointments'] as Map<String, dynamic>?;
        final patient = appointment?['patients'] as Map<String, dynamic>?;
        final patientName = patient?['full_name'] as String? ?? 'Unknown Patient';

        queue.add({
          'patientName': patientName,
          'testName': test['test_name'],
          'scheduledTime': test['scheduled_time'],
          'status': status,
        });
      }
      
      Map<String, dynamic>? doctorInfo;
      if (doctorId != null) {
        final docRes = await _supabase.from('doctors').select('full_name, email, is_available').eq('id', doctorId).maybeSingle();
        if (docRes != null) {
          doctorInfo = {
            'name': docRes['full_name'],
            'email': docRes['email'],
            'available': docRes['is_available'],
          };
        }
      }

      return {
        'roomNumber': roomNumber,
        'department': roomRes['department'],
        'floor': roomRes['floor'],
        'waiting': waiting,
        'inProgress': inProgress,
        'completed': completed,
        'avgDuration': '15 min',
        'doctor': doctorInfo,
        'queue': queue,
      };

    } catch (e) {
      print('Error fetching room details: $e');
      return null;
    }
  }
}
