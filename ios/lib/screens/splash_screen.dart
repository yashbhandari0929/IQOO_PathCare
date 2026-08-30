// lib/screens/splash/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

final supabase = Supabase.instance.client;

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Setup animations
    _animationController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _animationController.forward();

    // Check authentication and navigate after 3 seconds
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await Future.delayed(Duration(seconds: 3));

    if (!mounted) return;

    // Check if user is already logged in
    final session = supabase.auth.currentSession;

    if (session != null) {
      // User is logged in, check their role and navigate to appropriate dashboard
      final userId = session.user.id;
      await _checkUserRoleAndNavigate(userId);
    } else {
      // User not logged in, navigate to role selection
      Navigator.pushReplacementNamed(context, '/role-selection');
    }
  }

  Future<void> _checkUserRoleAndNavigate(String userId) async {
    try {
      // Check if user is a patient
      final patientData = await supabase
          .from('patients')
          .select()
          .eq('auth_id', userId)
          .maybeSingle();

      if (patientData != null) {
        Navigator.pushReplacementNamed(context, '/patient-home');
        return;
      }

      // Check if user is a doctor
      final doctorData = await supabase
          .from('doctors')
          .select()
          .eq('auth_id', userId)
          .maybeSingle();

      if (doctorData != null) {
        Navigator.pushReplacementNamed(context, '/doctor-dashboard');
        return;
      }

      // User exists in auth but not in any table, logout and go to role selection
      await supabase.auth.signOut();
      Navigator.pushReplacementNamed(context, '/role-selection');
    } catch (e) {
      print('Error checking user role: $e');
      // On error, go to role selection
      Navigator.pushReplacementNamed(context, '/role-selection');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2196F3), // Blue
              Color(0xFF1976D2), // Darker Blue
              Color(0xFF0D47A1), // Deep Blue
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated Logo
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.local_hospital,
                        size: 80,
                        color: Color(0xFF2196F3),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 40),

                // App Name
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      Text(
                        'HealthCare',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Hospital Management System',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 60),

                // Loading Indicator
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Text(
                    'Loading...',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
