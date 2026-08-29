import 'package:flutter/material.dart';
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

class _HospitalNavigationScreenState extends State<HospitalNavigationScreen> {
  final NavigationService _navigationService = NavigationService();

  List<Map<String, dynamic>> _allTests = [];
  Map<String, dynamic>? _currentTest;
  List<PathSegment> _pathSegments = [];
  String _currentLocation = 'Main Entrance';
  String _selectedFloor = 'Ground Floor';
  bool _isLoading = true;
  bool _hasReachedDestination = false;

  // New: Track tests in current room
  List<Map<String, dynamic>> _testsInCurrentRoom = [];
  int _currentTestIndexInRoom = 0;
  bool _showingRoomTests = false;

  @override
  void initState() {
    super.initState();
    _loadNavigationData();
  }

  Future<void> _loadNavigationData() async {
    setState(() => _isLoading = true);

    try {
      print('🔄 Loading navigation data...');
      print('📍 Appointment ID: ${widget.appointmentId}');

      // ⚠️ CRITICAL: Force refresh from database
      final tests = await _navigationService.getOptimalTestSequence(widget.appointmentId);

      if (tests.isEmpty) {
        print('❌ No tests found');
        setState(() => _isLoading = false);
        return;
      }

      print('✅ Found ${tests.length} tests');

      // Debug: Show all test statuses
      print('📋 Test statuses:');
      for (int i = 0; i < tests.length; i++) {
        print('   ${i + 1}. ${tests[i]['test_name']} - ${tests[i]['status']}');
      }

      // Get current location based on completed tests
      final currentLoc = _navigationService.getCurrentLocation(tests);
      print('📍 Current location: $currentLoc');

      // Get next pending test
      final nextTest = _navigationService.getNextTest(tests);

      if (nextTest != null) {
        final testRooms = nextTest['test_rooms'] as Map<String, dynamic>?;
        final toRoom = testRooms?['room_number'] ?? 'Unknown';
        final toFloor = testRooms?['floor'] ?? 'Ground Floor';
        final fromFloor = _getFloorForLocation(currentLoc);

        print('🎯 Next test: ${nextTest['test_name']} in $toRoom');

        // Get path segments for navigation
        final segments = await _navigationService.getNavigationPathSegments(
          fromLocation: currentLoc,
          toLocation: toRoom,
          fromFloor: fromFloor,
          toFloor: toFloor,
        );

        print('🗺️ Path segments: ${segments.length}');

        // Check if there are multiple tests in the same room
        final testsInRoom = _navigationService.getPendingTestsForRoom(tests, toRoom);
        print('📋 Tests in $toRoom: ${testsInRoom.length}');

        setState(() {
          _allTests = tests;
          _currentTest = nextTest;
          _currentLocation = currentLoc;
          _pathSegments = segments;
          _selectedFloor = segments.isNotEmpty ? segments.first.floor : toFloor;
          _testsInCurrentRoom = testsInRoom;
          _currentTestIndexInRoom = 0;
          _showingRoomTests = testsInRoom.length > 1;
          _isLoading = false;
        });
      } else {
        print('✅ All tests completed or no pending tests');
        setState(() {
          _allTests = tests;
          _currentTest = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading navigation data: $e');
      setState(() => _isLoading = false);
    }
  }

  String _getFloorForLocation(String location) {
    if (location == 'Main Entrance' || location == 'Lab A' || location == 'Lab B' || location == 'Elevator') {
      return 'Ground Floor';
    } else if (location.startsWith('Room 1')) {
      return '1st Floor';
    } else if (location.startsWith('Room 2')) {
      return '2nd Floor';
    }
    return 'Ground Floor';
  }

  Future<void> _markAsReached() async {
    if (_currentTest == null) return;

    setState(() => _hasReachedDestination = true);

    final success = await _navigationService.updateTestStatus(
      appointmentTestId: _currentTest!['id'],
      status: 'reached',
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Location confirmed! You\'re in the queue.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _completeCurrentTest() async {
    if (_currentTest == null) {
      print('❌ Error: _currentTest is null');
      return;
    }

    print('🔄 Attempting to complete test: ${_currentTest!['id']}');
    print('   Test name: ${_currentTest!['test_name']}');

    try {
      final success = await _navigationService.updateTestStatus(
        appointmentTestId: _currentTest!['id'],
        status: 'completed',
      );

      print('   Update result: $success');

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error updating test status in database'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Check if there are more tests in this room
      if (_showingRoomTests && _currentTestIndexInRoom < _testsInCurrentRoom.length - 1) {
        // Move to next test in same room
        setState(() {
          _currentTestIndexInRoom++;
          _currentTest = _testsInCurrentRoom[_currentTestIndexInRoom];
          _hasReachedDestination = true; // Already in room
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Test completed! Next test in this room...'),
            backgroundColor: Colors.blue,
          ),
        );
      } else {
        // ⚠️ CRITICAL: Reload fresh data from database
        print('🔄 Loading next test from database...');

        // Show loading indicator
        setState(() => _isLoading = true);

        // Reload all data
        await _loadNavigationData();

        // Reset reached status for new location
        setState(() => _hasReachedDestination = false);

        if (mounted && _currentTest != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Test completed! Navigate to next location...'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (mounted && _currentTest == null) {
          // All tests completed
          _showCompletionDialog();
        }
      }
    } catch (e) {
      print('❌ Exception in _completeCurrentTest: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _completeAllTestsInRoom() async {
    if (_testsInCurrentRoom.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Complete All Tests?'),
        content: Text(
            'You have ${_testsInCurrentRoom.length} tests in this room.\n\n'
                'Complete all of them now?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Complete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(),
      ),
    );

    final success = await _navigationService.completeAllTestsInRoom(_testsInCurrentRoom);

    Navigator.pop(context); // Close loading

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error completing tests'), backgroundColor: Colors.red),
      );
      return;
    }

    // Reload navigation data
    await _loadNavigationData();

    // Check if all tests are done
    if (_currentTest == null) {
      _showCompletionDialog();
    } else {
      setState(() {
        _hasReachedDestination = false;
        _showingRoomTests = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ All tests in room completed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<bool> _checkIfAllCompleted() async {
    final tests = await _navigationService.getTestSequence(widget.appointmentId);
    return _navigationService.areAllTestsCompleted(tests);
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.celebration, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Expanded(child: Text('All Tests Complete!')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            SizedBox(height: 16),
            Text(
              'Congratulations! 🎉',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'You have completed all your tests.',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Icon(Icons.schedule, color: Colors.blue),
                  SizedBox(height: 8),
                  Text(
                    'Results will be available within 24-48 hours',
                    style: TextStyle(fontSize: 14, color: Colors.blue[900]),
                    textAlign: TextAlign.center,
                  ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text('Done', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Navigation'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentTest == null) {
      final allCompleted = _navigationService.areAllTestsCompleted(_allTests);

      return Scaffold(
        appBar: AppBar(
          title: Text('Navigation'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                allCompleted ? Icons.celebration : Icons.info_outline,
                size: 80,
                color: allCompleted ? Colors.green : Colors.grey,
              ),
              SizedBox(height: 20),
              Text(
                allCompleted ? 'All tests completed!' : 'No pending tests',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Back to Home'),
              ),
            ],
          ),
        ),
      );
    }

    final testRooms = _currentTest!['test_rooms'] as Map<String, dynamic>?;
    final testName = _currentTest!['test_name'] ?? 'Unknown Test';
    final roomNumber = testRooms?['room_number'] ?? 'Unknown';
    final floor = testRooms?['floor'] ?? 'Ground Floor';

    final progress = _navigationService.getProgress(_allTests);

    // Determine floors to show
    final availableFloors = _pathSegments.map((s) => s.floor).toSet().toList();
    if (!availableFloors.contains(_selectedFloor)) {
      availableFloors.add(_selectedFloor);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Navigation'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress Card
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.blue.shade100],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200, width: 2),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Text(
                          '${progress['completed']! + 1}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _showingRoomTests
                                  ? 'Test ${_currentTestIndexInRoom + 1} of ${_testsInCurrentRoom.length} in this room'
                                  : 'Test ${progress['completed']! + 1} of ${progress['total']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              testName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$roomNumber • $floor',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_showingRoomTests) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_testsInCurrentRoom.length} tests will be done in this room!',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[900],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 16),

            // Queue Status
            QueueStatusWidget(roomNumber: roomNumber),
            SizedBox(height: 24),

            // Floor Toggle
            if (availableFloors.length > 1) ...[
              Text(
                'Floor View',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: availableFloors.length,
                  itemBuilder: (context, index) {
                    final floorOption = availableFloors[index];
                    final isSelected = _selectedFloor == floorOption;

                    return Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(floorOption),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedFloor = floorOption);
                          }
                        },
                        selectedColor: Colors.blue,
                        backgroundColor: Colors.grey[200],
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 16),
            ],

            // Interactive Floor Map
            Text(
              'Hospital Map',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            InteractiveFloorMap(
              floor: _selectedFloor,
              currentLocation: _currentLocation,
              destination: roomNumber,
              pathSegments: _pathSegments,
            ),
            SizedBox(height: 24),

            // Directions
            Text(
              'Step-by-Step Directions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            ..._buildDirections(),

            SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  List<Widget> _buildDirections() {
    // Get room number safely
    String destinationRoom = 'Unknown';
    if (_currentTest != null) {
      final testRooms = _currentTest!['test_rooms'];
      if (testRooms != null && testRooms is Map<String, dynamic>) {
        destinationRoom = testRooms['room_number'] ?? 'Unknown';
      }
    }

    // Get directions for current selected floor
    final segment = _pathSegments.firstWhere(
          (s) => s.floor == _selectedFloor,
      orElse: () => _pathSegments.isNotEmpty ? _pathSegments.first : PathSegment(
        floor: _selectedFloor,
        pathId: '',
        fromLocation: _currentLocation,
        toLocation: destinationRoom,
      ),
    );

    final directions = _navigationService.generateFallbackDirections(
      fromRoom: segment.fromLocation,
      toRoom: segment.toLocation,
      fromFloor: segment.floor,
      toFloor: segment.floor,
    );

    return directions.map((direction) {
      return Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  direction['step']!,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                direction['instruction']!,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildBottomActions() {
    // Safely get room number
    String roomNumber = 'Destination';
    if (_currentTest != null) {
      final testRooms = _currentTest!['test_rooms'];
      if (testRooms != null && testRooms is Map<String, dynamic>) {
        roomNumber = testRooms['room_number'] ?? 'Destination';
      }
    }

    return Container(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasReachedDestination && _showingRoomTests && _testsInCurrentRoom.length > 1) ...[
              // Option to complete all tests in room
              ElevatedButton(
                onPressed: _completeAllTestsInRoom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.done_all),
                    SizedBox(width: 8),
                    Text(
                      'Complete All ${_testsInCurrentRoom.length} Tests in Room',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),
              Text(
                'or complete them one by one:',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              SizedBox(height: 8),
            ],
            _hasReachedDestination
                ? ElevatedButton(
              onPressed: _completeCurrentTest,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _showingRoomTests
                    ? 'Mark This Test as Completed (${_currentTestIndexInRoom + 1}/${_testsInCurrentRoom.length})'
                    : 'Mark Test as Completed',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            )
                : ElevatedButton(
              onPressed: _markAsReached,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                'I\'ve Reached $roomNumber',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}