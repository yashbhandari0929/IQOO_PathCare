// lib/main.dart
import 'package:final_app/screens/Room%20Supervisor/supervisor_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/role_selection_screen.dart';
import 'screens/patient/patient_home_screen.dart';
import 'services/cart_service.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/doctor/doctor_dashboard.dart'; // ✅ Make sure this import exists

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    //url: 'https://bjxfmcskpasnuenvxjex.supabase.co', // Replace with your Supabase URL
    //anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqeGZtY3NrcGFzbnVlbnZ4amV4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5OTMyODEsImV4cCI6MjA4NDU2OTI4MX0.FgTVQwqRHR7T5x5S2yfbqx5Da1Pqb-2HvoGVP5p_YLU', // Replace with your Supabase anon key
    /*url: 'https://dlrzfleivroxgfsludmy.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRscnpmbGVpdnJveGdmc2x1ZG15Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzNDM4ODgsImV4cCI6MjA4NDkxOTg4OH0._LqcMtiHo7cKi0oJKGhcAKQSRglIKpRVFbEd2xwm9fU',*/
    url: 'https://zqxxqfkpiqyrkzdfevsi.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxeHhxZmtwaXF5cmt6ZGZldnNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAwNDE0MzksImV4cCI6MjA4NTYxNzQzOX0.xnqxEIH05OIlPeAjE2J5lkvi25hlncEK7-S2rrsCIXQ',
  );

  // Load cart from storage
  await CartService().loadCart();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => CartService(),
      child: MaterialApp(
        title: 'HealthCare Hospital',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.blue, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => SplashScreen(),
          '/role-selection': (context) => RoleSelectionScreen(),
          '/patient-home': (context) => PatientHomeScreen(),
          '/doctor-dashboard': (context) =>
              DoctorDashboardScreen(), // ✅ CHANGED: Now points to actual DoctorDashboard
          '/admin-dashboard': (context) => AdminDashboard(),
          '/supervisor-dashboard': (context) => const SupervisorDashboard(),
        },
      ),
    );
  }
}

// Temporary placeholder screen (can be kept for future use or removed)
class PlaceholderScreen extends StatelessWidget {
  final String title;

  const PlaceholderScreen({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: Colors.blue),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.construction, size: 80, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              '$title Screen',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'Will be implemented in next steps',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Supabase.instance.client.auth.signOut();
                Navigator.pushReplacementNamed(context, '/role-selection');
              },
              child: Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}
