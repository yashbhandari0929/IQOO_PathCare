// lib/models/test.dart
class Test {
  final String id;
  final String categoryId;
  final String name;
  final String description;
  final double price;
  final int avgDurationMinutes;
  final String? roomNumber;
  final String? floor;
  final String? department;
  final int floorOrder;

  Test({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.price,
    required this.avgDurationMinutes,
    this.roomNumber,
    this.floor,
    this.department,
    required this.floorOrder,
  });

  factory Test.fromJson(Map<String, dynamic> json) {
    return Test(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      avgDurationMinutes: json['avg_duration_minutes'] as int? ?? 15,
      roomNumber: json['room_number'] as String?,
      floor: json['floor'] as String?,
      department: json['department'] as String?,
      floorOrder: json['floor_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'name': name,
      'description': description,
      'price': price,
      'avg_duration_minutes': avgDurationMinutes,
      'room_number': roomNumber,
      'floor': floor,
      'department': department,
      'floor_order': floorOrder,
    };
  }
}