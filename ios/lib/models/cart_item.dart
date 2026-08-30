// lib/models/cart_item.dart
class CartItem {
  final String id;
  final String name;
  final double price;
  final String type; // 'test' or 'package'
  final String? description;

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    required this.type,
    this.description,
  });

  factory CartItem.fromTest(dynamic test) {
    return CartItem(
      id: test.id,
      name: test.name,
      price: test.price,
      type: 'test',
      description: test.description,
    );
  }

  factory CartItem.fromPackage(dynamic package) {
    return CartItem(
      id: package.id,
      name: package.name,
      price: package.price,
      type: 'package',
      description: package.description,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'type': type,
      'description': description,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      type: json['type'] as String,
      description: json['description'] as String?,
    );
  }
}
