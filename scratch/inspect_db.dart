import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final supabase = SupabaseClient(
      'https://zqxxqfkpiqyrkzdfevsi.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxeHhxZmtwaXF5cmt6ZGZldnNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAwNDE0MzksImV4cCI6MjA4NTYxNzQzOX0.xnqxEIH05OIlPeAjE2J5lkvi25hlncEK7-S2rrsCIXQ');
  
  try {
    final response = await supabase
        .from('messages')
        .select()
        .limit(1)
        .order('id', ascending: false);
    print("Messages: $response");
  } catch (e) {
    print('error: $e');
  }
  exit(0);
}
