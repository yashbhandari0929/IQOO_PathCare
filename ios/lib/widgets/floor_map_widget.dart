// lib/widgets/floor_map_widget.dart
import 'package:flutter/material.dart';

class FloorMapWidget extends StatelessWidget {
  final String floor;
  final String? highlightRoom;
  final List<String>? pathRooms;

  const FloorMapWidget({
    Key? key,
    required this.floor,
    this.highlightRoom,
    this.pathRooms,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 400,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: CustomPaint(
        painter: _FloorMapPainter(
          floor: floor,
          highlightRoom: highlightRoom,
          pathRooms: pathRooms ?? [],
        ),
        child: Container(),
      ),
    );
  }
}

class _FloorMapPainter extends CustomPainter {
  final String floor;
  final String? highlightRoom;
  final List<String> pathRooms;

  _FloorMapPainter({
    required this.floor,
    this.highlightRoom,
    required this.pathRooms,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (floor) {
      case 'Ground Floor':
        _paintGroundFloor(canvas, size);
        break;
      case '1st Floor':
        _paint1stFloor(canvas, size);
        break;
      case '2nd Floor':
        _paint2ndFloor(canvas, size);
        break;
    }
  }

  void _paintGroundFloor(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;

    // Paint styles
    final wallPaint = Paint()
      ..color = Colors.grey[800]!
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final pathPaint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;

    final highlightPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final roomPaint = Paint()
      ..color = Colors.blue[50]!
      ..style = PaintingStyle.fill;

    // Draw Main Entrance (top center)
    final entranceRect = Rect.fromLTWH(width * 0.4, 20, width * 0.2, 40);
    canvas.drawRect(entranceRect, roomPaint);
    canvas.drawRect(entranceRect, wallPaint);
    _drawText(canvas, 'Main\nEntrance', entranceRect.center, Colors.black, 10);

    // Draw Lobby (below entrance)
    final lobbyRect = Rect.fromLTWH(width * 0.35, 80, width * 0.3, 60);
    canvas.drawRect(lobbyRect, roomPaint);
    canvas.drawRect(lobbyRect, wallPaint);
    _drawText(canvas, 'Lobby', lobbyRect.center, Colors.black, 12);

    // Draw Reception (center)
    final receptionRect = Rect.fromLTWH(width * 0.4, 160, width * 0.2, 40);
    canvas.drawRect(receptionRect, roomPaint);
    canvas.drawRect(receptionRect, wallPaint);
    _drawText(canvas, 'Reception', receptionRect.center, Colors.black, 10);

    // Draw Lab A (left side)
    final labARect = Rect.fromLTWH(50, 220, width * 0.25, 80);
    if (highlightRoom == 'Lab A') {
      canvas.drawRect(labARect, highlightPaint);
    }
    canvas.drawRect(labARect, roomPaint);
    canvas.drawRect(labARect, wallPaint);
    _drawText(
      canvas,
      'Lab A\n🔬\nPathology',
      labARect.center,
      Colors.black,
      12,
    );

    // Draw Lab B (right side)
    final labBRect = Rect.fromLTWH(
      width - 50 - width * 0.25,
      220,
      width * 0.25,
      80,
    );
    if (highlightRoom == 'Lab B') {
      canvas.drawRect(labBRect, highlightPaint);
    }
    canvas.drawRect(labBRect, roomPaint);
    canvas.drawRect(labBRect, wallPaint);
    _drawText(
      canvas,
      'Lab B\n🔬\nPathology',
      labBRect.center,
      Colors.black,
      12,
    );

    // Draw Elevator (bottom center)
    final elevatorRect = Rect.fromLTWH(width * 0.42, 320, width * 0.16, 50);
    if (highlightRoom == 'Elevator') {
      canvas.drawRect(elevatorRect, highlightPaint);
    }
    canvas.drawRect(elevatorRect, roomPaint);
    canvas.drawRect(elevatorRect, wallPaint);
    _drawText(canvas, 'Elevator\n🛗', elevatorRect.center, Colors.black, 11);

    // Draw paths if needed
    if (pathRooms.contains('Main Entrance') && pathRooms.contains('Lab A')) {
      canvas.drawLine(
        Offset(width * 0.5, 60),
        Offset(width * 0.5, 140),
        pathPaint,
      );
      canvas.drawLine(
        Offset(width * 0.5, 140),
        Offset(labARect.center.dx, 180),
        pathPaint,
      );
      canvas.drawLine(
        Offset(labARect.center.dx, 180),
        Offset(labARect.center.dx, 220),
        pathPaint,
      );
    }

    if (pathRooms.contains('Lab A') && pathRooms.contains('Elevator')) {
      canvas.drawLine(
        Offset(labARect.center.dx, 300),
        Offset(elevatorRect.center.dx, 320),
        pathPaint,
      );
    }
  }

  void _paint1stFloor(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;

    final wallPaint = Paint()
      ..color = Colors.grey[800]!
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final roomPaint = Paint()
      ..color = Colors.blue[50]!
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Draw Elevator (top center)
    final elevatorRect = Rect.fromLTWH(width * 0.42, 20, width * 0.16, 50);
    if (highlightRoom == 'Elevator') {
      canvas.drawRect(elevatorRect, highlightPaint);
    }
    canvas.drawRect(elevatorRect, roomPaint);
    canvas.drawRect(elevatorRect, wallPaint);
    _drawText(canvas, 'Elevator\n🛗', elevatorRect.center, Colors.black, 11);

    // Draw Corridor
    final corridorRect = Rect.fromLTWH(width * 0.4, 90, width * 0.2, 40);
    canvas.drawRect(corridorRect, roomPaint);
    canvas.drawRect(corridorRect, wallPaint);
    _drawText(canvas, 'Corridor', corridorRect.center, Colors.black, 10);

    // LEFT SIDE ROOMS
    final room105 = Rect.fromLTWH(50, 150, width * 0.22, 60);
    _drawRoom(
      canvas,
      room105,
      'Room 105\n❤️ ECG',
      highlightRoom == 'Room 105',
      roomPaint,
      wallPaint,
      highlightPaint,
    );

    final room106 = Rect.fromLTWH(50, 220, width * 0.22, 60);
    _drawRoom(
      canvas,
      room106,
      'Room 106\n❤️ Echo',
      highlightRoom == 'Room 106',
      roomPaint,
      wallPaint,
      highlightPaint,
    );

    final room107 = Rect.fromLTWH(50, 290, width * 0.22, 60);
    _drawRoom(
      canvas,
      room107,
      'Room 107\n❤️ TMT',
      highlightRoom == 'Room 107',
      roomPaint,
      wallPaint,
      highlightPaint,
    );

    // RIGHT SIDE ROOMS
    final room110 = Rect.fromLTWH(
      width - 50 - width * 0.22,
      150,
      width * 0.22,
      60,
    );
    _drawRoom(
      canvas,
      room110,
      'Room 110\n👁️ Vision',
      highlightRoom == 'Room 110',
      roomPaint,
      wallPaint,
      highlightPaint,
    );

    final room111 = Rect.fromLTWH(
      width - 50 - width * 0.22,
      220,
      width * 0.22,
      60,
    );
    _drawRoom(
      canvas,
      room111,
      'Room 111\n👁️ Retinal',
      highlightRoom == 'Room 111',
      roomPaint,
      wallPaint,
      highlightPaint,
    );

    final room115 = Rect.fromLTWH(
      width - 50 - width * 0.22,
      290,
      width * 0.22,
      60,
    );
    _drawRoom(
      canvas,
      room115,
      'Room 115\n🧠 EEG',
      highlightRoom == 'Room 115',
      roomPaint,
      wallPaint,
      highlightPaint,
    );
  }

  void _paint2ndFloor(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;

    final wallPaint = Paint()
      ..color = Colors.grey[800]!
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final roomPaint = Paint()
      ..color = Colors.blue[50]!
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Draw Elevator (top center)
    final elevatorRect = Rect.fromLTWH(width * 0.42, 20, width * 0.16, 50);
    if (highlightRoom == 'Elevator') {
      canvas.drawRect(elevatorRect, highlightPaint);
    }
    canvas.drawRect(elevatorRect, roomPaint);
    canvas.drawRect(elevatorRect, wallPaint);
    _drawText(canvas, 'Elevator\n🛗', elevatorRect.center, Colors.black, 11);

    // Draw Corridor
    final corridorRect = Rect.fromLTWH(width * 0.4, 90, width * 0.2, 40);
    canvas.drawRect(corridorRect, roomPaint);
    canvas.drawRect(corridorRect, wallPaint);
    _drawText(canvas, 'Corridor', corridorRect.center, Colors.black, 10);

    // LEFT SIDE ROOMS
    final room201 = Rect.fromLTWH(50, 150, width * 0.22, 60);
    _drawRoom(
      canvas,
      room201,
      'Room 201\n📷 X-Ray',
      highlightRoom == 'Room 201',
      roomPaint,
      wallPaint,
      highlightPaint,
    );

    final room202 = Rect.fromLTWH(50, 220, width * 0.22, 60);
    _drawRoom(
      canvas,
      room202,
      'Room 202\n📷 CT Scan',
      highlightRoom == 'Room 202',
      roomPaint,
      wallPaint,
      highlightPaint,
    );

    final room203 = Rect.fromLTWH(50, 290, width * 0.22, 60);
    _drawRoom(
      canvas,
      room203,
      'Room 203\n📷 MRI',
      highlightRoom == 'Room 203',
      roomPaint,
      wallPaint,
      highlightPaint,
    );

    // RIGHT SIDE ROOMS
    final room204 = Rect.fromLTWH(
      width - 50 - width * 0.22,
      150,
      width * 0.22,
      60,
    );
    _drawRoom(
      canvas,
      room204,
      'Room 204\n📷 Ultrasound',
      highlightRoom == 'Room 204',
      roomPaint,
      wallPaint,
      highlightPaint,
    );

    final room205 = Rect.fromLTWH(
      width - 50 - width * 0.22,
      220,
      width * 0.22,
      60,
    );
    _drawRoom(
      canvas,
      room205,
      'Room 205\n📷 Mammogram',
      highlightRoom == 'Room 205',
      roomPaint,
      wallPaint,
      highlightPaint,
    );

    final room206 = Rect.fromLTWH(
      width - 50 - width * 0.22,
      290,
      width * 0.22,
      60,
    );
    _drawRoom(
      canvas,
      room206,
      'Room 206\n📷 DEXA',
      highlightRoom == 'Room 206',
      roomPaint,
      wallPaint,
      highlightPaint,
    );
  }

  void _drawRoom(
    Canvas canvas,
    Rect rect,
    String label,
    bool highlight,
    Paint roomPaint,
    Paint wallPaint,
    Paint highlightPaint,
  ) {
    if (highlight) {
      canvas.drawRect(rect, highlightPaint);
    }
    canvas.drawRect(rect, roomPaint);
    canvas.drawRect(rect, wallPaint);
    _drawText(canvas, label, rect.center, Colors.black, 10);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    Color color,
    double fontSize,
  ) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      position - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
