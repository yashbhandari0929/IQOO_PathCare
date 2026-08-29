// lib/models/room_position.dart

class RoomPosition {
  final String roomId;
  final String roomNumber;
  final String floor;
  final double x;
  final double y;
  final String pathId; // SVG path element ID

  RoomPosition({
    required this.roomId,
    required this.roomNumber,
    required this.floor,
    required this.x,
    required this.y,
    required this.pathId,
  });
}

// Predefined room positions matching SVG coordinates
class RoomPositions {
  // Ground Floor
  static Map<String, RoomPosition> groundFloor = {
    'Main Entrance': RoomPosition(
      roomId: 'entrance',
      roomNumber: 'Main Entrance',
      floor: 'Ground Floor',
      x: 500,
      y: 100,
      pathId: '',
    ),
    'Lab A': RoomPosition(
      roomId: 'lab_a',
      roomNumber: 'Lab A',
      floor: 'Ground Floor',
      x: 145,
      y: 340,
      pathId: 'path_entrance_to_lab_a',
    ),
    'Lab B': RoomPosition(
      roomId: 'lab_b',
      roomNumber: 'Lab B',
      floor: 'Ground Floor',
      x: 855,
      y: 340,
      pathId: 'path_entrance_to_lab_b',
    ),
    'Elevator': RoomPosition(
      roomId: 'elevator_ground',
      roomNumber: 'Elevator',
      floor: 'Ground Floor',
      x: 500,
      y: 600,
      pathId: '',
    ),
  };

  // First Floor
  static Map<String, RoomPosition> firstFloor = {
    'Elevator': RoomPosition(
      roomId: 'elevator_first',
      roomNumber: 'Elevator',
      floor: '1st Floor',
      x: 500,
      y: 120,
      pathId: '',
    ),
    'Room 105': RoomPosition(
      roomId: 'room_105',
      roomNumber: 'Room 105',
      floor: '1st Floor',
      x: 140,
      y: 230,
      pathId: 'path_elevator_to_room_105',
    ),
    'Room 106': RoomPosition(
      roomId: 'room_106',
      roomNumber: 'Room 106',
      floor: '1st Floor',
      x: 140,
      y: 390,
      pathId: 'path_elevator_to_room_106',
    ),
    'Room 107': RoomPosition(
      roomId: 'room_107',
      roomNumber: 'Room 107',
      floor: '1st Floor',
      x: 140,
      y: 550,
      pathId: 'path_elevator_to_room_107',
    ),
    'Room 110': RoomPosition(
      roomId: 'room_110',
      roomNumber: 'Room 110',
      floor: '1st Floor',
      x: 860,
      y: 230,
      pathId: 'path_elevator_to_room_110',
    ),
    'Room 111': RoomPosition(
      roomId: 'room_111',
      roomNumber: 'Room 111',
      floor: '1st Floor',
      x: 860,
      y: 390,
      pathId: 'path_elevator_to_room_111',
    ),
    'Room 115': RoomPosition(
      roomId: 'room_115',
      roomNumber: 'Room 115',
      floor: '1st Floor',
      x: 860,
      y: 550,
      pathId: 'path_elevator_to_room_115',
    ),
  };

  // Second Floor
  static Map<String, RoomPosition> secondFloor = {
    'Elevator': RoomPosition(
      roomId: 'elevator_second',
      roomNumber: 'Elevator',
      floor: '2nd Floor',
      x: 500,
      y: 120,
      pathId: '',
    ),
    'Room 201': RoomPosition(
      roomId: 'room_201',
      roomNumber: 'Room 201',
      floor: '2nd Floor',
      x: 140,
      y: 230,
      pathId: 'path_elevator_to_room_201',
    ),
    'Room 202': RoomPosition(
      roomId: 'room_202',
      roomNumber: 'Room 202',
      floor: '2nd Floor',
      x: 140,
      y: 390,
      pathId: 'path_elevator_to_room_202',
    ),
    'Room 203': RoomPosition(
      roomId: 'room_203',
      roomNumber: 'Room 203',
      floor: '2nd Floor',
      x: 140,
      y: 550,
      pathId: 'path_elevator_to_room_203',
    ),
    'Room 204': RoomPosition(
      roomId: 'room_204',
      roomNumber: 'Room 204',
      floor: '2nd Floor',
      x: 860,
      y: 230,
      pathId: 'path_elevator_to_room_204',
    ),
    'Room 205': RoomPosition(
      roomId: 'room_205',
      roomNumber: 'Room 205',
      floor: '2nd Floor',
      x: 860,
      y: 390,
      pathId: 'path_elevator_to_room_205',
    ),
    'Room 206': RoomPosition(
      roomId: 'room_206',
      roomNumber: 'Room 206',
      floor: '2nd Floor',
      x: 860,
      y: 550,
      pathId: 'path_elevator_to_room_206',
    ),
  };

  // Get position by room number and floor
  static RoomPosition? getPosition(String roomNumber, String floor) {
    switch (floor) {
      case 'Ground Floor':
        return groundFloor[roomNumber];
      case '1st Floor':
        return firstFloor[roomNumber];
      case '2nd Floor':
        return secondFloor[roomNumber];
      default:
        return null;
    }
  }

  // Get all positions for a floor
  static Map<String, RoomPosition> getFloorPositions(String floor) {
    switch (floor) {
      case 'Ground Floor':
        return groundFloor;
      case '1st Floor':
        return firstFloor;
      case '2nd Floor':
        return secondFloor;
      default:
        return {};
    }
  }
}