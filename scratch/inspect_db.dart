import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final supabase = SupabaseClient(
      'https://zqxxqfkpiqyrkzdfevsi.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxeHhxZmtwaXF5cmt6ZGZldnNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAwNDE0MzksImV4cCI6MjA4NTYxNzQzOX0.xnqxEIH05OIlPeAjE2J5lkvi25hlncEK7-S2rrsCIXQ');
  
  try {
    // Attempt to select from pg_extension to check if vector exists
    final ext = await supabase.rpc('hello_world'); // Or just test connectivity
    print('Ping: $ext');
  } catch (e) {
    print('error: $e');
  }
  exit(0);
}
