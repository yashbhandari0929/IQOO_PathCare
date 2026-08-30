// lib/services/cart_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';

class CartService extends ChangeNotifier {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  List<CartItem> _items = [];

  List<CartItem> get items => _items;

  int get itemCount => _items.length;

  double get totalPrice {
    return _items.fold(0.0, (sum, item) => sum + item.price);
  }

  bool isInCart(String itemId) {
    return _items.any((item) => item.id == itemId);
  }

  // Load cart from persistent storage
  Future<void> loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cartData = prefs.getString('cart_items');

      if (cartData != null) {
        final List<dynamic> jsonList = json.decode(cartData);
        _items = jsonList.map((json) => CartItem.fromJson(json)).toList();
        notifyListeners();
      }
    } catch (e) {}
  }

  // Save cart to persistent storage
  Future<void> _saveCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String cartData = json.encode(
        _items.map((item) => item.toJson()).toList(),
      );
      await prefs.setString('cart_items', cartData);
    } catch (e) {}
  }

  // Add item to cart
  Future<void> addItem(CartItem item) async {
    // Check if already in cart
    if (!isInCart(item.id)) {
      _items.add(item);
      await _saveCart();
      notifyListeners();
    }
  }

  // Remove item from cart
  Future<void> removeItem(String itemId) async {
    _items.removeWhere((item) => item.id == itemId);
    await _saveCart();
    notifyListeners();
  }

  // Clear entire cart
  Future<void> clearCart() async {
    _items.clear();
    await _saveCart();
    notifyListeners();
  }

  // Get test IDs from cart (for booking)
  List<String> getTestIds() {
    return _items
        .where((item) => item.type == 'test')
        .map((item) => item.id)
        .toList();
  }

  // Get package IDs from cart (for booking)
  List<String> getPackageIds() {
    return _items
        .where((item) => item.type == 'package')
        .map((item) => item.id)
        .toList();
  }

  // Get all item IDs (both tests and packages)
  List<String> getAllItemIds() {
    return _items.map((item) => item.id).toList();
  }
}
