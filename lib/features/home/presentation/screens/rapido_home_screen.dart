import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
class RapidoHomeScreen extends StatefulWidget {
  const RapidoHomeScreen({super.key});

  @override
  State<RapidoHomeScreen> createState() => _RapidoHomeScreenState();
}

class _RapidoHomeScreenState extends State<RapidoHomeScreen> {
  final MapController _mapController = MapController();

  String _currentLocationName = 'Locating...';
  String _currentLocationCity = 'Fetching GPS...';
  LatLng _currentLatLng = const LatLng(23.0225, 72.5714);

  final TextEditingController _originSearchCtrl = TextEditingController();
  final TextEditingController _destSearchCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  bool _isLoadingTrucks = false;
  List<dynamic> _searchResults = [];
  bool _hasSearched = false;

  List<Map<String, String>> _dynamicRoutes = [];
  bool _isLoadingRoutes = false;

  List<LatLng> _routePoints = [];
  LatLng? _originLatLng;
  LatLng? _destLatLng;

  int _selectedTabIndex = 0;

  List<String> _availableCities = [
    'Ahmedabad', 'Surat', 'Vadodara', 'Rajkot', 'Bhavnagar', 'Jamnagar',
    'Gandhinagar', 'Junagadh', 'Anand', 'Navsari', 'Morbi', 'Bharuch',
    'Mumbai', 'Pune', 'Delhi', 'Jaipur', 'Udaipur', 'Indore'
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _fetchAllCities();
    _fetchRoutesFromSupabase();
    _fetchAvailableTrucks();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _currentLocationName = 'Location Services Disabled';
          _currentLocationCity = 'Enable GPS';
        });
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _currentLocationName = 'Location Permission Denied';
            _currentLocationCity = 'Allow access';
          });
        }
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _currentLocationName = 'Location Denied Forever';
          _currentLocationCity = 'Settings required';
        });
      }
      return;
    } 

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      if (mounted) {
        setState(() {
          _currentLatLng = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_currentLatLng, 13.5);
      }
      
      // Reverse geocode with Mapbox
      final token = 'pk.eyJ1IjoidG9tODE1NSIsImEiOiJjbXJheGkzZHoyNms2MndxcmE2N3NidzFhIn0.UT6Ql_m2sJScB7mKiIN9MQ';
      final url = Uri.parse('https://api.mapbox.com/geocoding/v5/mapbox.places/${position.longitude},${position.latitude}.json?access_token=$token&limit=1');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          String name = feature['text'] ?? 'Current Location';
          String city = '';
          if (feature['context'] != null) {
            for (var c in feature['context']) {
              if ((c['id'] as String).startsWith('place')) {
                city = c['text'];
              } else if ((c['id'] as String).startsWith('region')) {
                if (city.isNotEmpty) city += ', ';
                city += c['text'];
              }
            }
          }
          if (city.isEmpty && feature['place_name'] != null) {
            city = feature['place_name'];
          }
          if (mounted) {
            setState(() {
              _currentLocationName = name;
              _currentLocationCity = city;
              if (_originSearchCtrl.text.isEmpty) {
                _originSearchCtrl.text = city;
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _fetchAllCities() async {
    try {
      final res = await Supabase.instance.client
          .from('truck_availability')
          .select('origin_city, destination_city')
          .eq('status', 'available');
      final list = res as List;
      final Set<String> cities = Set.from(_availableCities);
      for (var row in list) {
        if (row['origin_city'] != null && row['origin_city'].toString().trim().isNotEmpty) {
          cities.add(row['origin_city'].toString().trim());
        }
        if (row['destination_city'] != null && row['destination_city'].toString().trim().isNotEmpty) {
          cities.add(row['destination_city'].toString().trim());
        }
      }
      setState(() {
        _availableCities = cities.toList()..sort();
      });
    } catch (e) {
      debugPrint('Error fetching cities: $e');
    }
  }

  @override
  void dispose() {
    _originSearchCtrl.dispose();
    _destSearchCtrl.dispose();
    super.dispose();
  }

    Future<void> _fetchRoutesFromSupabase({String? filterOriginCity}) async {
    setState(() => _isLoadingRoutes = true);
    try {
      // If a city is selected/searched, only show routes FROM that city
      final originFilter = filterOriginCity ?? _originSearchCtrl.text.split(',').first.trim();

      var query = Supabase.instance.client
          .from('truck_availability')
          .select('origin_city, destination_city, available_date, status')
          .inFilter('status', ['available', 'partially_available', 'active']);

      // Filter by origin city if user has selected one
      if (originFilter.isNotEmpty) {
        query = query.ilike('origin_city', '%$originFilter%');
      }

      final res = await query.order('available_date', ascending: true).limit(20);

      final list = res as List;
      final Set<String> seen = {};
      final List<Map<String, String>> routes = [];

      for (var row in list) {
        final origin = (row['origin_city'] ?? '').toString().trim();
        final dest = (row['destination_city'] ?? '').toString().trim();
        final date = (row['available_date'] ?? '').toString();

        if (origin.isNotEmpty && dest.isNotEmpty) {
          final key = '$origin-$dest';
          if (!seen.contains(key)) {
            seen.add(key);
            routes.add({
              'title': dest,
              'subtitle': 'From $origin • $date',
              'origin': origin,
              'dest': dest,
              'date': date.isNotEmpty ? date : '',
              'price': '₹10,805', // indicative price
            });
          }
        }
      }

      // Show placeholder routes only when no filter is applied and DB is empty
      if (routes.isEmpty && originFilter.isEmpty) {
        routes.addAll([
          {'title': 'Mumbai', 'subtitle': '', 'origin': 'Ahmedabad', 'dest': 'Mumbai', 'date': '15-21 Jan', 'price': '₹10,805'},
          {'title': 'Pune', 'subtitle': '', 'origin': 'Ahmedabad', 'dest': 'Pune', 'date': '2-8 Jan', 'price': '₹11,382'},
          {'title': 'Delhi', 'subtitle': '', 'origin': 'Ahmedabad', 'dest': 'Delhi', 'date': '10-14 Feb', 'price': '₹15,400'},
        ]);
      }

      setState(() {
        _dynamicRoutes = routes;
        _isLoadingRoutes = false;
      });
    } catch (e) {
      debugPrint('Error fetching routes: $e');
      setState(() => _isLoadingRoutes = false);
    }
  }

  Future<Map<String, dynamic>?> _geocodeCityDetails(String query) async {
    try {
      final token = 'pk.eyJ1IjoidG9tODE1NSIsImEiOiJjbXJheGkzZHoyNms2MndxcmE2N3NidzFhIn0.UT6Ql_m2sJScB7mKiIN9MQ';
      // Strictly restrict geocoding to India
      final url = Uri.parse('https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?country=IN&access_token=$token&limit=1');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final center = feature['center'];
          
          String cityName = query.split(',').first.trim();
          if (feature['context'] != null) {
            for (var c in feature['context']) {
              if ((c['id'] as String).startsWith('place')) {
                cityName = c['text'];
                break;
              }
            }
          } else if (feature['id'] != null && (feature['id'] as String).startsWith('place')) {
            cityName = feature['text'];
          }

          return {
            'latLng': LatLng(center[1].toDouble(), center[0].toDouble()),
            'city': cityName,
          };
        }
      }
    } catch (e) {
      debugPrint('Geocode error: $e');
    }
    return null;
  }

  Future<Iterable<String>> _fetchPlaceSuggestions(String query) async {
    if (query.isEmpty) return const [];
    try {
      final token = 'pk.eyJ1IjoidG9tODE1NSIsImEiOiJjbXJheGkzZHoyNms2MndxcmE2N3NidzFhIn0.UT6Ql_m2sJScB7mKiIN9MQ';
      // Strictly restrict suggestions to India only (country=IN)
      final url = Uri.parse('https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?country=IN&types=place,locality,district,region,postcode&access_token=$token&autocomplete=true&proximity=${_currentLatLng.longitude},${_currentLatLng.latitude}&limit=6');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null) {
          return (data['features'] as List)
              .map((f) => f['place_name'].toString())
              .where((name) => name.toLowerCase().contains('india'))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Suggestion error: $e');
    }
    return const [];
  }

  Future<void> _fetchMapRoute(LatLng start, LatLng end) async {
    try {
      final token = 'pk.eyJ1IjoidG9tODE1NSIsImEiOiJjbXJheGkzZHoyNms2MndxcmE2N3NidzFhIn0.UT6Ql_m2sJScB7mKiIN9MQ';
      final url = Uri.parse('https://api.mapbox.com/directions/v5/mapbox/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson&access_token=$token');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final geometry = data['routes'][0]['geometry']['coordinates'] as List;
          setState(() {
            _routePoints = geometry.map((p) => LatLng(p[1].toDouble(), p[0].toDouble())).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Routing error: $e');
    }
  }

  Future<void> _fetchAvailableTrucks() async {
    setState(() => _isLoadingTrucks = true);
    try {
      final origin = _originSearchCtrl.text.trim();
      final dest = _destSearchCtrl.text.trim();

      String originCity = origin;
      String destCity = dest;

      if (origin.isNotEmpty && dest.isNotEmpty) {
        final originDetails = await _geocodeCityDetails(origin);
        final destDetails = await _geocodeCityDetails(dest);

        if (originDetails != null && destDetails != null) {
          final originPt = originDetails['latLng'] as LatLng;
          final destPt = destDetails['latLng'] as LatLng;
          originCity = originDetails['city'] as String;
          destCity = destDetails['city'] as String;

          setState(() {
            _originLatLng = originPt;
            _destLatLng = destPt;
          });
          await _fetchMapRoute(originPt, destPt);
          
          try {
            final bounds = LatLngBounds.fromPoints([originPt, destPt, ..._routePoints]);
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(40.0),
              ),
            );
          } catch (e) {
            debugPrint('Map fit error: $e');
          }
        }
      }

      // Extract pure city name (e.g. 'Mumbai, Maharashtra, India' -> 'Mumbai')
      String cleanCity(String text) {
        if (text.isEmpty) return '';
        final firstPart = text.split(',').first.trim();
        return firstPart.split(' ').first.trim();
      }

      final queryOrigin = cleanCity(originCity);
      final queryDest = cleanCity(destCity);

      // Log this search into Supabase `search_requests` table
      String? currentSearchRequestId;
      try {
        final prefs = await SharedPreferences.getInstance();
        final storedCustomerId = prefs.getString('customer_id');

        final searchPayload = {
          if (storedCustomerId != null) 'customer_id': storedCustomerId,
          'pickup_location': originCity.isNotEmpty ? originCity : queryOrigin,
          'pickup_city': queryOrigin,
          'drop_location': destCity.isNotEmpty ? destCity : queryDest,
          'drop_city': queryDest,
          'required_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'search_status': 'active',
        };

        final searchRes = await Supabase.instance.client
            .from('search_requests')
            .insert(searchPayload)
            .select('id')
            .maybeSingle();

        if (searchRes != null) {
          currentSearchRequestId = searchRes['id']?.toString();
        }
      } catch (err) {
        debugPrint('search_requests log error: $err');
      }

      debugPrint('Searching trucks with raw inputs origin: "${_originSearchCtrl.text}", dest: "${_destSearchCtrl.text}"');
      debugPrint('Parsed cities -> Origin: "$queryOrigin", Dest: "$queryDest"');

      // 1. Strict route & date match from truck_availability table
      var query = Supabase.instance.client
          .from('truck_availability').select('*, trucks(truck_number, truck_type), partners(owner_name, mobile_number)')
          .inFilter('status', ['available', 'partially_available', 'active']);

      if (queryOrigin.isNotEmpty) {
        query = query.ilike('origin_city', '%$queryOrigin%');
      }
      if (queryDest.isNotEmpty) {
        query = query.ilike('destination_city', '%$queryDest%');
      }

      // Filter strictly by the selected date (Format: YYYY-MM-DD)
      final formattedSelectedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
      query = query.eq('available_date', formattedSelectedDate);

      var response = await query.order('available_date', ascending: true).limit(20);
      var list = response as List;

      List<dynamic> enriched = [];
      for (var req in list) {
        enriched.add({
          ...req,
          'partner_profiles': req['partners'],
          'trucks': req['trucks'],
          'search_request_id': currentSearchRequestId,
        });
      }

      if (currentSearchRequestId != null) {
        try {
          await Supabase.instance.client
              .from('search_requests')
              .update({'results_count': enriched.length})
              .eq('id', currentSearchRequestId);
        } catch (_) {}
      }

      setState(() {
        _searchResults = enriched;
        _isLoadingTrucks = false;
        _hasSearched = true;
      });
      debugPrint('SUCCESS: Found ${enriched.length} trucks');
      if (enriched.isEmpty) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Query returned 0 results for $origin to $dest')));
      }
    } catch (e, stack) {
      debugPrint('Error loading trucks: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() {
        _isLoadingTrucks = false;
        _hasSearched = true;
      });
    }
  }

  void _openSearchBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final modalOriginCtrl = TextEditingController(text: _originSearchCtrl.text);
        final modalDestCtrl = TextEditingController(text: _destSearchCtrl.text);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.90,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Find Return Route',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                  // Route Inputs Box
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Origin Input
                              Row(
                                children: [
                                  Icon(Icons.trip_origin, color: Colors.grey.shade400, size: 20),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Autocomplete<String>(
                                      initialValue: TextEditingValue(text: modalOriginCtrl.text),
                                      optionsBuilder: (TextEditingValue textEditingValue) async {
                                        if (textEditingValue.text.isEmpty) {
                                          return const Iterable<String>.empty();
                                        }
                                        return await _fetchPlaceSuggestions(textEditingValue.text);
                                      },
                                      onSelected: (String selection) {
                                        modalOriginCtrl.text = selection;
                                        _originSearchCtrl.text = selection;
                                        setModalState(() {});
                                      },
                                      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                                        return TextField(
                                          controller: textEditingController,
                                          focusNode: focusNode,
                                          onChanged: (val) {
                                            modalOriginCtrl.text = val;
                                            _originSearchCtrl.text = val;
                                          },
                                          decoration: InputDecoration(
                                            hintText: 'Where from?',
                                            hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                                          ),
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1E293B)),
                                        );
                                      },
                                      optionsViewBuilder: (context, onSelected, options) {
                                        return Align(
                                          alignment: Alignment.topLeft,
                                          child: Material(
                                            elevation: 8.0,
                                            borderRadius: BorderRadius.circular(12),
                                            shadowColor: Colors.black26,
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(maxHeight: 250, maxWidth: MediaQuery.of(context).size.width - 80),
                                              child: ListView.separated(
                                                padding: EdgeInsets.zero,
                                                shrinkWrap: true,
                                                itemCount: options.length,
                                                separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
                                                itemBuilder: (BuildContext context, int index) {
                                                  final String option = options.elementAt(index);
                                                  return InkWell(
                                                    onTap: () => onSelected(option),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.location_city, size: 18, color: Colors.grey.shade400),
                                                          const SizedBox(width: 12),
                                                          Expanded(
                                                            child: Text(
                                                              option,
                                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 40), // Space for Swap Button
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Divider(color: Colors.grey.shade200, height: 1, indent: 34),
                              ),
                              // Destination Input
                              Row(
                                children: [
                                  const Icon(Icons.location_on, color: Color(0xFFEF4444), size: 20),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Autocomplete<String>(
                                      initialValue: TextEditingValue(text: modalDestCtrl.text),
                                      optionsBuilder: (TextEditingValue textEditingValue) async {
                                        if (textEditingValue.text.isEmpty) {
                                          return const Iterable<String>.empty();
                                        }
                                        return await _fetchPlaceSuggestions(textEditingValue.text);
                                      },
                                      onSelected: (String selection) {
                                        modalDestCtrl.text = selection;
                                        _destSearchCtrl.text = selection;
                                        setModalState(() {});
                                      },
                                      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                                        return TextField(
                                          controller: textEditingController,
                                          focusNode: focusNode,
                                          onChanged: (val) {
                                            modalDestCtrl.text = val;
                                            _destSearchCtrl.text = val;
                                          },
                                          decoration: InputDecoration(
                                            hintText: 'Where to?',
                                            hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                                          ),
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1E293B)),
                                          onSubmitted: (val) {
                                            Navigator.pop(context);
                                            _fetchAvailableTrucks();
                                          },
                                        );
                                      },
                                      optionsViewBuilder: (context, onSelected, options) {
                                        return Align(
                                          alignment: Alignment.topLeft,
                                          child: Material(
                                            elevation: 8.0,
                                            borderRadius: BorderRadius.circular(12),
                                            shadowColor: Colors.black26,
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(maxHeight: 250, maxWidth: MediaQuery.of(context).size.width - 80),
                                              child: ListView.separated(
                                                padding: EdgeInsets.zero,
                                                shrinkWrap: true,
                                                itemCount: options.length,
                                                separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
                                                itemBuilder: (BuildContext context, int index) {
                                                  final String option = options.elementAt(index);
                                                  return InkWell(
                                                    onTap: () => onSelected(option),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.location_on_outlined, size: 18, color: Colors.grey.shade400),
                                                          const SizedBox(width: 12),
                                                          Expanded(
                                                            child: Text(
                                                              option,
                                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 40), // Space for Swap Button
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Swap Button
                        Positioned(
                          right: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.swap_vert_rounded, color: Color(0xFF3B82F6)),
                              onPressed: () {
                                final temp = modalOriginCtrl.text;
                                modalOriginCtrl.text = modalDestCtrl.text;
                                modalDestCtrl.text = temp;

                                _originSearchCtrl.text = modalOriginCtrl.text;
                                _destSearchCtrl.text = modalDestCtrl.text;
                                setModalState(() {});
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Google Flights Style Date and Options Chips
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 30)),
                              );
                              if (date != null) {
                                setState(() => _selectedDate = date);
                                setModalState(() => _selectedDate = date);
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.calendar_month, size: 18, color: Colors.grey.shade600),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat('E, d MMM').format(_selectedDate),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Extra Chip example
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_outline, size: 18, color: Colors.grey.shade600),
                                const SizedBox(width: 8),
                                const Text(
                                  '1 Load',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Divider(color: Colors.grey.shade100, height: 1, thickness: 8),

                  // Search Results Area
                  Expanded(
                    child: !_hasSearched
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Text(
                                'Enter Origin and Destination, then tap Search Trucks to find available return loads.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                              ),
                            ),
                          )
                        : _isLoadingTrucks
                            ? ListView.builder(
                                padding: const EdgeInsets.only(top: 16),
                                itemCount: 3,
                                itemBuilder: (context, index) => _buildShimmerTruckCard(),
                              )
                            : _searchResults.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.local_shipping_outlined, size: 44, color: Colors.grey.shade400),
                                        const SizedBox(height: 10),
                                        Text(
                                          'No return trucks available on this route.',
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    itemCount: _searchResults.length,
                                    itemBuilder: (context, index) {
                                      return _buildTruckCard(_searchResults[index]);
                                    },
                                  ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () async {
                          _originSearchCtrl.text = modalOriginCtrl.text.trim();
                          _destSearchCtrl.text = modalDestCtrl.text.trim();

                          // Update modal state to show loading
                          setModalState(() {
                            _hasSearched = true;
                            _isLoadingTrucks = true;
                          });
                          
                          // Await the fetch function
                          await _fetchAvailableTrucks();
                          
                          // Trigger modal rebuild to show the results
                          setModalState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6), // Google Blue
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          elevation: 2,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search, size: 22),
                            SizedBox(width: 8),
                            Text('Search Trucks', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBody() {
    switch (_selectedTabIndex) {
      case 1:
        return _buildContactedDriversScreen();
      case 2:
        return _buildProfileScreen();
      case 0:
      default:
        return _buildHomeMapStack();
    }
  }

  Widget _buildHomeMapStack() {
    return Stack(
        children: [
          // 1. Clean Top Map Section with Gradient Overlay
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.40,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(20.5937, 78.9629), // Center of India
                    initialZoom: 5.5,
                    minZoom: 4.0,
                    maxZoom: 18.0,
                    cameraConstraint: CameraConstraint.contain(
                      bounds: LatLngBounds(
                        const LatLng(6.5546, 68.1113),  // South-West corner of India
                        const LatLng(35.6745, 97.3953), // North-East corner of India
                      ),
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/navigation-day-v1/tiles/{z}/{x}/{y}?access_token=pk.eyJ1IjoidG9tODE1NSIsImEiOiJjbXJheGkzZHoyNms2MndxcmE2N3NidzFhIn0.UT6Ql_m2sJScB7mKiIN9MQ',
                      userAgentPackageName: 'com.example.translink_customer',
                      additionalOptions: const {
                        'accessToken': 'pk.eyJ1IjoidG9tODE1NSIsImEiOiJjbXJheGkzZHoyNms2MndxcmE2N3NidzFhIn0.UT6Ql_m2sJScB7mKiIN9MQ',
                      },
                    ),
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            color: Colors.blue.shade700,
                            strokeWidth: 4.0,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (_originLatLng == null && _destLatLng == null)
                          Marker(
                            point: const LatLng(23.0225, 72.5714),
                            width: 60,
                            height: 60,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 3.5),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 6,
                                        offset: Offset(0, 2),
                                      )
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_originLatLng != null)
                          Marker(
                            point: _originLatLng!,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on, color: Colors.green, size: 40),
                          ),
                        if (_destLatLng != null)
                          Marker(
                            point: _destLatLng!,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                          ),
                      ],
                    ),
                  ],
                ),
                // Map top gradient
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 100,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Top Header (Location Pill & Logout)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFECFDF5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.my_location, color: Color(0xFF10B981), size: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _currentLocationName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  _currentLocationCity,
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.logout, size: 20, color: Colors.black87),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Logout'),
                            content: const Text('Are you sure you want to logout?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Logout')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('logged_in_phone');
                          await prefs.remove('user_full_name');
                          await prefs.remove('user_email');
                          await prefs.remove('user_gender');
                          if (!context.mounted) return;
                          context.go('/login');
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Rapido Exact Sheet with Smooth Curves
          DraggableScrollableSheet(
            initialChildSize: 0.65,
            minChildSize: 0.60,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 24,
                      offset: Offset(0, -6),
                    )
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    // Sheet Pill Indicator
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 12),
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    // Rapido "Where do you want to go?" Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: GestureDetector(
                        onTap: _openSearchBottomSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              )
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: Color(0xFF1E293B), size: 24),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  _destSearchCtrl.text.isEmpty
                                      ? 'Where do you want to go?'
                                      : 'To: ${_destSearchCtrl.text}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: _destSearchCtrl.text.isEmpty
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Recent destination shortcuts (Exact Rapido Design)
                    _buildRecentItem(
                      title: 'Dastan Circle',
                      subtitle: 'Sardar Patel Ring Road, Kathwada, Gujarat,...',
                      distance: '22 km',
                      dest: 'Kathwada, Ahmedabad',
                    ),
                    _buildRecentItem(
                      title: 'Bhat Circle',
                      subtitle: 'GIDC Bhat, Bhat, Ahmedabad, Gujarat, India',
                      distance: '20 km',
                      dest: 'Gandhinagar',
                    ),
                    _buildRecentItem(
                      title: 'Surat Ring Road Hub',
                      subtitle: 'Kamrej Char Rasta, Surat, Gujarat',
                      distance: '265 km',
                      dest: 'Surat',
                    ),

                    const SizedBox(height: 18),


                    const SizedBox(height: 24),
                    Divider(color: Colors.grey.shade100, thickness: 8),
                    const SizedBox(height: 16),

                    // Available Return Trucks Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _hasSearched && _destSearchCtrl.text.isNotEmpty
                                ? 'Trucks to ${_destSearchCtrl.text}'
                                : 'Available Return Trucks',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Available Trucks List
                    if (_isLoadingTrucks)
                      ...List.generate(3, (index) => _buildShimmerTruckCard())
                    else if (_searchResults.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.local_shipping_outlined, size: 44, color: Colors.grey.shade400),
                              const SizedBox(height: 10),
                              Text(
                                'No return trucks available on this route.',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _openSearchBottomSheet,
                                child: const Text(
                                  'Search Other Route',
                                  style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._searchResults.map((truck) => _buildTruckCard(truck)),

                    const SizedBox(height: 60),
                  ],
                ),
              );
            },
          ),
        ],
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _buildBody(),
      // Clean Bottom Navigation Bar (Rapido style)
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_filled, 'Ride'),
                _buildNavItem(1, Icons.history_rounded, 'Contacts'),
                _buildNavItem(2, Icons.person_outline_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Exact Rapido Recent Location Row
  Widget _buildRecentItem({
    required String title,
    required String subtitle,
    required String distance,
    required String dest,
  }) {
    return InkWell(
      onTap: () {
        _destSearchCtrl.text = dest;
        _fetchAvailableTrucks();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 11.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Icon(Icons.history_rounded, color: Colors.grey.shade500, size: 20),
                const SizedBox(height: 2),
                Text(
                  distance,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.favorite_border_rounded, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // 1. Parcel Card
  Widget _buildCardParcel() {
    return InkWell(
      onTap: _openSearchBottomSheet,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 110,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send\nanything',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.2),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Parcel',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE68A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.inventory_2_rounded, color: Color(0xFFB45309), size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. Book Now / Trucks
  Widget _buildCardBookNow() {
    return InkWell(
      onTap: _openSearchBottomSheet,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your everyday return loads', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 2),
            const Text(
              'Book truck',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.local_shipping_rounded, size: 48, color: const Color(0xFFF59E0B)),
                const SizedBox(width: 4),
                Icon(Icons.fire_truck_rounded, size: 36, color: const Color(0xFF10B981)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 3. Heavy / Express Truck Card (Rapido Bike Taxi equivalent)
  Widget _buildCardBikeTaxi() {
    return InkWell(
      onTap: _openSearchBottomSheet,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCFCE7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Save up to 50%', style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            const Text(
              'Return Truck',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
                  ],
                ),
                child: const Icon(Icons.local_shipping, size: 40, color: Color(0xFF059669)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 4. All Services
  Widget _buildCardAllServices() {
    return InkWell(
      onTap: _openSearchBottomSheet,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 90,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'All\nServices',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.grid_view_rounded, color: Color(0xFFF59E0B), size: 24),
            ),
          ],
        ),
      ),
    );
  }

  // Shimmer Truck Card
  Widget _buildShimmerTruckCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 14, width: 100, color: Colors.white),
                    const SizedBox(height: 6),
                    Container(height: 10, width: 70, color: Colors.white),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(height: 12, width: double.infinity, color: Colors.white),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(height: 14, width: 80, color: Colors.white),
                Container(height: 36, width: 110, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Truck Result Card
  Widget _buildTruckCard(dynamic item) {
    final partner = item['partner_profiles'];
    final truck = item['trucks'];
    final ownerName = partner != null ? partner['owner_name'] ?? 'Translink Partner' : 'Translink Partner';
    final truckNo = truck != null ? (truck['truck_number'] ?? truck['vehicle_number'] ?? 'Truck Available') : 'Truck Available';
    final vehicleType = truck != null ? (truck['truck_type'] ?? truck['vehicle_type'] ?? '14 - 32 Ft Truck') : 'Available Load';
    final mobile = partner != null ? (partner['mobile'] ?? partner['mobile_number'] ?? '') : '';
    final rating = partner != null && partner['rating'] != null ? partner['rating'].toString() : '4.8';

    final origin = item['origin_city'] ?? 'Ahmedabad';
    final destination = item['destination_city'] ?? 'Mumbai';
    final requiredDate = item['available_date'] ?? item['required_date'] ?? 'Available Today';

    return InkWell(
      onTap: () {
        _showTruckDetailsSheet(item, ownerName, truckNo, vehicleType, mobile);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Top Section (Icon, Title, Route, Rating)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE), // Light blue background
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(Icons.local_shipping_outlined, color: Color(0xFF0369A1), size: 32),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vehicleType, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B))),
                      const SizedBox(height: 2),
                      Text(truckNo, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '$origin ➔ $destination', 
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Color(0xFFFACC15)),
                        const SizedBox(width: 4),
                        Text(rating, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B))),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('(112 Reviews)', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Bottom Section (Date, Location snippet, Button)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Available: $requiredDate', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      const SizedBox(height: 2),
                      Text(origin, style: TextStyle(fontSize: 13, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981), // Emerald Green
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Get Contact Number', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      SizedBox(width: 6),
                      Icon(Icons.call, color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTruckDetailsSheet(dynamic item, String ownerName, String truckNo, String vehicleType, String mobile) {
    bool isNumberVisible = false;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Indicator
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
                  ),
                  const SizedBox(height: 24),
                  // Truck Title
                  Row(
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.local_shipping, color: Color(0xFF10B981), size: 36),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(vehicleType, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                            const SizedBox(height: 4),
                            Text(truckNo, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                        child: const Text('Verified', style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Divider(color: Colors.grey.shade100, height: 1),
                  const SizedBox(height: 20),
                  
                  // Route Details
                  const Text('Route Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.trip_origin, color: Colors.blue, size: 18),
                      const SizedBox(width: 12),
                      Expanded(child: Text('${item['origin_city']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    ],
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    height: 20, width: 2, color: Colors.grey.shade300,
                  ),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.red, size: 18),
                      const SizedBox(width: 12),
                      Expanded(child: Text('${item['destination_city']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.calendar_month, color: Colors.grey, size: 18),
                      const SizedBox(width: 12),
                      Text('Available: ${item['available_date'] ?? item['required_date'] ?? 'Immediate'}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    ],
                  ),
                  if (item['trucks'] != null && (item['trucks']['capacity_tons'] != null || item['trucks']['capacity_kg'] != null)) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.fitness_center, color: Colors.grey, size: 18),
                        const SizedBox(width: 12),
                        Text(
                          'Capacity: ${item['trucks']['capacity_tons'] != null ? '${item['trucks']['capacity_tons']} Tons' : '${item['trucks']['capacity_kg']} Kg'}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                  
                  const SizedBox(height: 20),
                  Divider(color: Colors.grey.shade100, height: 1),
                  const SizedBox(height: 20),
                  
                  // Owner
                  Row(
                    children: [
                      CircleAvatar(radius: 22, backgroundColor: Colors.grey.shade200, child: const Icon(Icons.person, color: Colors.grey)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ownerName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                            const SizedBox(height: 2),
                            Text('Partner • ★ 4.8', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Call Button Logic
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: isNumberVisible
                        ? ElevatedButton.icon(
                            onPressed: () async {
                              final Uri launchUri = Uri(scheme: 'tel', path: mobile);
                              if (await canLaunchUrl(launchUri)) {
                                await launchUrl(launchUri);
                              }
                              // Log direct dial call into contact_logs
                              try {
                                final prefs = await SharedPreferences.getInstance();
                                final customerId = prefs.getString('customer_id');
                                final profileId = prefs.getString('profile_id');
                                await Supabase.instance.client.from('contact_logs').insert({
                                  if (customerId != null) 'customer_id': customerId,
                                  'partner_id': item['partner_id'],
                                  'truck_id': item['truck_id'],
                                  if (profileId != null) 'performed_by': profileId,
                                  'contact_type': 'call',
                                  'contact_direction': 'outbound',
                                  'outcome': 'dialed',
                                });
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.call, size: 20),
                            label: Text('Dial: $mobile', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: isSaving ? null : () async {
                              if (mobile.isNotEmpty) {
                                setModalState(() => isSaving = true);
                                try {
                                  // Save locally for Contacts Tab first
                                  await _saveContactedDriver(item, ownerName, truckNo, vehicleType, mobile);
                                  
                                  // Log contact view to Supabase database (kis user ne kiska contact dekha)
                                  try {
                                    final prefs = await SharedPreferences.getInstance();
                                    final customerPhone = prefs.getString('logged_in_phone') ?? 'Guest';
                                    final customerName = prefs.getString('user_full_name') ?? 'Translink User';
                                    final customerId = prefs.getString('customer_id');
                                    final profileId = prefs.getString('profile_id');
                                    final searchRequestId = item['search_request_id'];

                                    // 1. Log to contact_logs table (Direct schema match)
                                    try {
                                      await Supabase.instance.client.from('contact_logs').insert({
                                        if (customerId != null) 'customer_id': customerId,
                                        'partner_id': item['partner_id'],
                                        'truck_id': item['truck_id'],
                                        if (profileId != null) 'performed_by': profileId,
                                        'contact_type': 'view_contact_number',
                                        'contact_direction': 'outbound',
                                        'outcome': 'contact_viewed',
                                        'notes': 'Customer viewed contact number of truck $truckNo',
                                      });
                                    } catch (clErr) {
                                      debugPrint('contact_logs error: $clErr');
                                    }

                                    // 2. Also log to driver_number_views table
                                    try {
                                      await Supabase.instance.client.from('driver_number_views').insert({
                                        if (customerId != null) 'customer_id': customerId,
                                        'customer_phone': customerPhone,
                                        'customer_name': customerName,
                                        'partner_id': item['partner_id'],
                                        'truck_id': item['truck_id'],
                                        'owner_name': ownerName,
                                        'truck_number': truckNo,
                                        'driver_phone': mobile,
                                        'origin': item['origin_city'] ?? '',
                                        'destination': item['destination_city'] ?? '',
                                      });
                                    } catch (_) {}
                                  } catch (e) {
                                    debugPrint('Database view logging notice: $e');
                                  }

                                  setModalState(() {
                                    isNumberVisible = true;
                                    isSaving = false;
                                  });
                                  if (mounted) setState(() {});
                                } catch (e) {
                                  debugPrint('Error logging view: $e');
                                  // Fallback to reveal if network fails for smooth UX
                                  setModalState(() {
                                    isNumberVisible = true;
                                    isSaving = false;
                                  });
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact details unavailable')));
                              }
                            },
                            icon: isSaving
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.visibility, size: 20),
                            label: Text(isSaving ? 'Fetching...' : 'Get Contact Number', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Exact Rapido Bottom Nav Item
  Widget _buildNavItem(int index, IconData icon, String label, {VoidCallback? onTap}) {
    final isSelected = _selectedTabIndex == index;
    final color = isSelected ? Colors.black : Colors.grey.shade400;

    return InkWell(
      onTap: () {
        setState(() => _selectedTabIndex = index);
        if (onTap != null) onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveContactedDriver(dynamic item, String ownerName, String truckNo, String vehicleType, String mobile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsStr = prefs.getString('contacted_drivers') ?? '[]';
      final List contacts = json.decode(contactsStr);
      
      final newContact = {
        'owner_name': ownerName,
        'truck_number': truckNo,
        'vehicle_type': vehicleType,
        'mobile_number': mobile,
        'origin': item['origin_city'] ?? '',
        'destination': item['destination_city'] ?? '',
        'contact_time': DateTime.now().toIso8601String(),
      };
      
      bool exists = contacts.any((c) => c['mobile_number'] == mobile && c['truck_number'] == truckNo);
      if (!exists) {
        contacts.insert(0, newContact);
        await prefs.setString('contacted_drivers', json.encode(contacts));
      }
    } catch (e) {
      debugPrint('Error saving contact: $e');
    }
  }

  Future<List<dynamic>> _getContactedDrivers() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsStr = prefs.getString('contacted_drivers') ?? '[]';
    return json.decode(contactsStr);
  }

  Widget _buildContactedDriversScreen() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text(
              'Contacted Drivers',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _getContactedDrivers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final drivers = snapshot.data ?? [];
                if (drivers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('No drivers contacted yet', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: drivers.length,
                  itemBuilder: (context, index) {
                    final driver = drivers[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFECFDF5),
                        child: Icon(Icons.local_shipping, color: Color(0xFF10B981)),
                      ),
                      title: Text('${driver['owner_name']} - ${driver['truck_number']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${driver['origin']} → ${driver['destination']}\n${driver['mobile_number']}'),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.call, color: Color(0xFF10B981)),
                        onPressed: () => launchUrl(Uri(scheme: 'tel', path: driver['mobile_number'])),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(String currentName, String currentEmail, String currentGender) {
    final nameController = TextEditingController(text: currentName == 'Translink User' ? '' : currentName);
    final emailController = TextEditingController(text: currentEmail);
    String selectedGender = currentGender.isNotEmpty ? currentGender.toUpperCase() : 'MALE';
    if (!['MALE', 'FEMALE', 'OTHER'].contains(selectedGender)) {
      selectedGender = 'MALE';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Full Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: 'Enter your full name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Email Address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Enter your email',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Gender', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedGender,
                  items: const [
                    DropdownMenuItem(value: 'MALE', child: Text('Male')),
                    DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
                    DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedGender = val);
                    }
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final newName = nameController.text.trim();
                final newEmail = emailController.text.trim();
                
                final prefs = await SharedPreferences.getInstance();
                if (newName.isNotEmpty) await prefs.setString('user_full_name', newName);
                if (newEmail.isNotEmpty) await prefs.setString('user_email', newEmail);
                await prefs.setString('user_gender', selectedGender);
                final phone = prefs.getString('logged_in_phone');

                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);

                if (phone != null && phone.isNotEmpty) {
                  try {
                    await Supabase.instance.client.from('profiles').update({
                      if (newName.isNotEmpty) 'full_name': newName,
                      if (newEmail.isNotEmpty) 'email': newEmail,
                    }).eq('mobile_number', phone);
                  } catch (e) {
                    debugPrint('Supabase profile update warning: $e');
                  }
                }

                if (mounted) {
                  navigator.pop();
                  setState(() {});
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Profile updated successfully!')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('logged_in_phone');
      final localName = prefs.getString('user_full_name');
      final localEmail = prefs.getString('user_email');

      final localGender = prefs.getString('user_gender');

      if (phone != null && phone.isNotEmpty) {
        try {
          final res = await Supabase.instance.client
              .from('profiles')
              .select()
              .eq('mobile_number', phone)
              .maybeSingle();
          if (res != null) {
            return {
              ...res,
              if (localGender != null && localGender.isNotEmpty) 'gender': localGender,
            };
          }
        } catch (e) {
          debugPrint('Supabase profile query error: $e');
        }

        // Return locally stored profile data if Supabase hasn't populated yet
        if (localName != null && localName.isNotEmpty) {
          return {
            'full_name': localName,
            'mobile_number': phone,
            'email': localEmail ?? '',
            'gender': localGender ?? '',
          };
        } else {
          return {
            'full_name': 'Translink User',
            'mobile_number': phone,
            'email': localEmail ?? '',
            'gender': localGender ?? '',
          };
        }
      }
    } catch (e) {
      debugPrint('Profile fetch error: $e');
    }
    return null;
  }

  Widget _buildProfileScreen() {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchUserProfile(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = snapshot.data;
          final name = (userData?['full_name'] != null && userData!['full_name'].toString().isNotEmpty)
              ? userData['full_name'].toString()
              : 'Translink User';
          final email = (userData?['email'] != null && userData!['email'].toString().isNotEmpty)
              ? userData['email'].toString()
              : 'Not provided';
          final phone = userData?['mobile_number'] ?? '';
          final gender = (userData?['gender'] != null && userData!['gender'].toString().isNotEmpty)
              ? userData['gender'].toString().toUpperCase()
              : 'NOT SPECIFIED';
          
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'My Profile',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    ),
                    TextButton.icon(
                      onPressed: () => _showEditProfileDialog(name, email == 'Not provided' ? '' : email, gender == 'NOT SPECIFIED' ? 'Male' : gender),
                      icon: const Icon(Icons.edit, size: 18, color: Color(0xFF0284C7)),
                      label: const Text('Edit', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Center(
                  child: CircleAvatar(
                    radius: 46,
                    backgroundColor: const Color(0xFFE0F2FE),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Column(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        phone,
                        style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Details Card (Name, Mobile, Email, Gender)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      _buildProfileDetailRow(Icons.person_outline, 'Full Name', name),
                      Divider(height: 20, color: Colors.grey.shade200),
                      _buildProfileDetailRow(Icons.phone_outlined, 'Mobile Number', phone),
                      Divider(height: 20, color: Colors.grey.shade200),
                      _buildProfileDetailRow(Icons.email_outlined, 'Email', email),
                      Divider(height: 20, color: Colors.grey.shade200),
                      _buildProfileDetailRow(
                        gender.toLowerCase().contains('fem') ? Icons.female : Icons.male,
                        'Gender',
                        gender,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                    child: const Icon(Icons.history_rounded, color: Color(0xFF1E293B), size: 20),
                  ),
                  title: const Text('My Viewed Contacts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                  onTap: () {
                    setState(() => _selectedTabIndex = 1);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                    child: const Icon(Icons.help_outline, color: Color(0xFF1E293B), size: 20),
                  ),
                  title: const Text('Help & Support', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                  onTap: () {},
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                    child: const Icon(Icons.logout, color: Colors.red, size: 20),
                  ),
                  title: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 15)),
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('logged_in_phone');
                    await prefs.remove('user_full_name');
                    await prefs.remove('user_email');
                    await prefs.remove('user_gender');
                    if (!context.mounted) return;
                    context.go('/login');
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildProfileDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF64748B)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          ],
        ),
      ],
    );
  }
}
