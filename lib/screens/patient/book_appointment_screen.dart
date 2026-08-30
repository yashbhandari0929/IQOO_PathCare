// lib/screens/patient/book_appointment_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/cart_service.dart';
import '../../services/booking_service.dart';

final supabase = Supabase.instance.client;

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({Key? key}) : super(key: key);

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final BookingService _bookingService = BookingService();
  final TextEditingController _instructionsController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  String? _selectedTimeSlot;
  List<String> _availableTimeSlots = [];
  bool _isLoadingSlots = false;
  bool _isBooking = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableSlots();
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableSlots() async {
    setState(() => _isLoadingSlots = true);

    final cartService = Provider.of<CartService>(context, listen: false);
    final testIds = cartService.getAllItemIds();

    if (testIds.isEmpty) {
      setState(() => _isLoadingSlots = false);
      return;
    }

    try {
      final slots = await _bookingService.getAvailableTimeSlots(
        testIds: testIds,
        date: _selectedDate,
      );

      // ── Filter out past / too-soon slots ─────────────────────────────────
      // Rule: only show slots that start at least 30 minutes from NOW.
      // This applies only when the selected date is TODAY.
      // For future dates, all returned slots are shown as-is.
      final now = DateTime.now();
      final isToday =
          _selectedDate.year == now.year &&
          _selectedDate.month == now.month &&
          _selectedDate.day == now.day;

      final cutoff = now.add(const Duration(minutes: 30));

      final filtered = slots.where((slot) {
        if (!isToday) return true; // future date — show everything

        // Parse slot time (format "HH:mm:ss")
        final parts = slot.split(':');
        if (parts.length < 2) return true;

        final slotHour = int.tryParse(parts[0]) ?? 0;
        final slotMinute = int.tryParse(parts[1]) ?? 0;

        // Build a DateTime for this slot on today's date
        final slotDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          slotHour,
          slotMinute,
        );

        // Only include if slot starts 30+ minutes from now
        return slotDateTime.isAfter(cutoff);
      }).toList();
      // ─────────────────────────────────────────────────────────────────────

      setState(() {
        _availableTimeSlots = filtered;
        _selectedTimeSlot = null;
        _isLoadingSlots = false;
      });
    } catch (e) {
      setState(() => _isLoadingSlots = false);
    }
  }

  String _formatTimeSlot(String timeSlot) {
    final parts = timeSlot.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }

  Future<void> _bookAppointment() async {
    if (_selectedTimeSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a time slot'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isBooking = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Get patient ID
      final patientData = await supabase
          .from('patients')
          .select('id')
          .eq('auth_id', userId)
          .single();

      final patientId = patientData['id'] as String;

      final cartService = Provider.of<CartService>(context, listen: false);
      final testIds = cartService.getTestIds();

      // Expand package tests
      final packageIds = cartService.getPackageIds();
      for (var packageId in packageIds) {
        final packageTests = await supabase
            .from('health_package_tests')
            .select('test_id')
            .eq('package_id', packageId);

        for (var test in packageTests) {
          testIds.add(test['test_id'] as String);
        }
      }

      // Book appointment
      final result = await _bookingService.bookAppointment(
        patientId: patientId,
        testIds: testIds,
        date: _selectedDate,
        startTime: _selectedTimeSlot!,
        specialInstructions: _instructionsController.text.trim().isEmpty
            ? null
            : _instructionsController.text.trim(),
      );

      setState(() => _isBooking = false);

      if (result['success'] == true) {
        // Clear cart
        await cartService.clearCart();

        // Show success dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 32),
                SizedBox(width: 12),
                Text('Booking Confirmed!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your appointment has been booked successfully.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appointment Details:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                      ),
                      Text('Time: ${_formatTimeSlot(_selectedTimeSlot!)}'),
                      Text('Tests: ${testIds.length}'),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Go back to home
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: Text('Done'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Booking failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _isBooking = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartService = Provider.of<CartService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Book Appointment'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: cartService.itemCount == 0
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Your cart is empty',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Add Tests'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cart Summary
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Tests',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        ...cartService.items.map(
                          (item) => Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(child: Text(item.name)),
                                Text(
                                  '₹${item.price.toStringAsFixed(0)}',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '₹${cartService.totalPrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),

                  // Date Selection
                  Text(
                    'Select Date',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TableCalendar(
                      firstDay: DateTime.now(),
                      lastDay: DateTime.now().add(Duration(days: 90)),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDate, day),
                      onDaySelected: (selectedDay, focusedDay) {
                        if (!isSameDay(_selectedDate, selectedDay)) {
                          setState(() {
                            _selectedDate = selectedDay;
                            _focusedDay = focusedDay;
                          });
                          _loadAvailableSlots();
                        }
                      },
                      calendarStyle: CalendarStyle(
                        selectedDecoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        todayDecoration: BoxDecoration(
                          color: Colors.blue.shade200,
                          shape: BoxShape.circle,
                        ),
                      ),
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Time Slot Selection
                  Text(
                    'Select Time',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),

                  if (_isLoadingSlots)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_availableTimeSlots.isEmpty)
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No available slots for this date. Please select another date.',
                              style: TextStyle(color: Colors.orange.shade900),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableTimeSlots.map((slot) {
                        final isSelected = _selectedTimeSlot == slot;
                        return ChoiceChip(
                          label: Text(_formatTimeSlot(slot)),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedTimeSlot = selected ? slot : null;
                            });
                          },
                          selectedColor: Colors.blue,
                          backgroundColor: Colors.grey[200],
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                  SizedBox(height: 24),

                  // Special Instructions
                  Text(
                    'Special Instructions (Optional)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: _instructionsController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Any special requirements or notes...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  SizedBox(height: 80),
                ],
              ),
            ),
      bottomNavigationBar: cartService.itemCount == 0
          ? null
          : Container(
              padding: EdgeInsets.all(16),
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
              child: SafeArea(
                child: ElevatedButton(
                  onPressed: _isBooking ? null : _bookAppointment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isBooking
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Confirm Booking',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
    );
  }
}
