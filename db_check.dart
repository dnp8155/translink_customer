import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await Supabase.initialize(
    url: 'https://ydmkelswmewcyewpprtf.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkbWtlbHN3bWV3Y3lld3BwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEwNTA4NzYsImV4cCI6MjEwNjYyNjg3Nn0.Qa5U6BMdtpxqspR772VCdHQ7yS4nYADZ5y3zbapGjqY',
  );

  final client = Supabase.instance.client;

  try {
    final list = await client.from('truck_availability').select();
    print('--- ALL TRUCK AVAILABILITY ROWS ---');
    print('Total rows: ${list.length}');
    for (var row in list) {
      print('ROW: origin_city="${row['origin_city']}", destination_city="${row['destination_city']}", available_date="${row['available_date']}", status="${row['status']}"');
    }
  } catch (e) {
    print('Error: $e');
  }
}
