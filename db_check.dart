import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await Supabase.initialize(
    url: 'https://ydmkelswmewcyewpprtf.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkbWtlbHN3bWV3Y3lld3BwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEwNTA4NzYsImV4cCI6MjEwNjYyNjg3Nn0.Qa5U6BMdtpxqspR772VCdHQ7yS4nYADZ5y3zbapGjqY',
  );

  final client = Supabase.instance.client;

  try {
    final response = await client.from('return_requirements').select();
    print('--- RETURN REQUIREMENTS TABLE ---');
    if ((response as List).isEmpty) {
      print('Table is EMPTY!');
    } else {
      for (var req in response) {
        print(req);
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}
