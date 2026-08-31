// lib/screens/patient/patient_home_screen.dart
/*import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/test_category.dart';
import '../../models/health_package.dart';
import '../../models/cart_item.dart';
import '../../services/cart_service.dart';
import '../../widgets/category_card.dart';
import '../../widgets/package_card.dart';
import 'category_tests_screen.dart';
import 'cart_screen.dart';
import 'patient_appointments_screen.dart';
import 'patient_profile_screen.dart';

final supabase = Supabase.instance.client;

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({Key? key}) : super(key: key);

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  int _currentIndex = 0;
  List<TestCategory> _categories = [];
  List<HealthPackage> _packages = [];
  Map<String, int> _testCounts = {}; // category_id -> test count
  Map<String, int> _packageTestCounts = {}; // package_id -> test count
  bool _isLoading = true;
  String _patientName = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPatientInfo();
  }

  Future<void> _loadPatientInfo() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final data = await supabase
            .from('patients')
            .select('full_name')
            .eq('auth_id', userId)
            .single();

        setState(() {
          _patientName = data['full_name'] as String;
        });
      }
    } catch (e) {
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load categories
      final categoriesData = await supabase
          .from('test_categories')
          .select()
          .order('display_order');

      _categories = (categoriesData as List)
          .map((json) => TestCategory.fromJson(json))
          .toList();

      // Load test counts for each category
      final testsData = await supabase.from('tests').select('category_id');

      Map<String, int> counts = {};
      for (var test in testsData as List) {
        final categoryId = test['category_id'] as String;
        counts[categoryId] = (counts[categoryId] ?? 0) + 1;
      }
      _testCounts = counts;

      // Load health packages
      final packagesData = await supabase
          .from('health_packages')
          .select()
          .order('price');

      _packages = (packagesData as List)
          .map((json) => HealthPackage.fromJson(json))
          .toList();

      // Load test counts for packages
      for (var package in _packages) {
        final packageTestsData = await supabase
            .from('health_package_tests')
            .select('test_id')
            .eq('package_id', package.id);

        _packageTestCounts[package.id] = (packageTestsData as List).length;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildHomeTab() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue, Colors.blue.shade300],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _patientName.isNotEmpty ? _patientName : 'Patient',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Test Categories Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Test Categories',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  '${_categories.length} categories',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Categories Grid (2 per row)
            GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final testCount = _testCounts[category.id] ?? 0;

                return CategoryCard(
                  category: category,
                  testCount: testCount,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CategoryTestsScreen(
                          category: category,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            SizedBox(height: 32),

            // Health Packages Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Health Packages',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  '${_packages.length} packages',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Packages List
            Consumer<CartService>(
              builder: (context, cartService, child) {
                return Column(
                  children: _packages.map((package) {
                    final testCount = _packageTestCounts[package.id] ?? 0;
                    final isInCart = cartService.isInCart(package.id);

                    return PackageCard(
                      package: package,
                      testCount: testCount,
                      isInCart: isInCart,
                      onAddToCart: () async {
                        await cartService.addItem(
                          CartItem.fromPackage(package),
                        );

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${package.name} added to cart'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _screens = [
      _buildHomeTab(),
      PatientAppointmentsScreen(),
      PatientProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? 'HealthCare'
              : _currentIndex == 1
              ? 'Appointments'
              : 'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_currentIndex == 0)
            Consumer<CartService>(
              builder: (context, cartService, child) {
                return Stack(
                  children: [
                    IconButton(
                      icon: Icon(Icons.shopping_cart),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CartScreen(),
                          ),
                        );
                      },
                    ),
                    if (cartService.itemCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '${cartService.itemCount}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
        },
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Appointments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}*/

