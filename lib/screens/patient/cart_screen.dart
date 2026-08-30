// lib/screens/patient/cart_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/cart_service.dart';
import 'book_appointment_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cart'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Consumer<CartService>(
        builder: (context, cartService, child) {
          if (cartService.itemCount == 0) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 100,
                    color: Colors.grey[300],
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Your cart is empty',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Add tests or packages to get started',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    child: Text('Browse Tests'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Cart Items List
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: cartService.items.length,
                  itemBuilder: (context, index) {
                    final item = cartService.items[index];
                    final isPackage = item.type == 'package';

                    return Container(
                      margin: EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Icon
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: isPackage
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isPackage ? Icons.card_giftcard : Icons.science,
                                color: isPackage ? Colors.green : Colors.blue,
                                size: 28,
                              ),
                            ),
                            SizedBox(width: 16),

                            // Item Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPackage
                                          ? Colors.green.withValues(alpha: 0.2)
                                          : Colors.blue.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isPackage ? 'Package' : 'Test',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isPackage
                                            ? Colors.green[700]
                                            : Colors.blue[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (item.description != null &&
                                      item.description!.isNotEmpty) ...[
                                    SizedBox(height: 4),
                                    Text(
                                      item.description!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Price & Remove
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹${item.price.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                SizedBox(height: 8),
                                IconButton(
                                  onPressed: () async {
                                    await cartService.removeItem(item.id);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('${item.name} removed'),
                                        backgroundColor: Colors.orange,
                                        behavior: SnackBarBehavior.floating,
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  icon: Icon(Icons.delete_outline),
                                  color: Colors.red,
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Bottom Summary & Checkout
              Container(
                padding: EdgeInsets.all(20),
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
                    children: [
                      // Summary
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Items:',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            '${cartService.itemCount}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Amount:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          Text(
                            '₹${cartService.totalPrice.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),

                      // Checkout Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => BookAppointmentScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Proceed to Book',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 12),

                      // Clear Cart Button
                      TextButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Clear Cart?'),
                              content: Text(
                                'Are you sure you want to remove all items?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(
                                    'Clear',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await cartService.clearCart();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Cart cleared'),
                                backgroundColor: Colors.orange,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: Text(
                          'Clear Cart',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
