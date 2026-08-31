// lib/screens/doctor/room_selection_screen.dart

import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/doctor_service.dart';

class RoomSelectionScreen extends StatefulWidget {
  const RoomSelectionScreen({Key? key}) : super(key: key);

  @override
  State<RoomSelectionScreen> createState() => _RoomSelectionScreenState();
}

class _RoomSelectionScreenState extends State<RoomSelectionScreen> {
  final DoctorService _doctorService = DoctorService();

  List<Map<String, dynamic>> _allRooms = [];
  Map<String, List<Map<String, dynamic>>> _roomsByFloor = {};
  String _selectedFilter = 'All';
  bool _isLoading = true;
  StreamSubscription? _queueSubscription;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);

    try {
      final rooms = await _doctorService.getRoomStats();
      
      if (!mounted) return;
      
      setState(() {
        _allRooms = rooms;
        _roomsByFloor = _doctorService.groupRoomsByFloor(rooms);
        _isLoading = false;
      });

      _queueSubscription?.cancel();
      _queueSubscription = _doctorService.watchAllRoomsWaitCounts().listen((waitCounts) {
        if (!mounted) return;
        
        setState(() {
          for (var room in _allRooms) {
             final matchingCount = waitCounts.firstWhere(
                (wc) => wc['room_number'] == room['room_number'],
                orElse: () => <String, dynamic>{'waiting_count': 0},
             );
             
             final waitingCount = matchingCount['waiting_count'] as int? ?? 0;
             room['current_queue'] = waitingCount;
             room['estimated_wait_minutes'] = waitingCount * 15;
             
             if (waitingCount == 0) {
                 room['status'] = 'normal';
             } else if (waitingCount <= 2) {
                 room['status'] = 'busy';
             } else {
                 room['status'] = 'very_busy';
             }
          }
          _roomsByFloor = _doctorService.groupRoomsByFloor(_allRooms);
        });
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _getFilteredRooms() {
    if (_selectedFilter == 'All') {
      return _allRooms;
    } else {
      return _roomsByFloor[_selectedFilter] ?? [];
    }
  }

  void _selectRoom(Map<String, dynamic> room) {
    // Return the selected room to previous screen
    Navigator.pop(context, room);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Select Your Room'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Floor Filter
                _buildFloorFilter(),

                // Room List
                Expanded(
                  child: _getFilteredRooms().isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadRooms,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _getFilteredRooms().length,
                            itemBuilder: (context, index) {
                              final room = _getFilteredRooms()[index];
                              return _buildRoomCard(room);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFloorFilter() {
    final filters = ['All', 'Ground Floor', '1st Floor', '2nd Floor'];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((filter) {
            final isSelected = _selectedFilter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(filter),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
                backgroundColor: Colors.grey[200],
                selectedColor: Colors.blue,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    final roomNumber = room['room_number'] as String? ?? 'Unknown';
    final floor = room['floor'] as String? ?? 'Ground Floor';
    final department = room['department'] as String? ?? '';
    final queueCount = room['current_queue'] as int? ?? 0;
    final waitMinutes = room['estimated_wait_minutes'] as int? ?? 0;
    final status = room['status'] as String? ?? 'normal';
    final totalScheduled = room['total_scheduled'] as int? ?? 0;

    // Determine status color and text
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'normal':
        statusColor = Colors.green;
        statusText = 'Light';
        statusIcon = Icons.check_circle;
        break;
      case 'busy':
        statusColor = Colors.orange;
        statusText = 'Moderate';
        statusIcon = Icons.warning;
        break;
      case 'very_busy':
        statusColor = Colors.red;
        statusText = 'Busy';
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'Unknown';
        statusIcon = Icons.help;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _selectRoom(room),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Room Header
              Row(
                children: [
                  // Room Icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.local_hospital,
                      color: Colors.blue.shade700,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Room Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roomNumber,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              department,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                floor.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Arrow
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Queue Info
              Row(
                children: [
                  Expanded(
                    child: _buildInfoChip(
                      icon: Icons.people,
                      label: '$queueCount waiting',
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoChip(
                      icon: Icons.access_time,
                      label: '~${_doctorService.formatDuration(waitMinutes)}',
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoChip(
                      icon: statusIcon,
                      label: statusText,
                      color: statusColor,
                    ),
                  ),
                ],
              ),

              if (totalScheduled > queueCount) ...[
                const SizedBox(height: 8),
                Text(
                  '$totalScheduled total scheduled today',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
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
          Icon(
            Icons.local_hospital_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No rooms available',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try selecting a different floor',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
