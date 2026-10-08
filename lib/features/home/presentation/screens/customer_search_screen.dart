import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/widgets/primary_button.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomerSearchScreen extends StatefulWidget {
  const CustomerSearchScreen({super.key});

  @override
  State<CustomerSearchScreen> createState() => _CustomerSearchScreenState();
}

class _CustomerSearchScreenState extends State<CustomerSearchScreen> {
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  DateTime? _selectedDate;
  bool _isLoading = false;
  List<dynamic> _searchResults = [];

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _searchTrucks() async {
    final origin = _originController.text.trim();
    final dest = _destinationController.text.trim();

    if (origin.isEmpty || dest.isEmpty || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields')));
      return;
    }

    setState(() {
      _isLoading = true;
      _searchResults = [];
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      
      // Save the search request first
      String? searchRequestId;
      try {
         final searchRes = await Supabase.instance.client.from('search_requests').insert({
            'pickup_location': origin,
            'pickup_city': origin,
            'drop_location': dest,
            'drop_city': dest,
            'required_date': dateStr,
            'search_status': 'active'
         }).select('id').maybeSingle();
         if (searchRes != null) {
            searchRequestId = searchRes['id'];
         }
      } catch (e) {
         debugPrint('Error saving search request: $e');
      }

      String cleanCity(String text) {
        if (text.isEmpty) return '';
        final firstPart = text.split(',').first.trim();
        return firstPart.split(' ').first.trim();
      }

      final queryOrigin = cleanCity(origin);
      final queryDest = cleanCity(dest);

      // Query truck_availability matching the criteria
      var query = Supabase.instance.client
          .from('truck_availability')
          .select('*, trucks(truck_number, truck_type), partners(owner_name, mobile_number)');

      if (queryOrigin.isNotEmpty) {
        query = query.ilike('origin_city', '%$queryOrigin%');
      }
      if (queryDest.isNotEmpty) {
        query = query.ilike('destination_city', '%$queryDest%');
      }
      
      query = query.eq('available_date', dateStr);

      final response = await query.inFilter('status', ['available', 'partially_available', 'active']);

      List<dynamic> enrichedResults = [];
      
      for (var trip in (response as List)) {
        enrichedResults.add({
          ...trip,
          'partner_profiles': trip['partners'],
          'trucks': trip['trucks'],
        });
      }

      // Update the results_count in search_requests
      if (searchRequestId != null) {
         try {
           await Supabase.instance.client.from('search_requests')
              .update({'results_count': enrichedResults.length})
              .eq('id', searchRequestId);
         } catch (_) {}
      }

      setState(() {
        _searchResults = enrichedResults;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        title: const Text('Find Return Trucks', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            tooltip: 'Logout',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Kya aap logout karna chahte hain?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Nahi'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );

              if (confirm == true && mounted) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                await Supabase.instance.client.auth.signOut();
                if (mounted) {
                  context.go('/login');
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Box
          Container(
            padding: const EdgeInsets.all(24),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _originController,
                  decoration: InputDecoration(
                    hintText: 'From (e.g. Surat)',
                    prefixIcon: const Icon(Icons.my_location),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _destinationController,
                  decoration: InputDecoration(
                    hintText: 'To (e.g. Ahmedabad)',
                    prefixIcon: const Icon(Icons.location_on),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_selectedDate == null ? 'Select Date' : DateFormat('dd MMM yyyy').format(_selectedDate!)),
                        const Icon(Icons.calendar_today, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(text: 'Search Trucks', onPressed: _searchTrucks),
              ],
            ),
          ),
          
          // Results
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _searchResults.isEmpty
                ? const Center(child: Text('No trucks found for this route.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final req = _searchResults[index];
                      final partner = req['partner_profiles'];
                      final truck = req['trucks'];
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(partner?['owner_name'] ?? 'Driver', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    color: Colors.green.shade100,
                                    child: const Text('Available', style: TextStyle(color: Colors.green)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text('Route: ${req['origin_city']} to ${req['destination_city']}'),
                              Text('Truck: ${truck?['truck_type'] ?? 'N/A'} (${truck?['truck_number'] ?? 'N/A'})'),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () async {
                                        final contactInfo = partner?['mobile'] ?? partner?['mobile_number'];
                                        if (contactInfo != null) {
                                          final url = Uri.parse('tel:$contactInfo');
                                          if (await canLaunchUrl(url)) {
                                            await launchUrl(url);
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch dialer')));
                                          }
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contact info')));
                                        }
                                        
                                        // Log the contact event
                                        try {
                                          await Supabase.instance.client.from('contact_logs').insert({
                                            'partner_id': req['partner_id'],
                                            'truck_id': req['truck_id'],
                                            'contact_type': 'call',
                                            'contact_direction': 'outbound'
                                          });
                                        } catch (_) {}
                                      },
                                      icon: const Icon(Icons.phone),
                                      label: const Text('Call'),
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A1128), foregroundColor: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () async {
                                        final contactInfo = partner?['mobile'] ?? partner?['mobile_number'];
                                        if (contactInfo != null) {
                                          final msg = 'Hello, I found your truck on Return Translink for ${req['origin_city']} \u2192 ${req['destination_city']}. I would like to discuss the transport requirement.';
                                          final url = Uri.parse('https://wa.me/$contactInfo?text=${Uri.encodeComponent(msg)}');
                                          if (await canLaunchUrl(url)) {
                                            await launchUrl(url, mode: LaunchMode.externalApplication);
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch WhatsApp')));
                                          }
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contact info')));
                                        }
                                        
                                        // Log the contact event
                                        try {
                                          await Supabase.instance.client.from('contact_logs').insert({
                                            'partner_id': req['partner_id'],
                                            'truck_id': req['truck_id'],
                                            'contact_type': 'whatsapp',
                                            'contact_direction': 'outbound'
                                          });
                                        } catch (_) {}
                                      },
                                      icon: const Icon(Icons.chat), // WhatsApp icon equivalent
                                      label: const Text('WhatsApp'),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                    ),
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
        ],
      ),
    );
  }
}
