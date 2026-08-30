// lib/services/booking_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class BookingService {
  // Check if a time slot is available for all tests
  Future<Map<String, dynamic>> checkSlotAvailability({
    required List<String> testIds,
    required DateTime date,
    required String startTime,
  }) async {
    try {
      print(
        '🔍 Checking availability for ${testIds.length} tests at $startTime',
      );

      // Get test details with room information
      final testsData = await supabase
          .from('tests')
          .select('id, name, room_number, avg_duration_minutes')
          .inFilter('id', testIds);

      List<Map<String, dynamic>> tests = List<Map<String, dynamic>>.from(
        testsData,
      );

      // Calculate time slots for each test
      DateTime currentTime = DateTime.parse('2000-01-01 $startTime');
      List<Map<String, dynamic>> allocations = [];

      for (var test in tests) {
        final duration = test['avg_duration_minutes'] as int? ?? 15;
        final endTime = currentTime.add(Duration(minutes: duration));

        allocations.add({
          'test_id': test['id'],
          'test_name': test['name'],
          'room_number': test['room_number'],
          'start_time':
              '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}:00',
          'end_time':
              '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00',
          'duration': duration,
        });

        currentTime = endTime;
      }

      // Check room capacity for each allocation
      for (var allocation in allocations) {
        final roomNumber = allocation['room_number'];

        if (roomNumber != null) {
          // Get room capacity
          final roomData = await supabase
              .from('test_rooms')
              .select('capacity')
              .eq('room_number', roomNumber)
              .maybeSingle();

          if (roomData != null) {
            final capacity = roomData['capacity'] as int;

            // Check existing bookings at this time
            final existingBookings = await supabase
                .from('test_time_slots')
                .select('slot_number')
                .eq('appointment_date', date.toIso8601String().split('T')[0])
                .eq('start_time', allocation['start_time'])
                .eq('is_booked', true)
                .count();

            final bookedCount = existingBookings.count;

            if (bookedCount >= capacity) {
              return {
                'available': false,
                'message':
                    'Room ${roomNumber} is full at ${allocation['start_time']}',
                'conflict_test': allocation['test_name'],
              };
            }
          }
        }
      }

      // All checks passed
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
      return {'available': false, 'message': 'Error checking availability: $e'};
    }
  }

  // Get available time slots for a date
  Future<List<String>> getAvailableTimeSlots({
    required List<String> testIds,
    required DateTime date,
  }) async {
    List<String> timeSlots = [];

    // Generate time slots from 9 AM to 5 PM (every 15 minutes)
    for (int hour = 9; hour < 17; hour++) {
      for (int minute = 0; minute < 60; minute += 15) {
        final timeStr =
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00';
        timeSlots.add(timeStr);
      }
    }

    List<String> availableSlots = [];

    for (var timeSlot in timeSlots) {
      final result = await checkSlotAvailability(
        testIds: testIds,
        date: date,
        startTime: timeSlot,
      );

      if (result['available'] == true) {
        availableSlots.add(timeSlot);
      }
    }

    return availableSlots;
  }

  // Book appointment with time slot allocation
  Future<Map<String, dynamic>> bookAppointment({
    required String patientId,
    required List<String> testIds,
    required DateTime date,
    required String startTime,
    String? specialInstructions,
  }) async {
    try {
      print('📅 Booking appointment for $patientId');

      // Check availability first
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

      // Create appointment
      final appointmentData = await supabase
          .from('appointments')
          .insert({
            'patient_id': patientId,
            'appointment_date': date.toIso8601String().split('T')[0],
            'appointment_time': startTime,
            'status': 'scheduled',
            'special_instructions': specialInstructions,
          })
          .select()
          .single();

      final appointmentId = appointmentData['id'] as String;
      print('✅ Appointment created: $appointmentId');

      // Create time slot bookings
      final allocations = availabilityCheck['allocations'] as List;

      for (var i = 0; i < allocations.length; i++) {
        final allocation = allocations[i];

        // Get room ID
        final roomData = await supabase
            .from('test_rooms')
            .select('id, capacity')
            .eq('room_number', allocation['room_number'])
            .maybeSingle();

        if (roomData != null) {
          // Get next available slot number
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

          // Create time slot booking
          await supabase.from('test_time_slots').insert({
            'test_id': allocation['test_id'],
            'room_id': roomData['id'],
            'appointment_date': date.toIso8601String().split('T')[0],
            'start_time': allocation['start_time'],
            'end_time': allocation['end_time'],
            'slot_number': nextSlotNumber,
            'is_booked': true,
            'booked_by_appointment_id': appointmentId,
            'booked_by_patient_id': patientId,
          });

          // Create appointment test record
          await supabase.from('appointment_tests').insert({
            'appointment_id': appointmentId,
            'test_id': allocation['test_id'],
            'test_name': allocation['test_name'],
            'test_order': i + 1,
            'assigned_room_id': roomData['id'],
            'scheduled_time': allocation['start_time'],
            'status': 'pending',
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
      return {'success': false, 'message': 'Error booking appointment: $e'};
    }
  }

  // Get appointments for a patient
  Future<List<Map<String, dynamic>>> getPatientAppointments({
    required String patientId,
    String? status,
  }) async {
    try {
      var query = supabase
          .from('appointments')
          .select(
            '*, appointment_tests!inner(*, test_rooms!appointment_tests_assigned_room_id_fkey(*))',
          )
          .eq('patient_id', patientId);

      if (status != null) {
        query = query.eq('status', status);
      }

      final appointments = await query.order(
        'appointment_date',
        ascending: false,
      );

      return List<Map<String, dynamic>>.from(appointments);
    } catch (e) {
      print('Error fetching appointments: $e');
      return [];
    }
  }

  // Cancel appointment
  Future<bool> cancelAppointment(String appointmentId) async {
    try {
      // Update appointment status
      await supabase
          .from('appointments')
          .update({
            'status': 'cancelled',
            'cancelled_at': DateTime.now().toIso8601String(),
          })
          .eq('id', appointmentId);

      // Release time slots
      await supabase
          .from('test_time_slots')
          .update({
            'is_booked': false,
            'booked_by_appointment_id': null,
            'booked_by_patient_id': null,
          })
          .eq('booked_by_appointment_id', appointmentId);

      return true;
    } catch (e) {
      print('Error cancelling appointment: $e');
      return false;
    }
  }

  // ==================== NEW FUNCTIONALITY ====================

  // Mark a test as completed
  Future<bool> completeTest({
    required String appointmentTestId,
    required String appointmentId,
  }) async {
    try {
      // Update the test status to completed
      await supabase
          .from('appointment_tests')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', appointmentTestId);

      print('✅ Test $appointmentTestId marked as completed');

      // Check if all tests are completed and auto-complete appointment
      await checkAndCompleteAppointment(appointmentId);

      return true;
    } catch (e) {
      print('❌ Error completing test: $e');
      return false;
    }
  }

  // Auto-complete appointment when all tests are done
  Future<void> checkAndCompleteAppointment(String appointmentId) async {
    try {
      // Get all tests for this appointment
      final appointmentTests = await supabase
          .from('appointment_tests')
          .select('status')
          .eq('appointment_id', appointmentId);

      if (appointmentTests.isEmpty) {
        print('⚠️ No tests found for appointment $appointmentId');
        return;
      }

      // Check if all tests are completed
      bool allCompleted = appointmentTests.every(
        (test) => test['status'] == 'completed',
      );

      if (allCompleted) {
        // Update appointment status to completed
        await supabase
            .from('appointments')
            .update({
              'status': 'completed',
              'completed_at': DateTime.now().toIso8601String(),
            })
            .eq('id', appointmentId);

        print('✅ Appointment $appointmentId auto-completed - all tests done!');
      } else {
        final completedCount = appointmentTests
            .where((test) => test['status'] == 'completed')
            .length;
        print(
          '📊 Progress: $completedCount/${appointmentTests.length} tests completed',
        );
      }
    } catch (e) {
      print('❌ Error auto-completing appointment: $e');
    }
  }

  // Get appointment test details
  Future<List<Map<String, dynamic>>> getAppointmentTests({
    required String appointmentId,
  }) async {
    try {
      final tests = await supabase
          .from('appointment_tests')
          .select(
            '*, tests(*), test_rooms!appointment_tests_assigned_room_id_fkey(*)',
          )
          .eq('appointment_id', appointmentId)
          .order('test_order');

      return List<Map<String, dynamic>>.from(tests);
    } catch (e) {
      print('Error fetching appointment tests: $e');
      return [];
    }
  }

  // Update test status (generic method for any status update)
  Future<bool> updateTestStatus({
    required String appointmentTestId,
    required String appointmentId,
    required String status,
  }) async {
    try {
      Map<String, dynamic> updateData = {'status': status};

      // Add timestamp based on status
      if (status == 'completed') {
        updateData['completed_at'] = DateTime.now().toIso8601String();
      } else if (status == 'in_progress') {
        updateData['reached_at'] = DateTime.now().toIso8601String();
      }

      await supabase
          .from('appointment_tests')
          .update(updateData)
          .eq('id', appointmentTestId);

      print('✅ Test status updated to: $status');

      // Auto-complete appointment if this was the last test
      if (status == 'completed') {
        await checkAndCompleteAppointment(appointmentId);
      }

      return true;
    } catch (e) {
      print('❌ Error updating test status: $e');
      return false;
    }
  }
}