/*
// lib/screens/patient/patient_home_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/test_category.dart';
import '../../models/health_package.dart';
import '../../models/cart_item.dart';
import '../../services/cart_service.dart';
import '../../services/booking_service.dart';
import '../../widgets/category_card.dart';
import '../../widgets/package_card.dart';
import 'category_tests_screen.dart';
import 'cart_screen.dart';
import 'patient_appointments_screen.dart';
import 'patient_profile_screen.dart';
import 'hospital_navigation_screen.dart';

final supabase = Supabase.instance.client;

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({Key? key}) : super(key: key);

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  int _currentIndex = 0;
  List<TestCategory> _categories = [];
  List<HealthPackage> _packages = [];
  Map<String, int> _testCounts = {}; // category_id -> test count
  Map<String, int> _packageTestCounts = {}; // package_id -> test count
  bool _isLoading = true;
  String _patientName = '';
  String? _patientId;
  Map<String, dynamic>? _todayAppointment;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPatientInfo();
    _checkTodayAppointment();
  }

  Future<void> _loadPatientInfo() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final data = await supabase
            .from('patients')
            .select('id, full_name')
            .eq('auth_id', userId)
            .single();
        setState(() {
          _patientName = data['full_name'] as String;
          _patientId = data['id'] as String;
        });
      } else {
      }
    } catch (e) {
    }
  }

  Future<void> _checkTodayAppointment() async {
    try {
      if (_patientId == null) {
        await _loadPatientInfo();
      }

      if (_patientId == null) {
        return;
      }
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final appointments = await supabase
          .from('appointments')
          .select('*, appointment_tests(*)')
          .eq('patient_id', _patientId!)
          .eq('appointment_date', todayStr)
          .eq('status', 'scheduled');
          
      if (appointments.isNotEmpty) {
        final appointment = appointments[0];
        final tests = appointment['appointment_tests'] as List? ?? [];
        
        // Hide if all tests are completed
        final allCompleted = tests.isNotEmpty && tests.every((t) => t['status'] == 'completed');
        
        if (!allCompleted) {
          setState(() {
            _todayAppointment = appointment;
          });
          // Show alert after a short delay
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted && _todayAppointment != null) {
              _showAppointmentAlert();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking today appointment: $e');
    }
  }

  void _showAppointmentAlert() {
    if (_todayAppointment == null) {
      return;
    }

    final testCount = (_todayAppointment!['appointment_tests'] as List?)?.length ?? 0;
    final time = _todayAppointment!['appointment_time'] as String;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.orange, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Appointment Today!',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have an appointment scheduled for today.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Time: ${_formatTime(time)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.science, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Tests: $testCount scheduled',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Would you like to start navigation to your first test?',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HospitalNavigationScreen(
                    appointmentId: _todayAppointment!['id'],
                  ),
                ),
              );
            },
            icon: Icon(Icons.navigation),
            label: Text('Start Navigation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String timeStr) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load categories
      final categoriesData = await supabase
          .from('test_categories')
          .select()
          .order('display_order');

      _categories = (categoriesData as List)
          .map((json) => TestCategory.fromJson(json))
          .toList();

      // Load test counts for each category
      final testsData = await supabase.from('tests').select('category_id');

      Map<String, int> counts = {};
      for (var test in testsData as List) {
        final categoryId = test['category_id'] as String;
        counts[categoryId] = (counts[categoryId] ?? 0) + 1;
      }
      _testCounts = counts;

      // Load health packages
      final packagesData = await supabase
          .from('health_packages')
          .select()
          .order('price');

      _packages = (packagesData as List)
          .map((json) => HealthPackage.fromJson(json))
          .toList();

      // Load test counts for packages
      for (var package in _packages) {
        final packageTestsData = await supabase
            .from('health_package_tests')
            .select('test_id')
            .eq('package_id', package.id);

        _packageTestCounts[package.id] = (packageTestsData as List).length;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildHomeTab() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue, Colors.blue.shade300],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _patientName.isNotEmpty ? _patientName : 'Patient',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Test Categories Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Test Categories',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  '${_categories.length} categories',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Categories Grid (2 per row)
            GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final testCount = _testCounts[category.id] ?? 0;

                return CategoryCard(
                  category: category,
                  testCount: testCount,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CategoryTestsScreen(
                          category: category,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            SizedBox(height: 32),

            // Health Packages Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Health Packages',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  '${_packages.length} packages',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Packages List
            Consumer<CartService>(
              builder: (context, cartService, child) {
                return Column(
                  children: _packages.map((package) {
                    final testCount = _packageTestCounts[package.id] ?? 0;
                    final isInCart = cartService.isInCart(package.id);

                    return PackageCard(
                      package: package,
                      testCount: testCount,
                      isInCart: isInCart,
                      onAddToCart: () async {
                        await cartService.addItem(
                          CartItem.fromPackage(package),
                        );

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${package.name} added to cart'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _screens = [
      _buildHomeTab(),
      PatientAppointmentsScreen(),
      PatientProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? 'HealthCare'
              : _currentIndex == 1
              ? 'Appointments'
              : 'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_currentIndex == 0)
            Consumer<CartService>(
              builder: (context, cartService, child) {
                return Stack(
                  children: [
                    IconButton(
                      icon: Icon(Icons.shopping_cart),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CartScreen(),
                          ),
                        );
                      },
                    ),
                    if (cartService.itemCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '${cartService.itemCount}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
        },
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Appointments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}*/

// lib/screens/patient/patient_home_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/test_category.dart';
import '../../models/health_package.dart';
import '../../models/cart_item.dart';
import '../../services/cart_service.dart';
import '../../widgets/category_card.dart';
import '../../widgets/package_card.dart';
import 'category_tests_screen.dart';
import 'cart_screen.dart';
import 'patient_appointments_screen.dart';
import 'patient_profile_screen.dart';
import 'hospital_navigation_screen.dart';
import 'chatbot_screen.dart';
import 'view_reports_screen.dart';

