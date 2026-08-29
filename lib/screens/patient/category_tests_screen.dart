// lib/screens/patient/category_tests_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/test_category.dart';
import '../../models/test.dart';
import '../../models/cart_item.dart';
import '../../services/cart_service.dart';
import 'cart_screen.dart';

final supabase = Supabase.instance.client;

class CategoryTestsScreen extends StatefulWidget {
  final TestCategory category;

  const CategoryTestsScreen({
    Key? key,
    required this.category,
  }) : super(key: key);

  @override
  State<CategoryTestsScreen> createState() => _CategoryTestsScreenState();
}

class _CategoryTestsScreenState extends State<CategoryTestsScreen> {
  List<Test> _tests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTests();
  }

  Future<void> _loadTests() async {
    setState(() => _isLoading = true);

    try {
      final testsData = await supabase
          .from('tests')
          .select()
          .eq('category_id', widget.category.id)
          .order('name');

      setState(() {
        _tests = (testsData as List).map((json) => Test.fromJson(json)).toList();
      });
    } catch (e) {
      print('Error loading tests: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading tests: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Color _getColorFromHex(String hexColor) {
    final hexCode = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$hexCode', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColorFromHex(widget.category.color);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _tests.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No tests available',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      )
          : Consumer<CartService>(
        builder: (context, cartService, child) {
          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: _tests.length,
            itemBuilder: (context, index) {
              final test = _tests[index];
              final isInCart = cartService.isInCart(test.id);

              return Container(
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 5,
                      offset: Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: isInCart
                        ? Colors.green.withOpacity(0.5)
                        : Colors.grey.withOpacity(0.2),
                    width: isInCart ? 2 : 1,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Checkbox/Check Icon
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isInCart
                              ? Colors.green
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isInCart
                              ? Icons.check
                              : Icons.add,
                          color: isInCart
                              ? Colors.white
                              : Colors.grey[600],
                        ),
                      ),
                      SizedBox(width: 16),

                      // Test Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              test.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                            if (test.description.isNotEmpty) ...[
                              SizedBox(height: 4),
                              Text(
                                test.description,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.grey[500],
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '~${test.avgDurationMinutes} min',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (test.roomNumber != null) ...[
                                  SizedBox(width: 12),
                                  Icon(
                                    Icons.location_on,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '${test.roomNumber}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Price & Add Button
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${test.price.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: isInCart
                                ? () async {
                              await cartService
                                  .removeItem(test.id);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${test.name} removed from cart'),
                                  backgroundColor: Colors.orange,
                                  behavior:
                                  SnackBarBehavior.floating,
                                  duration:
                                  Duration(seconds: 1),
                                ),
                              );
                            }
                                : () async {
                              await cartService.addItem(
                                CartItem.fromTest(test),
                              );
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${test.name} added to cart'),
                                  backgroundColor: Colors.green,
                                  behavior:
                                  SnackBarBehavior.floating,
                                  duration:
                                  Duration(seconds: 1),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isInCart
                                  ? Colors.orange
                                  : color,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              isInCart ? 'Remove' : 'Add',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: Consumer<CartService>(
        builder: (context, cartService, child) {
          if (cartService.itemCount == 0) return SizedBox.shrink();

          return Container(
            padding: EdgeInsets.all(16),
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
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${cartService.itemCount} items',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          '₹${cartService.totalPrice.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const CartScreen()),
                      ); // Go back to home
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      padding: EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'View Cart',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}