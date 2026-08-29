// lib/models/test_category.dart
class TestCategory {
  final String id;
  final String name;
  final String icon;
  final String color;
  final String description;
  final int displayOrder;

  TestCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
    required this.displayOrder,
  });

  factory TestCategory.fromJson(Map<String, dynamic> json) {
    return TestCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? '🔬',
      color: json['color'] as String? ?? '#2196F3',
      description: json['description'] as String? ?? '',
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'color': color,
      'description': description,
      'display_order': displayOrder,
    };
  }
}