final supabase = Supabase.instance.client;

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({Key? key}) : super(key: key);

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  int _currentIndex = 0;
  List<TestCategory> _categories = [];
  List<HealthPackage> _packages = [];
  Map<String, int> _testCounts = {}; // category_id -> test count
  Map<String, int> _packageTestCounts = {}; // package_id -> test count
  bool _isLoading = true;
  String _patientName = '';
  String? _patientId;
  Map<String, dynamic>? _todayAppointment;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPatientInfo();
    _checkTodayAppointment();
  }

  Future<void> _loadPatientInfo() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final data = await supabase
            .from('patients')
            .select('id, full_name')
            .eq('auth_id', userId)
            .single();
        setState(() {
          _patientName = data['full_name'] as String;
          _patientId = data['id'] as String;
        });
      } else {}
    } catch (e) {}
  }

  Future<void> _checkTodayAppointment() async {
    try {
      if (_patientId == null) {
        await _loadPatientInfo();
      }

      if (_patientId == null) {
        return;
      }
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final appointments = await supabase
          .from('appointments')
          .select(
            '*, appointment_tests!inner(*, test_rooms!appointment_tests_assigned_room_id_fkey(*))',
          )
          .eq('patient_id', _patientId!)
          .eq('appointment_date', todayStr)
          .eq('status', 'scheduled');
      if (appointments.isNotEmpty) {
        setState(() {
          _todayAppointment = appointments[0];
        });
        // Show alert after a short delay
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted && _todayAppointment != null) {
            _showAppointmentAlert();
          } else {}
        });
      } else {}
    } catch (e) {}
  }

  void _showAppointmentAlert() {
    if (_todayAppointment == null) {
      return;
    }

    final testCount =
        (_todayAppointment!['appointment_tests'] as List?)?.length ?? 0;
    final time = _todayAppointment!['appointment_time'] as String;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.orange, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text('Appointment Today!', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have an appointment scheduled for today.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Time: ${_formatTime(time)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.science, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Tests: $testCount scheduled',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Would you like to start navigation to your first test?',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HospitalNavigationScreen(
                    appointmentId: _todayAppointment!['id'],
                  ),
                ),
              );
            },
            icon: Icon(Icons.navigation),
            label: Text('Start Navigation'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ],
      ),
    );
  }

  String _formatTime(String timeStr) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load categories
      final categoriesData = await supabase
          .from('test_categories')
          .select()
          .order('display_order');

      _categories = (categoriesData as List)
          .map((json) => TestCategory.fromJson(json))
          .toList();

      // Load test counts for each category
      final testsData = await supabase.from('tests').select('category_id');

      Map<String, int> counts = {};
      for (var test in testsData as List) {
        final categoryId = test['category_id'] as String;
        counts[categoryId] = (counts[categoryId] ?? 0) + 1;
      }
      _testCounts = counts;

      // Load health packages
      final packagesData = await supabase
          .from('health_packages')
          .select()
          .order('price');

      _packages = (packagesData as List)
          .map((json) => HealthPackage.fromJson(json))
          .toList();

      // Load test counts for packages
      for (var package in _packages) {
        final packageTestsData = await supabase
            .from('health_package_tests')
            .select('test_id')
            .eq('package_id', package.id);

        _packageTestCounts[package.id] = (packageTestsData as List).length;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildHomeTab() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue, Colors.blue.shade300],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _patientName.isNotEmpty ? _patientName : 'Patient',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.person, color: Colors.white, size: 32),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Test Categories Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Test Categories',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  '${_categories.length} categories',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Categories Grid (2 per row)
            GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final testCount = _testCounts[category.id] ?? 0;

                return CategoryCard(
                  category: category,
                  testCount: testCount,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            CategoryTestsScreen(category: category),
                      ),
                    );
                  },
                );
              },
            ),
            SizedBox(height: 32),

            // Health Packages Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Health Packages',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  '${_packages.length} packages',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Packages List
            Consumer<CartService>(
              builder: (context, cartService, child) {
                return Column(
                  children: _packages.map((package) {
                    final testCount = _packageTestCounts[package.id] ?? 0;
                    final isInCart = cartService.isInCart(package.id);

                    return PackageCard(
                      package: package,
                      testCount: testCount,
                      isInCart: isInCart,
                      onAddToCart: () async {
                        await cartService.addItem(
                          CartItem.fromPackage(package),
                        );

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${package.name} added to cart'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _screens = [
      _buildHomeTab(),
      PatientAppointmentsScreen(),
      ViewReportsScreen(),
      PatientProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? 'PathCare'
              : _currentIndex == 1
              ? 'Appointments'
              : _currentIndex == 2
              ? 'My Reports' // ← ADDED
              : 'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_currentIndex == 0)
            Consumer<CartService>(
              builder: (context, cartService, child) {
                return Stack(
                  children: [
                    IconButton(
                      icon: Icon(Icons.shopping_cart),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => CartScreen()),
                        );
                      },
                    ),
                    if (cartService.itemCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '${cartService.itemCount}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          _screens[_currentIndex],
          // Floating Chatbot Button
          if (_currentIndex == 0)
            Positioned(
              bottom: 20,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ChatbotScreen(patientName: _patientName),
                    ),
                  );
                },
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.blue.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
        },
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Appointments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_special),
            label: 'My Reports',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
