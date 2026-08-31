// lib/models/room_position.dart

class RoomPosition {
  final String roomId;
  final String roomNumber;
  final String floor;
  final String hotspotId;
  final double x; // Keep for 2D map
  final double y; // Keep for 2D map
  final String pathId; // Keep for 2D map
  final double x3d;
  final double y3d;
  final double z3d;

  RoomPosition({
    required this.roomId,
    required this.roomNumber,
    required this.floor,
    required this.hotspotId,
    required this.x,
    required this.y,
    this.pathId = '',
    required this.x3d,
    required this.y3d,
    required this.z3d,
  });
}

// Predefined 3D room positions matching the generated hospital.glb
class RoomPositions {
  static Map<String, RoomPosition> groundFloor = {
    'Main Entrance': RoomPosition(
      roomId: 'entrance',
      roomNumber: 'Main Entrance',
      floor: 'Ground Floor',
      hotspotId: 'anchor_entrance',
      x: 500, y: 100,
      x3d: -10, y3d: 4.5, z3d: 5,
    ),
    'Reception': RoomPosition(
      roomId: 'reception',
      roomNumber: 'Reception',
      floor: 'Ground Floor',
      hotspotId: 'anchor_reception',
      x: 500, y: 200,
      x3d: 0, y3d: 4.5, z3d: 5,
    ),
    'Lab A': RoomPosition(
      roomId: 'lab_a',
      roomNumber: 'Lab A',
      floor: 'Ground Floor',
      hotspotId: 'anchor_lab_a',
      x: 145, y: 340, pathId: 'path_entrance_to_lab_a',
      x3d: -10, y3d: 4.5, z3d: -10,
    ),
    'Lab B': RoomPosition(
      roomId: 'lab_b',
      roomNumber: 'Lab B',
      floor: 'Ground Floor',
      hotspotId: 'anchor_lab_b',
      x: 855, y: 340, pathId: 'path_entrance_to_lab_b',
      x3d: 10, y3d: 4.5, z3d: -10,
    ),
    'Elevator': RoomPosition(
      roomId: 'elevator_ground',
      roomNumber: 'Elevator',
      floor: 'Ground Floor',
      hotspotId: 'anchor_elevator',
      x: 500, y: 600,
      x3d: 0, y3d: 7.5, z3d: -2,
    ),
  };

  static Map<String, RoomPosition> firstFloor = {
    'Elevator': RoomPosition(
      roomId: 'elevator_first',
      roomNumber: 'Elevator',
      floor: '1st Floor',
      hotspotId: 'anchor_elevator',
      x: 500, y: 120,
      x3d: 0, y3d: 7.5, z3d: -2,
    ),
    'Room 105': RoomPosition(
      roomId: 'room_105', roomNumber: 'Room 105', floor: '1st Floor', hotspotId: '',
      x: 140, y: 230, pathId: 'path_elevator_to_room_105', x3d: 0, y3d: 0, z3d: 0,
    ),
    'Room 106': RoomPosition(
      roomId: 'room_106', roomNumber: 'Room 106', floor: '1st Floor', hotspotId: '',
      x: 140, y: 390, pathId: 'path_elevator_to_room_106', x3d: 0, y3d: 0, z3d: 0,
    ),
    'Room 107': RoomPosition(
      roomId: 'room_107', roomNumber: 'Room 107', floor: '1st Floor', hotspotId: '',
      x: 140, y: 550, pathId: 'path_elevator_to_room_107', x3d: 0, y3d: 0, z3d: 0,
    ),
    'Room 110': RoomPosition(
      roomId: 'room_110', roomNumber: 'Room 110', floor: '1st Floor', hotspotId: '',
      x: 860, y: 230, pathId: 'path_elevator_to_room_110', x3d: 0, y3d: 0, z3d: 0,
    ),
    'Room 111': RoomPosition(
      roomId: 'room_111', roomNumber: 'Room 111', floor: '1st Floor', hotspotId: '',
      x: 860, y: 390, pathId: 'path_elevator_to_room_111', x3d: 0, y3d: 0, z3d: 0,
    ),
    'Room 115': RoomPosition(
      roomId: 'room_115', roomNumber: 'Room 115', floor: '1st Floor', hotspotId: '',
      x: 860, y: 550, pathId: 'path_elevator_to_room_115', x3d: 0, y3d: 0, z3d: 0,
    ),
  };

  static Map<String, RoomPosition> secondFloor = {
    'Elevator': RoomPosition(
      roomId: 'elevator_second',
      roomNumber: 'Elevator',
      floor: '2nd Floor',
      hotspotId: 'anchor_elevator',
      x: 500, y: 120,
      x3d: 0, y3d: 7.5, z3d: -2,
    ),
    'Room 201': RoomPosition(
      roomId: 'room_201',
      roomNumber: 'Room 201',
      floor: '2nd Floor',
      hotspotId: 'anchor_201',
      x: 140, y: 230, pathId: 'path_elevator_to_room_201',
      x3d: -11, y3d: 10.5, z3d: -5,
    ),
    'Room 202': RoomPosition(
      roomId: 'room_202',
      roomNumber: 'Room 202',
      floor: '2nd Floor',
      hotspotId: 'anchor_202',
      x: 140, y: 390, pathId: 'path_elevator_to_room_202',
      x3d: -7, y3d: 10.5, z3d: -5,
    ),
    'Room 203': RoomPosition(
      roomId: 'room_203',
      roomNumber: 'Room 203',
      floor: '2nd Floor',
      hotspotId: 'anchor_203',
      x: 140, y: 550, pathId: 'path_elevator_to_room_203',
      x3d: -3, y3d: 10.5, z3d: -5,
    ),
    'Room 204': RoomPosition(
      roomId: 'room_204',
      roomNumber: 'Room 204',
      floor: '2nd Floor',
      hotspotId: 'anchor_204',
      x: 860, y: 230, pathId: 'path_elevator_to_room_204',
      x3d: 1, y3d: 10.5, z3d: -5,
    ),
    'Room 205': RoomPosition(
      roomId: 'room_205',
      roomNumber: 'Room 205',
      floor: '2nd Floor',
      hotspotId: 'anchor_205',
      x: 860, y: 390, pathId: 'path_elevator_to_room_205',
      x3d: 5, y3d: 10.5, z3d: -5,
    ),
    'Room 206': RoomPosition(
      roomId: 'room_206',
      roomNumber: 'Room 206',
      floor: '2nd Floor',
      hotspotId: 'anchor_206',
      x: 860, y: 550, pathId: 'path_elevator_to_room_206',
      x3d: 9, y3d: 10.5, z3d: -5,
    ),
  };

  static RoomPosition? getPosition(String roomNumber, String floor) {
    if (floor == 'Ground Floor') return groundFloor[roomNumber];
    if (floor == '1st Floor') return firstFloor[roomNumber];
    if (floor == '2nd Floor') return secondFloor[roomNumber];
    return null;
  }
  
  static Map<String, RoomPosition> getFloorPositions(String floor) {
    if (floor == 'Ground Floor') return groundFloor;
    if (floor == '1st Floor') return firstFloor;
    if (floor == '2nd Floor') return secondFloor;
    return {};
  }

  static List<RoomPosition> get allRooms {
    return [
      ...groundFloor.values, 
      ...firstFloor.values,
      ...secondFloor.values
    ].where((r) => r.hotspotId.isNotEmpty).toList();
  }
}
