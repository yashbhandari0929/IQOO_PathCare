// lib/models/health_package.dart
class HealthPackage {
  final String id;
  final String name;
  final String description;
  final double price;
  final List<String>? testIds; // Optional list of test IDs

  HealthPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.testIds,
  });

  factory HealthPackage.fromJson(Map<String, dynamic> json) {
    return HealthPackage(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      testIds: json['test_ids'] != null
          ? List<String>.from(json['test_ids'] as List)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'test_ids': testIds,
    };
  }
}
