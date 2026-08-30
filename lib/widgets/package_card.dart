// lib/widgets/package_card.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/health_package.dart';

final supabase = Supabase.instance.client;

class PackageCard extends StatelessWidget {
  final HealthPackage package;
  final int testCount;
  final bool isInCart;
  final VoidCallback onAddToCart;

  const PackageCard({
    Key? key,
    required this.package,
    required this.testCount,
    required this.isInCart,
    required this.onAddToCart,
  }) : super(key: key);

  Future<void> _showPackageDetails(BuildContext context) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    try {
      // Fetch test IDs for this package
      final packageTestsData = await supabase
          .from('health_package_tests')
          .select('test_id')
          .eq('package_id', package.id);

      List<String> testIds = (packageTestsData as List)
          .map((item) => item['test_id'] as String)
          .toList();

      // Fetch test details
      final testsData = await supabase
          .from('tests')
          .select('name, price, description')
          .inFilter('id', testIds)
          .order('name');

      // Close loading dialog
      Navigator.pop(context);

      // Show bottom sheet with test details
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green, Colors.green.shade400],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // Drag Handle
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white54,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.card_giftcard,
                          color: Colors.white,
                          size: 32,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                package.name,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '${testsData.length} tests included',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${package.price.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Test List
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: testsData.length,
                  itemBuilder: (context, index) {
                    final test = testsData[index];
                    return Container(
                      margin: EdgeInsets.only(bottom: 12),
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  test['name'] as String,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                if (test['description'] != null &&
                                    (test['description'] as String)
                                        .isNotEmpty) ...[
                                  SizedBox(height: 4),
                                  Text(
                                    test['description'] as String,
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
                          Text(
                            '₹${(test['price'] as num).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Bottom Action Button
              Container(
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
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isInCart
                          ? () => Navigator.pop(context)
                          : () {
                              Navigator.pop(context);
                              onAddToCart();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isInCart ? Colors.grey : Colors.green,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isInCart ? 'Already in Cart' : 'Add Package to Cart',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      // Close loading dialog
      Navigator.pop(context);

      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading package details: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPackageDetails(context),
      child: Container(
        margin: EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.blue.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Package Icon
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green, Colors.green.shade300],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.card_giftcard,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  SizedBox(width: 16),

                  // Package Name & Test Count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          package.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Tap to view $testCount tests',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Price
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${package.price.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              if (package.description.isNotEmpty) ...[
                SizedBox(height: 12),
                Text(
                  package.description,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              SizedBox(height: 12),

              // Add to Cart Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isInCart
                      ? null
                      : () {
                          // Prevent tap from propagating to GestureDetector
                          onAddToCart();
                        },
                  icon: Icon(
                    isInCart ? Icons.check : Icons.add_shopping_cart,
                    size: 18,
                  ),
                  label: Text(
                    isInCart ? 'Added to Cart' : 'Add to Cart',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isInCart ? Colors.grey : Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
