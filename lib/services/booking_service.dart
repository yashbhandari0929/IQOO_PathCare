// lib/services/booking_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class BookingService {

  // ============================================================
  // FAST: Fetch everything in ONE query, calculate locally
  // Old approach: 100+ DB calls. New approach: 3 DB calls total.
  // ============================================================
  Future<List<String>> getAvailableTimeSlots({
    required List<String> testIds,
    required DateTime date,
  }) async {
    try {
      final dateStr = date.toIso8601String().split('T')[0];

      // STEP 1: Get test details (1 DB call)
      final testsData = await supabase
          .from('tests')
          .select('id, name, room_number, avg_duration_minutes')
          .inFilter('id', testIds);

      final List<Map<String, dynamic>> tests =
      List<Map<String, dynamic>>.from(testsData);

      if (tests.isEmpty) return [];

      // STEP 2: Get ALL booked slots for this date in ONE call
      final bookedSlotsRaw = await supabase
          .from('test_time_slots')
          .select('room_id, start_time, end_time, slot_number')
          .eq('appointment_date', dateStr)
          .eq('is_booked', true);

      final List<Map<String, dynamic>> bookedSlots =
      List<Map<String, dynamic>>.from(bookedSlotsRaw);

      // STEP 3: Get room capacities in ONE call
      final roomNumbers = tests
          .map((t) => t['room_number'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final roomsData = await supabase
          .from('test_rooms')
          .select('id, room_number, capacity')
          .inFilter('room_number', roomNumbers);

      final List<Map<String, dynamic>> rooms =
      List<Map<String, dynamic>>.from(roomsData);

      // Build room lookup maps locally (no more DB calls)
      final Map<String, int> roomCapacity = {};
      final Map<String, String> roomIdMap = {};

      for (var room in rooms) {
        final rn = room['room_number'] as String;
        roomCapacity[rn] = room['capacity'] as int;
        roomIdMap[rn]    = room['id'] as String;
      }

      // Build booked count map locally: "roomId_startTime" -> count
      final Map<String, int> bookedCountMap = {};
      for (var slot in bookedSlots) {
        final roomId    = slot['room_id']    as String?;
        final startTime = slot['start_time'] as String?;
        if (roomId != null && startTime != null) {
          final key = '${roomId}_${_normalizeTime(startTime)}';
          bookedCountMap[key] = (bookedCountMap[key] ?? 0) + 1;
        }
      }

      // Calculate total duration needed
      int totalDurationMinutes = 0;
      for (var test in tests) {
        totalDurationMinutes += (test['avg_duration_minutes'] as int? ?? 15);
      }

      // Generate all possible time slots 9 AM → 9:30 PM every 15 min
      final List<String> availableSlots = [];
      final DateTime lastSlotStart = DateTime(2000, 1, 1, 21, 30, 0);

      for (int hour = 9; hour < 22; hour++) {
        for (int minute = 0; minute < 60; minute += 15) {
          final slotStart = DateTime(2000, 1, 1, hour, minute, 0);

          // Cut off any slot that STARTS after 9:30 PM
          if (slotStart.isAfter(lastSlotStart)) continue;

          final bool slotAvailable = _checkAvailabilityLocally(
            tests: tests,
            slotStart: slotStart,
            roomCapacity: roomCapacity,
            roomIdMap: roomIdMap,
            bookedCountMap: bookedCountMap,
          );

          if (slotAvailable) {
            final timeStr =
                '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00';
            availableSlots.add(timeStr);
          }
        }
      }

      print(
          '✅ Found ${availableSlots.length} available slots (3 DB calls total)');
      return availableSlots;
    } catch (e) {
      print('❌ Error getting available slots: $e');
      return [];
    }
  }

  bool _checkAvailabilityLocally({
    required List<Map<String, dynamic>> tests,
    required DateTime slotStart,
    required Map<String, int> roomCapacity,
    required Map<String, String> roomIdMap,
    required Map<String, int> bookedCountMap,
  }) {
    DateTime currentTime = slotStart;

    for (var test in tests) {
      final duration   = test['avg_duration_minutes'] as int? ?? 15;
      final roomNumber = test['room_number'] as String?;

      if (roomNumber != null) {
        final roomId  = roomIdMap[roomNumber];
        final capacity = roomCapacity[roomNumber] ?? 1;

        if (roomId != null) {
          final timeStr =
              '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}:00';
          final key        = '${roomId}_$timeStr';
          final bookedCount = bookedCountMap[key] ?? 0;

          if (bookedCount >= capacity) return false;
        }
      }

      currentTime = currentTime.add(Duration(minutes: duration));
    }

    return true;
  }

  String _normalizeTime(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:00';
    }
    return timeStr;
  }

  // ============================================================
  // Check slot availability (validation at booking time)
  // ============================================================
  Future<Map<String, dynamic>> checkSlotAvailability({
    required List<String> testIds,
    required DateTime date,
    required String startTime,
  }) async {
    try {
      final dateStr = date.toIso8601String().split('T')[0];

      final testsData = await supabase
          .from('tests')
          .select('id, name, room_number, avg_duration_minutes')
          .inFilter('id', testIds);

      final List<Map<String, dynamic>> tests =
      List<Map<String, dynamic>>.from(testsData);

      DateTime currentTime = DateTime.parse('2000-01-01 $startTime');
      List<Map<String, dynamic>> allocations = [];

      for (var test in tests) {
        final duration = test['avg_duration_minutes'] as int? ?? 15;
        final endTime  = currentTime.add(Duration(minutes: duration));

        allocations.add({
          'test_id':     test['id'],
          'test_name':   test['name'],
          'room_number': test['room_number'],
          'start_time':
          '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}:00',
          'end_time':
          '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00',
          'duration': duration,
        });

        currentTime = endTime;
      }

      for (var allocation in allocations) {
        final roomNumber = allocation['room_number'];

        if (roomNumber != null) {
          final roomData = await supabase
              .from('test_rooms')
              .select('capacity')
              .eq('room_number', roomNumber)
              .maybeSingle();

          if (roomData != null) {
            final capacity = roomData['capacity'] as int;

            final existingBookings = await supabase
                .from('test_time_slots')
                .select('slot_number')
                .eq('appointment_date', dateStr)
                .eq('start_time', allocation['start_time'])
                .eq('is_booked', true)
                .count();

            if (existingBookings.count >= capacity) {
              return {
                'available': false,
                'message':
                'Room $roomNumber is full at ${allocation['start_time']}',
                'conflict_test': allocation['test_name'],
              };
            }
          }
        }
      }

      return {
        'available': true,
        'allocations': allocations,
        'total_duration': allocations.fold<int>(
          0,
              (sum, item) => sum + (item['duration'] as int),
        ),
      };
    } catch (e) {
      print('❌ Error checking availability: $e');
      return {
        'available': false,
        'message': 'Error checking availability: $e',
      };
    }
  }

  // ============================================================
  // Book appointment
  // ============================================================
  Future<Map<String, dynamic>> bookAppointment({
    required String patientId,
    required List<String> testIds,
    required DateTime date,
    required String startTime,
    String? specialInstructions,
  }) async {
    try {
      print('📅 Booking appointment for $patientId');

      final availabilityCheck = await checkSlotAvailability(
        testIds: testIds,
        date: date,
        startTime: startTime,
      );

      if (availabilityCheck['available'] != true) {
        return {
          'success': false,
          'message': availabilityCheck['message'] ?? 'Time slot not available',
        };
      }

      final appointmentData = await supabase
          .from('appointments')
          .insert({
        'patient_id':           patientId,
        'appointment_date':     date.toIso8601String().split('T')[0],
        'appointment_time':     startTime,
        'status':               'scheduled',
        'special_instructions': specialInstructions,
      })
          .select()
          .single();

      final appointmentId = appointmentData['id'] as String;
      print('✅ Appointment created: $appointmentId');

      final allocations = availabilityCheck['allocations'] as List;

      for (var i = 0; i < allocations.length; i++) {
        final allocation = allocations[i];

        final roomData = await supabase
            .from('test_rooms')
            .select('id, capacity')
            .eq('room_number', allocation['room_number'])
            .maybeSingle();

        if (roomData != null) {
          final existingSlots = await supabase
              .from('test_time_slots')
              .select('slot_number')
              .eq('appointment_date', date.toIso8601String().split('T')[0])
              .eq('start_time', allocation['start_time'])
              .eq('room_id', roomData['id'])
              .order('slot_number', ascending: false)
              .limit(1);

          int nextSlotNumber = 1;
          if (existingSlots.isNotEmpty) {
            nextSlotNumber = (existingSlots[0]['slot_number'] as int) + 1;
          }

          await supabase.from('test_time_slots').insert({
            'test_id':                   allocation['test_id'],
            'room_id':                   roomData['id'],
            'appointment_date':          date.toIso8601String().split('T')[0],
            'start_time':                allocation['start_time'],
            'end_time':                  allocation['end_time'],
            'slot_number':               nextSlotNumber,
            'is_booked':                 true,
            'booked_by_appointment_id':  appointmentId,
            'booked_by_patient_id':      patientId,
          });

          await supabase.from('appointment_tests').insert({
            'appointment_id':   appointmentId,
            'test_id':          allocation['test_id'],
            'test_name':        allocation['test_name'],
            'test_order':       i + 1,
            'assigned_room_id': roomData['id'],
            'scheduled_time':   allocation['start_time'],
            'status':           'pending',
          });
        }
      }

      print('✅ All time slots booked successfully');

      return {
        'success': true,
        'appointment_id': appointmentId,
        'allocations': allocations,
      };
    } catch (e) {
      print('❌ Error booking appointment: $e');
      return {
        'success': false,
        'message': 'Error booking appointment: $e',
      };
    }
  }

  // ============================================================
  // Get appointments for a patient
  // ── FIX: returns ALL statuses (pending + reached + completed)
  //    so that a test marked completed in the navigation screen
  //    immediately shows up correctly in the appointments list.
  //    The status field on each appointment_test row is the
  //    source of truth — we never filter it out here.
  // ============================================================
  Future<List<Map<String, dynamic>>> getPatientAppointments({
    required String patientId,
    String? status,           // filters the APPOINTMENT status, not test status
  }) async {
    try {
      var query = supabase
          .from('appointments')
          .select(
        // Select ALL appointment_test rows regardless of their status.
        // Do NOT add .eq('status','pending') on appointment_tests here —
        // that was hiding completed tests from the list.
        '*, appointment_tests('
            '  id, test_id, test_name, test_order, status,'
            '  scheduled_time, reached_at, completed_at,'
            '  assigned_room_id,'
            '  test_rooms!appointment_tests_assigned_room_id_fkey('
            '    id, room_number, floor'
            '  )'
            ')',
      )
          .eq('patient_id', patientId);

      // Filter by APPOINTMENT-level status if requested
      // (e.g. show only 'scheduled' appointments on home screen)
      if (status != null) {
        query = query.eq('status', status);
      }

      final appointments =
      await query.order('appointment_date', ascending: false);

      return List<Map<String, dynamic>>.from(appointments);
    } catch (e) {
      print('Error fetching appointments: $e');
      return [];
    }
  }

  // ============================================================
  // Cancel appointment
  // ============================================================
  Future<bool> cancelAppointment(String appointmentId) async {
    try {
      await supabase.from('appointments').update({
        'status':       'cancelled',
        'cancelled_at': DateTime.now().toIso8601String(),
      }).eq('id', appointmentId);

      await supabase.from('test_time_slots').update({
        'is_booked':                 false,
        'booked_by_appointment_id':  null,
        'booked_by_patient_id':      null,
      }).eq('booked_by_appointment_id', appointmentId);

      return true;
    } catch (e) {
      print('Error cancelling appointment: $e');
      return false;
    }
  }

  // ============================================================
  // Mark a test as completed
  // ============================================================
  Future<bool> completeTest({
    required String appointmentTestId,
    required String appointmentId,
  }) async {
    try {
      await supabase.from('appointment_tests').update({
        'status':       'completed',
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', appointmentTestId);

      print('✅ Test $appointmentTestId marked as completed');
      await checkAndCompleteAppointment(appointmentId);

      return true;
    } catch (e) {
      print('❌ Error completing test: $e');
      return false;
    }
  }

  // ============================================================
  // Auto-complete appointment when all tests are done
  // ── FIX: this is now also called by NavigationService when
  //    it marks a test completed via updateTestStatus().
  //    Previously it was only called via BookingService.completeTest()
  //    which the navigation screen never used.
  // ============================================================
  Future<void> checkAndCompleteAppointment(String appointmentId) async {
    try {
      final appointmentTests = await supabase
          .from('appointment_tests')
          .select('status')
          .eq('appointment_id', appointmentId);

      if (appointmentTests.isEmpty) return;

      final bool allCompleted =
      appointmentTests.every((test) => test['status'] == 'completed');

      if (allCompleted) {
        await supabase.from('appointments').update({
          'status':       'completed',
          'completed_at': DateTime.now().toIso8601String(),
        }).eq('id', appointmentId);

        print('✅ Appointment $appointmentId auto-completed!');
      } else {
        final completedCount = appointmentTests
            .where((test) => test['status'] == 'completed')
            .length;
        print(
            '📊 Progress: $completedCount/${appointmentTests.length} tests completed');
      }
    } catch (e) {
      print('❌ Error auto-completing appointment: $e');
    }
  }

  // ============================================================
  // Get appointment test details
  // ── FIX: no status filter — returns pending + reached + completed
  // ============================================================
  Future<List<Map<String, dynamic>>> getAppointmentTests({
    required String appointmentId,
  }) async {
    try {
      final tests = await supabase
          .from('appointment_tests')
          .select(
        '*, tests(*), '
            'test_rooms!appointment_tests_assigned_room_id_fkey(*)',
      )
          .eq('appointment_id', appointmentId)
          .order('test_order');

      return List<Map<String, dynamic>>.from(tests);
    } catch (e) {
      print('Error fetching appointment tests: $e');
      return [];
    }
  }

  // ============================================================
  // Update test status
  // ── This is the BookingService version (used from appointments
  //    screen). NavigationService has its own updateTestStatus.
  //    Both write to the same row — they are compatible.
  //    checkAndCompleteAppointment is called here so the parent
  //    appointment flips to 'completed' when the last test is done.
  // ============================================================
  Future<bool> updateTestStatus({
    required String appointmentTestId,
    required String appointmentId,
    required String status,
  }) async {
    try {
      final Map<String, dynamic> updateData = {'status': status};

      if (status == 'completed') {
        updateData['completed_at'] = DateTime.now().toIso8601String();
        updateData['completed_by_role'] = 'patient';
      } else if (status == 'in_progress' || status == 'reached') {
        updateData['reached_at'] = DateTime.now().toIso8601String();
      }

      await supabase
          .from('appointment_tests')
          .update(updateData)
          .eq('id', appointmentTestId);

      print('✅ Test status updated to: $status');

      // Always check if appointment should be auto-completed
      if (status == 'completed') {
        await checkAndCompleteAppointment(appointmentId);
      }

      return true;
    } catch (e) {
      print('❌ Error updating test status: $e');
      return false;
    }
  }

  // ============================================================
  // Called by NavigationService after it marks a test completed.
  // NavigationService doesn't have the appointmentId readily
  // available in all code paths, so it calls this helper with
  // just the appointmentTestId and we look up the appointmentId.
  // ============================================================
  Future<void> triggerCompletionCheckForTest(
      String appointmentTestId) async {
    try {
      final row = await supabase
          .from('appointment_tests')
          .select('appointment_id, status')
          .eq('id', appointmentTestId)
          .single();

      final apptId = row['appointment_id'] as String?;
      final status = row['status'] as String?;

      if (apptId != null && status == 'completed') {
        await checkAndCompleteAppointment(apptId);
      }
    } catch (e) {
      print('❌ Error in triggerCompletionCheckForTest: $e');
    }
  }
}