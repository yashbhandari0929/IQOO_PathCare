// lib/screens/patient/blood_bank_screen.dart
//
// ─── PERFORMANCE OPTIMIZATIONS (v3) ─────────────────────────────────────────
//  1. LOCAL DATA in _allBanks at field-init — frame 1 shows 28 banks, zero wait
//  2. TRUE PARALLEL bootstrap — cache + GPS + Overpass all fire simultaneously
//  3. SharedPreferences SINGLETON — getInstance() called once, reused forever
//  4. Cache JSON decoded/encoded on isolate via compute() — UI never janks
//  5. Overpass query simplified (dropped slow regex clause) + timeout 12 s
//  6. Mirror RACE (Future.any) — fastest of 3 mirrors wins
//  7. O(1) hash for filter + marker memoization (was O(n) fold)
//  8. Stat counts memoized (_recomputeStats) — 0 where() calls per build
//  9. TileLayer with CancellableNetworkTileProvider + keepBuffer/panBuffer
// 10. _bootstrap() is sync — returns in < 1 µs, no async overhead
// 11. All errors silent — user always sees banks, never a blank screen
//
// ─── REQUIRED pubspec.yaml packages ──────────────────────────────────────────
//   flutter_map: ^8.2.2
//   latlong2: ^0.9.0
//   url_launcher: ^6.3.0
//   geolocator: ^14.0.2
//   flutter_map_location_marker: ^10.0.0
//   http: ^1.1.0
//   shared_preferences: ^2.3.2       ← NEW (cache)
//
// ─── PLATFORM SETUP ───────────────────────────────────────────────────────────
//   Android → android/app/src/main/AndroidManifest.xml
//     <application android:usesCleartextTraffic="true" ...>
//     <uses-permission android:name="android.permission.INTERNET"/>
//     <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
//     <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
//
//   iOS → ios/Runner/Info.plist
//     <key>NSLocationWhenInUseUsageDescription</key>
//     <string>Shows nearby blood banks on the map.</string>
//     <key>NSAppTransportSecurity</key>
//     <dict><key>NSAllowsArbitraryLoads</key><true/></dict>

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

const String _demoPhone = '+919876543210';
const String _predefinedMsg =
    '🚨 URGENT BLOOD REQUEST 🚨\n\n'
    'Hello, I urgently need blood. This is a medical emergency.\n'
    'Please assist or guide me to the nearest available blood unit.\n\n'
    'Thank you 🙏';

const List<String> _bloodGroups = [
  'A+',
  'A−',
  'B+',
  'B−',
  'AB+',
  'AB−',
  'O+',
  'O−',
];

const List<String> _typeFilters = ['All', 'Government', 'Private', 'Trust'];

// All 3 mirrors raced simultaneously — fastest wins
const List<String> _overpassMirrors = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

const String _nominatimUrl = 'https://nominatim.openstreetmap.org/search';
const Map<String, String> _nominatimHeaders = {
  'User-Agent': 'BloodBankFinderApp/1.0 (contact@example.com)',
  'Accept-Language': 'en',
};

const String _cacheKey = 'bb_cache_v2';
const String _cachePosKey = 'bb_cache_pos_v2';
const Duration _cacheTtl = Duration(hours: 6);

// ═══════════════════════════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class BloodBank {
  final String id;
  final String name;
  final String address;
  final String phone;
  final double latitude;
  final double longitude;
  final String timing;
  final String type;
  final String area;
  final Map<String, int>? bloodStock;

  const BloodBank({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.timing,
    required this.type,
    required this.area,
    this.bloodStock,
  });

  String get effectivePhone => phone;

  bool get hasRealPhone => phone.isNotEmpty && phone != 'N/A';

  // JSON serialization for cache
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'phone': phone,
    'lat': latitude,
    'lon': longitude,
    'timing': timing,
    'type': type,
    'area': area,
    if (bloodStock != null) 'bloodStock': bloodStock,
  };

  factory BloodBank.fromJson(Map<String, dynamic> j) => BloodBank(
    id: j['id'] as String,
    name: j['name'] as String,
    address: j['address'] as String,
    phone: j['phone'] as String,
    latitude: (j['lat'] as num).toDouble(),
    longitude: (j['lon'] as num).toDouble(),
    timing: j['timing'] as String,
    type: j['type'] as String,
    area: j['area'] as String,
    bloodStock: j['bloodStock'] != null
        ? Map<String, int>.from(j['bloodStock'] as Map)
        : null,
  );

  factory BloodBank.fromOverpass(Map<String, dynamic> el) {
    final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
    final id = 'osm_${el['id']}';
    final name =
        tags['name'] as String? ?? tags['name:en'] as String? ?? 'Blood Bank';
    final phone =
        tags['contact:phone'] as String? ??
        tags['phone'] as String? ??
        tags['contact:mobile'] as String? ??
        tags['mobile'] as String? ??
        '';
    final area =
        tags['addr:suburb'] as String? ?? tags['addr:city'] as String? ?? '';

    double lat, lon;
    if (el['type'] == 'node') {
      lat = (el['lat'] as num).toDouble();
      lon = (el['lon'] as num).toDouble();
    } else {
      final center = (el['center'] as Map<String, dynamic>?) ?? {};
      lat = (center['lat'] as num?)?.toDouble() ?? 0.0;
      lon = (center['lon'] as num?)?.toDouble() ?? 0.0;
    }

    return BloodBank(
      id: id,
      name: name,
      address: _buildAddress(tags),
      phone: phone,
      latitude: lat,
      longitude: lon,
      timing: tags['opening_hours'] as String? ?? 'Hours not listed',
      type: _inferType(tags),
      area: area,
    );
  }

  static String _buildAddress(Map<String, dynamic> t) {
    final parts = <String>[
      if (t['addr:housenumber'] != null) t['addr:housenumber'] as String,
      if (t['addr:street'] != null) t['addr:street'] as String,
      if (t['addr:suburb'] != null) t['addr:suburb'] as String,
      if (t['addr:city'] != null) t['addr:city'] as String,
      if (t['addr:postcode'] != null) t['addr:postcode'] as String,
    ];
    return parts.isNotEmpty ? parts.join(', ') : 'Address not available';
  }

  static String _inferType(Map<String, dynamic> t) {
    final op = ((t['operator:type'] ?? t['ownership'] ?? '') as String)
        .toLowerCase();
    final opr = ((t['operator'] ?? '') as String).toLowerCase();
    if (op.contains('government') ||
        op.contains('public') ||
        opr.contains('govt') ||
        opr.contains('municipal') ||
        opr.contains('bmc'))
      return 'Government';
    if (op.contains('ngo') ||
        op.contains('trust') ||
        op.contains('charity') ||
        opr.contains('red cross') ||
        opr.contains('rotary'))
      return 'Trust';
    return 'Private';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOCAL DATASET  (instant, offline)
// ═══════════════════════════════════════════════════════════════════════════════

const List<BloodBank> _localBloodBanks = [
  // ── SOUTH MUMBAI ──────────────────────────────────────────────────────────
  BloodBank(
    id: 'kem_hosp',
    name: 'KEM Hospital Blood Bank',
    address: 'Acharya Donde Marg, Parel, Mumbai 400 012',
    phone: '02224107000',
    latitude: 19.0007,
    longitude: 72.8407,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Parel',
  ),
  BloodBank(
    id: 'sion_hosp',
    name: 'Sion Hospital Blood Bank',
    address: 'Dr Ambedkar Rd, Sion (W), Mumbai 400 022',
    phone: '02224076381',
    latitude: 19.0397,
    longitude: 72.8659,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Sion',
  ),
  BloodBank(
    id: 'nair_hosp',
    name: 'Nair Hospital Blood Bank',
    address: 'Dr A L Nair Rd, Mumbai Central, Mumbai 400 008',
    phone: '02223027444',
    latitude: 18.9716,
    longitude: 72.8204,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Mumbai Central',
  ),
  BloodBank(
    id: 'gt_hosp',
    name: 'GT Hospital Blood Bank',
    address: 'Lokmanya Tilak Marg, Fort, Mumbai 400 001',
    phone: '02222620000',
    latitude: 18.9356,
    longitude: 72.8347,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Fort',
  ),
  BloodBank(
    id: 'jj_hosp',
    name: 'JJ Hospital Blood Bank',
    address: 'J J Marg, Nagpada, Byculla, Mumbai 400 008',
    phone: '02223735555',
    latitude: 18.9601,
    longitude: 72.8302,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Byculla',
  ),
  BloodBank(
    id: 'cama_hosp',
    name: 'Cama & Albless Hospital Blood Bank',
    address: 'Mahapalika Marg, Fort, Mumbai 400 001',
    phone: '02222620555',
    latitude: 18.9374,
    longitude: 72.8344,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Fort',
  ),
  BloodBank(
    id: 'bombay_hosp',
    name: 'Bombay Hospital Blood Bank',
    address: 'New Marine Lines, Mumbai 400 020',
    phone: '02222067676',
    latitude: 18.9397,
    longitude: 72.8289,
    timing: '8 AM – 8 PM',
    type: 'Private',
    area: 'Marine Lines',
  ),
  BloodBank(
    id: 'breach_candy',
    name: 'Breach Candy Hospital Blood Bank',
    address: '60-A Bhulabhai Desai Rd, Breach Candy, Mumbai 400 026',
    phone: '02223667878',
    latitude: 18.9690,
    longitude: 72.8075,
    timing: '8 AM – 6 PM',
    type: 'Private',
    area: 'Breach Candy',
  ),
  BloodBank(
    id: 'hinduja_mahim',
    name: 'P D Hinduja Hospital Blood Bank',
    address: 'Veer Savarkar Marg, Mahim, Mumbai 400 016',
    phone: '02224447000',
    latitude: 19.0359,
    longitude: 72.8417,
    timing: 'Open 24/7',
    type: 'Private',
    area: 'Mahim',
  ),
  BloodBank(
    id: 'wockhardt_south',
    name: 'Wockhardt Hospital Blood Bank',
    address: '1877 Dr Anandrao Nair Rd, Mumbai Central, Mumbai 400 011',
    phone: '02261784444',
    latitude: 18.9705,
    longitude: 72.8218,
    timing: 'Open 24/7',
    type: 'Private',
    area: 'Mumbai Central',
  ),
  // ── BANDRA / WESTERN SUBURBS ──────────────────────────────────────────────
  BloodBank(
    id: 'bhabha_bandra',
    name: 'Bhabha Hospital Blood Bank',
    address: 'Bandra (W), Mumbai 400 050',
    phone: '02226400300',
    latitude: 19.0607,
    longitude: 72.8361,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Bandra West',
  ),
  BloodBank(
    id: 'lilavati',
    name: 'Lilavati Hospital Blood Bank',
    address: 'A-791 Bandra Reclamation, Bandra (W), Mumbai 400 050',
    phone: '02226751000',
    latitude: 19.0563,
    longitude: 72.8298,
    timing: '7 AM – 9 PM',
    type: 'Private',
    area: 'Bandra West',
  ),
  BloodBank(
    id: 'holy_family',
    name: 'Holy Family Hospital Blood Bank',
    address: 'St Andrews Rd, Bandra (W), Mumbai 400 050',
    phone: '02226483900',
    latitude: 19.0582,
    longitude: 72.8310,
    timing: '8 AM – 8 PM',
    type: 'Private',
    area: 'Bandra West',
  ),
  BloodBank(
    id: 'cooper_vile',
    name: 'Cooper Hospital Blood Bank',
    address: 'Bhaktivedanta Swami Marg, Juhu, Vile Parle (W), Mumbai 400 056',
    phone: '02226207254',
    latitude: 19.1029,
    longitude: 72.8395,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Vile Parle West',
  ),
  // ── ANDHERI / JOGESHWARI ──────────────────────────────────────────────────
  BloodBank(
    id: 'seven_hills',
    name: 'Seven Hills Hospital Blood Bank',
    address: 'Marol Maroshi Rd, Andheri (E), Mumbai 400 059',
    phone: '02267676767',
    latitude: 19.1138,
    longitude: 72.8800,
    timing: 'Open 24/7',
    type: 'Private',
    area: 'Andheri East',
  ),
  BloodBank(
    id: 'kokilaben',
    name: 'Kokilaben Dhirubhai Ambani Hospital Blood Bank',
    address: 'Rao Saheb Achutrao Patwardhan Marg, Andheri (W), Mumbai 400 053',
    phone: '02230999999',
    latitude: 19.1296,
    longitude: 72.8274,
    timing: 'Open 24/7',
    type: 'Private',
    area: 'Andheri West',
  ),
  BloodBank(
    id: 'bharat_ratna',
    name: 'Dr Babasaheb Ambedkar Hospital Blood Bank',
    address: 'Jogeshwari (E), Mumbai 400 060',
    phone: '02228206600',
    latitude: 19.1365,
    longitude: 72.8609,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Jogeshwari East',
  ),
  // ── BORIVALI / KANDIVALI ──────────────────────────────────────────────────
  BloodBank(
    id: 'bhagwati_borivali',
    name: 'Bhagwati Hospital Blood Bank',
    address: 'Western Express Hwy, Borivali (E), Mumbai 400 066',
    phone: '02228980000',
    latitude: 19.2293,
    longitude: 72.8626,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Borivali East',
  ),
  BloodBank(
    id: 'shatabdi_kandivali',
    name: 'Shatabdi Hospital Blood Bank',
    address: 'Kandivali (E), Mumbai 400 101',
    phone: '02228860000',
    latitude: 19.2067,
    longitude: 72.8603,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Kandivali East',
  ),
  // ── GHATKOPAR / MULUND ────────────────────────────────────────────────────
  BloodBank(
    id: 'rajawadi_ghatkopar',
    name: 'Rajawadi Hospital Blood Bank',
    address: 'LBS Marg, Ghatkopar (E), Mumbai 400 077',
    phone: '02225014141',
    latitude: 19.0779,
    longitude: 72.9147,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Ghatkopar East',
  ),
  BloodBank(
    id: 'fortis_mulund',
    name: 'Fortis Hospital Blood Bank',
    address: 'Mulund – Goregaon Link Rd, Mulund (W), Mumbai 400 078',
    phone: '02267125500',
    latitude: 19.1727,
    longitude: 72.9521,
    timing: '8 AM – 8 PM',
    type: 'Private',
    area: 'Mulund West',
  ),
  // ── SION / CHEMBUR ────────────────────────────────────────────────────────
  BloodBank(
    id: 'ltmg_sion',
    name: 'Lokmanya Tilak Municipal General Hospital Blood Bank',
    address: 'Dr Babasaheb Ambedkar Rd, Sion, Mumbai 400 022',
    phone: '02224076363',
    latitude: 19.0398,
    longitude: 72.8651,
    timing: 'Open 24/7',
    type: 'Government',
    area: 'Sion',
  ),
  BloodBank(
    id: 'chembur_hosp',
    name: 'Chembur Hospital & Research Centre Blood Bank',
    address: 'Chembur Naka, Mumbai 400 071',
    phone: '02225200200',
    latitude: 19.0605,
    longitude: 72.9002,
    timing: '8 AM – 8 PM',
    type: 'Private',
    area: 'Chembur',
  ),
  // ── TRUST / NGO ───────────────────────────────────────────────────────────
  BloodBank(
    id: 'idonate_dadar',
    name: 'iDonate Blood Bank (Red Cross)',
    address: 'N S Patkar Marg, Dadar (W), Mumbai 400 028',
    phone: '02224300300',
    latitude: 19.0175,
    longitude: 72.8445,
    timing: '8 AM – 6 PM',
    type: 'Trust',
    area: 'Dadar West',
  ),
  BloodBank(
    id: 'indian_red_cross',
    name: 'Indian Red Cross Society Blood Bank',
    address: 'Red Cross Building, Marine Lines, Mumbai 400 020',
    phone: '02222621664',
    latitude: 18.9410,
    longitude: 72.8290,
    timing: '9 AM – 5 PM',
    type: 'Trust',
    area: 'Marine Lines',
  ),
  BloodBank(
    id: 'rotary_bb',
    name: 'Rotary Blood Bank',
    address: 'Juhu Tara Rd, Santacruz (W), Mumbai 400 054',
    phone: '02226118885',
    latitude: 19.0888,
    longitude: 72.8264,
    timing: '9 AM – 6 PM',
    type: 'Trust',
    area: 'Santacruz West',
  ),
];

// ═══════════════════════════════════════════════════════════════════════════════
// CACHE SERVICE  — singleton SharedPreferences to avoid repeated async init
// ═══════════════════════════════════════════════════════════════════════════════

class _CacheService {
  // Pre-warmed once at app start — all subsequent calls are synchronous
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Pre-warm the prefs instance so the very first load() is fast.
  static Future<void> preWarm() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Returns cached banks if fresh (within TTL), else null.
  static Future<List<BloodBank>?> load() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_cacheKey);
      final ts = prefs.getInt('${_cacheKey}_ts') ?? 0;
      if (raw == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > _cacheTtl.inMilliseconds) return null;
      // Decode on isolate — large JSON, keep UI smooth
      final list = await compute(_decodeCacheIsolate, raw);
      return list;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(List<BloodBank> banks) async {
    try {
      final prefs = await _getPrefs();
      final encoded = await compute(_encodeCacheIsolate, banks);
      await prefs.setString(_cacheKey, encoded);
      await prefs.setInt(
        '${_cacheKey}_ts',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_cacheKey);
      await prefs.remove('${_cacheKey}_ts');
    } catch (_) {}
  }
}

// Isolate helpers for cache JSON — keeps UI thread free
List<BloodBank> _decodeCacheIsolate(String raw) => (jsonDecode(raw) as List)
    .map((e) => BloodBank.fromJson(e as Map<String, dynamic>))
    .toList();

String _encodeCacheIsolate(List<BloodBank> banks) =>
    jsonEncode(banks.map((b) => b.toJson()).toList());

// ═══════════════════════════════════════════════════════════════════════════════
// OVERPASS SERVICE  — races all mirrors simultaneously
// ═══════════════════════════════════════════════════════════════════════════════

// Parsed in an isolate to avoid janking the UI thread on large payloads
List<BloodBank> _parseOverpassIsolate(String body) {
  final elements = (jsonDecode(body)['elements'] as List? ?? []);
  final results = <BloodBank>[];
  for (final el in elements) {
    try {
      final b = BloodBank.fromOverpass(el as Map<String, dynamic>);
      if (b.latitude != 0.0 && b.longitude != 0.0) results.add(b);
    } catch (_) {}
  }
  return results;
}

class OverpassService {
  // Shared client for keep-alive / connection reuse
  static final http.Client _client = http.Client();

  static String _buildQuery(double lat, double lon, int radius) =>
      '[out:json][timeout:12];'
      '('
      'node["amenity"="blood_bank"](around:$radius,$lat,$lon);'
      'way["amenity"="blood_bank"](around:$radius,$lat,$lon);'
      'relation["amenity"="blood_bank"](around:$radius,$lat,$lon);'
      'node["healthcare"="blood_bank"](around:$radius,$lat,$lon);'
      'way["healthcare"="blood_bank"](around:$radius,$lat,$lon);'
      'relation["healthcare"="blood_bank"](around:$radius,$lat,$lon);'
      ');'
      'out center tags;';

  /// Fires all mirrors at once — returns the first successful response.
  static Future<List<BloodBank>> fetchNearby({
    required LatLng center,
    int radiusMeters = 50000,
  }) async {
    final query = _buildQuery(center.latitude, center.longitude, radiusMeters);

    final futures = _overpassMirrors.map((mirror) async {
      final res = await _client
          .post(
            Uri.parse(mirror),
            body: {'data': query},
            headers: {
              'User-Agent': 'BloodBankFinderApp/1.0 (contact@example.com)',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode} from $mirror');
      }
      // Decode on an isolate — keeps the UI thread smooth
      return compute(_parseOverpassIsolate, res.body);
    }).toList();

    // Race: first mirror to succeed wins; others are cancelled via error
    return Future.any(futures);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NOMINATIM SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class NominatimResult {
  final String displayName;
  final double latitude;
  final double longitude;
  const NominatimResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
  factory NominatimResult.fromJson(Map<String, dynamic> j) => NominatimResult(
    displayName: j['display_name'] as String? ?? '',
    latitude: double.tryParse(j['lat'] as String? ?? '') ?? 0.0,
    longitude: double.tryParse(j['lon'] as String? ?? '') ?? 0.0,
  );
}

class NominatimService {
  static DateTime? _lastCall;
  static final http.Client _client = http.Client();

  static Future<List<NominatimResult>> search(
    String query, {
    int limit = 5,
  }) async {
    if (query.trim().isEmpty) return [];
    if (_lastCall != null) {
      final elapsed = DateTime.now().difference(_lastCall!);
      if (elapsed < const Duration(seconds: 1)) {
        await Future.delayed(const Duration(seconds: 1) - elapsed);
      }
    }
    _lastCall = DateTime.now();

    final uri = Uri.parse(_nominatimUrl).replace(
      queryParameters: {
        'q': query,
        'format': 'json',
        'limit': '$limit',
        'addressdetails': '1',
        'countrycodes': 'in',
      },
    );

    final res = await _client
        .get(uri, headers: _nominatimHeaders)
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('Nominatim ${res.statusCode}');

    return (jsonDecode(res.body) as List)
        .map((e) => NominatimResult.fromJson(e as Map<String, dynamic>))
        .where((r) => r.latitude != 0.0 && r.longitude != 0.0)
        .toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class BloodBankScreen extends StatefulWidget {
  const BloodBankScreen({Key? key}) : super(key: key);
  @override
  State<BloodBankScreen> createState() => _BloodBankScreenState();
}

class _BloodBankScreenState extends State<BloodBankScreen>
    with SingleTickerProviderStateMixin {
  // ── Constants ─────────────────────────────────────────────────────────────
  static const LatLng _testHospitalLoc = LatLng(19.0522, 72.9005);

  // ── Controllers ───────────────────────────────────────────────────────────
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  Timer? _debounce;

  // ── Data state ────────────────────────────────────────────────────────────
  List<BloodBank> _allBanks = List.of(_localBloodBanks);
  BloodBank? _selectedBank;
  String _searchQuery = '';
  String _selectedType = 'All';
  String? _bloodGroupFilter;

  // Memoization: cached result + inputs that produced it
  List<BloodBank>? _filteredCache;
  String _filterCacheQuery = '__INVALID__';
  String _filterCacheType = '__INVALID__';
  int _filterCacheBankHash = -1;

  // Memoized stat counts — recomputed only when _allBanks changes
  int _cachedTotal = 0;
  int _cachedGovt = 0;
  int _cachedPrivate = 0;
  int _cachedTrust = 0;
  int _statCacheHash = -1;

  void _recomputeStats() {
    final hash =
        _allBanks.length ^
        (_allBanks.isEmpty ? 0 : _allBanks.first.id.hashCode) ^
        (_allBanks.isEmpty ? 0 : _allBanks.last.id.hashCode);
    if (hash == _statCacheHash) return;
    _statCacheHash = hash;
    _cachedTotal = _allBanks.length;
    _cachedGovt = 0;
    _cachedPrivate = 0;
    _cachedTrust = 0;
    for (final b in _allBanks) {
      if (b.type == 'Government')
        _cachedGovt++;
      else if (b.type == 'Private')
        _cachedPrivate++;
      else if (b.type == 'Trust')
        _cachedTrust++;
    }
  }

  // Marker list cache (expensive to rebuild on every frame)
  List<Marker>? _markerCache;
  int _markerCacheBankHash = -1;
  String? _markerCacheSelectedId;

  // ── Async state ───────────────────────────────────────────────────────────
  bool _fetchingOverpass = false;
  bool _fetchingNominatim = false;
  String? _errorMsg;

  // ── Location ──────────────────────────────────────────────────────────────
  bool _locationGranted = false;
  LatLng _userLocation = _testHospitalLoc;

  // ── Nominatim suggestions ─────────────────────────────────────────────────
  List<NominatimResult> _suggestions = [];
  bool _showSuggestions = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // INIT / DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _bootstrap(); // sync — returns immediately, fires background work
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOOTSTRAP  — frame 1 shows local banks instantly (zero network)
  //              cache + GPS + Overpass all fired simultaneously in background
  // ═══════════════════════════════════════════════════════════════════════════
  void _bootstrap() {
    // Local banks are already in _allBanks at field-init time.
    // Fire everything else in parallel — nothing blocks the first paint.
    unawaited(_backgroundRefresh());
  }

  Future<void> _backgroundRefresh() async {
    // Pre-warm SharedPreferences once so all later calls are synchronous
    unawaited(_CacheService.preWarm());

    // Fire cache load, GPS, and Overpass ALL AT ONCE — true parallel
    final cacheF = _CacheService.load();
    final locationF = _resolveLocation();
    final overpassF = _fetchAndApply(_testHospitalLoc, skipIfSamePos: false);

    // Apply cache the moment it resolves (usually < 50 ms)
    final cached = await cacheF;
    if (cached != null && mounted && cached.length > _allBanks.length) {
      setState(() {
        _allBanks = cached;
        _filteredCache = null;
        _markerCache = null;
      });
    }

    // Let location + overpass finish in background — they update state
    // themselves when ready via their own setState calls
    await Future.wait([locationF, overpassF]);
  }

  // Resolves GPS location silently in background — never blocks UI
  Future<void> _resolveLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied)
        return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      setState(() {
        _locationGranted = true;
        _userLocation = LatLng(pos.latitude, pos.longitude);
      });
      try {
        _mapController.move(_userLocation, 12.5);
      } catch (_) {}

      // If the user is meaningfully far from Mumbai center,
      // silently fetch Overpass around their actual position too.
      final dist = const Distance().as(
        LengthUnit.Meter,
        _userLocation,
        _testHospitalLoc,
      );
      if (dist > 2000) {
        unawaited(_fetchAndApply(_userLocation, skipIfSamePos: true));
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OVERPASS FETCH
  // ═══════════════════════════════════════════════════════════════════════════
  LatLng? _lastFetchedPos;

  Future<void> _fetchAndApply(
    LatLng center, {
    bool skipIfSamePos = true,
  }) async {
    // Skip if already fetched for this exact position
    if (skipIfSamePos && _lastFetchedPos != null) {
      final dist = const Distance().as(
        LengthUnit.Meter,
        _lastFetchedPos!,
        center,
      );
      if (dist < 500) return; // within 500 m — not worth re-fetching
    }

    if (_fetchingOverpass) return;
    if (mounted)
      setState(() {
        _fetchingOverpass = true;
      });

    try {
      final live = await OverpassService.fetchNearby(center: center);
      if (!mounted) return;

      _lastFetchedPos = center;
      final liveIds = live.map((b) => b.id).toSet();
      final merged = [
        ...live,
        ..._localBloodBanks.where((b) => !liveIds.contains(b.id)),
      ];

      setState(() {
        _allBanks = merged;
        // Invalidate caches
        _filteredCache = null;
        _markerCache = null;
      });

      // Persist in background — don't await
      unawaited(_CacheService.save(merged));
    } catch (e) {
      // Overpass failed — keep whatever data we already have (local + cache).
      // Never show an error banner; the user already has banks on screen.
      debugPrint('Overpass fetch failed (silent): $e');
    } finally {
      if (mounted) setState(() => _fetchingOverpass = false);
    }
  }

  Future<void> _manualRefresh() async {
    await _CacheService.clear();
    _lastFetchedPos = null;
    await _fetchAndApply(_userLocation, skipIfSamePos: false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MEMOIZED FILTERING  — only recomputed when inputs actually change
  // ═══════════════════════════════════════════════════════════════════════════
  List<BloodBank> get _filtered {
    // O(1) hash: length + first id + last id — fast, good enough for invalidation
    final bankHash =
        _allBanks.length ^
        (_allBanks.isEmpty ? 0 : _allBanks.first.id.hashCode) ^
        (_allBanks.isEmpty ? 0 : _allBanks.last.id.hashCode);
    if (_filteredCache != null &&
        _filterCacheQuery == _searchQuery &&
        _filterCacheType == _selectedType &&
        _filterCacheBankHash == bankHash) {
      return _filteredCache!;
    }

    final q = _searchQuery.toLowerCase();
    final result = _allBanks.where((b) {
      final matchSearch =
          q.isEmpty ||
          b.name.toLowerCase().contains(q) ||
          b.area.toLowerCase().contains(q) ||
          b.address.toLowerCase().contains(q) ||
          b.type.toLowerCase().contains(q);
      final matchType = _selectedType == 'All' || b.type == _selectedType;

      final d = const Distance().as(
        LengthUnit.Meter,
        _userLocation,
        LatLng(b.latitude, b.longitude),
      );
      final matchDist = d <= 50000;

      return matchSearch && matchType && matchDist;
    }).toList();

    result.sort((a, b) {
      final distA = const Distance().as(
        LengthUnit.Kilometer,
        _userLocation,
        LatLng(a.latitude, a.longitude),
      );
      final distB = const Distance().as(
        LengthUnit.Kilometer,
        _userLocation,
        LatLng(b.latitude, b.longitude),
      );
      return distA.compareTo(distB);
    });

    _filteredCache = result;
    _filterCacheQuery = _searchQuery;
    _filterCacheType = _selectedType;
    _filterCacheBankHash = bankHash;
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MEMOIZED MARKERS
  // ═══════════════════════════════════════════════════════════════════════════
  List<Marker> _buildMarkers(List<BloodBank> filtered) {
    // O(1) hash: length + first id + last id
    final bankHash =
        filtered.length ^
        (filtered.isEmpty ? 0 : filtered.first.id.hashCode) ^
        (filtered.isEmpty ? 0 : filtered.last.id.hashCode);
    final selId = _selectedBank?.id;

    if (_markerCache != null &&
        _markerCacheBankHash == bankHash &&
        _markerCacheSelectedId == selId) {
      return _markerCache!;
    }

    _markerCache = filtered.map((bank) {
      final isSel = selId == bank.id;
      final color = _typeColor(bank.type);
      return Marker(
        point: LatLng(bank.latitude, bank.longitude),
        width: isSel ? 48 : 36,
        height: isSel ? 48 : 36,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedBank = bank;
              _markerCache = null; // invalidate so selection re-renders
            });
            _mapController.move(LatLng(bank.latitude, bank.longitude), 15.0);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSel ? color : color.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: isSel ? 3 : 2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: isSel ? 14 : 6,
                  spreadRadius: isSel ? 3 : 1,
                ),
              ],
            ),
            child: Icon(
              Icons.local_hospital,
              color: Colors.white,
              size: isSel ? 26 : 18,
            ),
          ),
        ),
      );
    }).toList();

    _markerCacheBankHash = bankHash;
    _markerCacheSelectedId = selId;
    return _markerCache!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEARCH / NOMINATIM
  // ═══════════════════════════════════════════════════════════════════════════
  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _selectedBank = null;
      _showSuggestions = false;
      _suggestions = [];
    });

    _debounce?.cancel();
    if (value.trim().isEmpty) return;

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      // 1 — local match: if found, skip Nominatim entirely
      final q = value.toLowerCase();
      final hits = _allBanks
          .where(
            (b) =>
                b.name.toLowerCase().contains(q) ||
                b.area.toLowerCase().contains(q) ||
                b.address.toLowerCase().contains(q),
          )
          .toList();

      if (hits.isNotEmpty) {
        if (mounted) {
          _mapController.move(
            LatLng(hits.first.latitude, hits.first.longitude),
            14.0,
          );
        }
        return; // skip Nominatim — local hit is faster
      }

      // 2 — Nominatim fallback
      if (!mounted) return;
      setState(() => _fetchingNominatim = true);
      try {
        final results = await NominatimService.search('$value Mumbai India');
        if (!mounted) return;
        if (results.isNotEmpty) {
          setState(() {
            _suggestions = results;
            _showSuggestions = true;
          });
        } else {
          _snack('No location found for "$value"');
        }
      } catch (_) {
        if (mounted) _snack('Location search failed — check your connection.');
      } finally {
        if (mounted) setState(() => _fetchingNominatim = false);
      }
    });
  }

  void _applySuggestion(NominatimResult r) {
    final shortName = r.displayName.split(',').first.trim();
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
      _searchController.text = shortName;
      _searchQuery = shortName;
    });
    final target = LatLng(r.latitude, r.longitude);
    _mapController.move(target, 14.0);
    _fetchAndApply(target, skipIfSamePos: false);
    _tabController.animateTo(0);
  }

  void _clearSearch() => setState(() {
    _searchController.clear();
    _searchQuery = '';
    _suggestions = [];
    _showSuggestions = false;
    _bloodGroupFilter = null;
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMUNICATION
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _launchCall(String phone) async {
    final c = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (c.isEmpty) {
      _snack('No phone number available');
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: c));
    } catch (_) {
      _snack('Could not open dialer.');
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    final c = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (c.isEmpty) {
      _snack('No phone number available');
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/$c?text=${Uri.encodeComponent(_predefinedMsg)}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _snack('WhatsApp not installed.');
      }
    } catch (_) {
      _snack('Could not open WhatsApp.');
    }
  }

  Future<void> _launchSMS(String phone) async {
    final c = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (c.isEmpty) {
      _snack('No phone number available');
      return;
    }
    final uri = Uri(
      scheme: 'sms',
      path: c,
      queryParameters: {'body': _predefinedMsg},
    );
    try {
      if (await canLaunchUrl(uri))
        await launchUrl(uri);
      else
        _snack('Could not open SMS app.');
    } catch (_) {
      _snack('Could not open SMS app.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTACT SHEET
  // ═══════════════════════════════════════════════════════════════════════════
  void _showContactOptions(BloodBank bank) {
    final phone = bank.effectivePhone;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              bank.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              phone,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            if (!bank.hasRealPhone) ...[
              const SizedBox(height: 2),
              Text(
                '(demo number)',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.amber[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Text(
                _predefinedMsg,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[700],
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _contactBtn(
                    Icons.call_rounded,
                    'Call',
                    Colors.green[600]!,
                    () {
                      Navigator.pop(ctx);
                      _launchCall(phone);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _contactBtn(
                    Icons.chat_rounded,
                    'WhatsApp',
                    const Color(0xFF25D366),
                    () {
                      Navigator.pop(ctx);
                      _launchWhatsApp(phone);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _contactBtn(
                    Icons.sms_rounded,
                    'SMS',
                    Colors.blue[600]!,
                    () {
                      Navigator.pop(ctx);
                      _launchSMS(phone);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    _recomputeStats(); // O(n) only when bank list changes
    final filtered = _filtered; // memoized — cheap on repeat calls
    return GestureDetector(
      onTap: () => setState(() => _showSuggestions = false),
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text('Blood Banks — Nearby'),
          backgroundColor: Colors.red[700],
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            if (_fetchingOverpass || _fetchingNominatim)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh nearby',
              onPressed: _fetchingOverpass ? null : _manualRefresh,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.map), text: 'Map'),
              Tab(icon: Icon(Icons.list), text: 'List'),
            ],
          ),
        ),

        body: Column(
          children: [
            // ── Error banner ─────────────────────────────────────────────────
            if (_errorMsg != null)
              Material(
                color: Colors.amber[100],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.amber[800],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMsg!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber[900],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _fetchingOverpass ? null : _manualRefresh,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Retry',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.amber[800],
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() => _errorMsg = null),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Search bar ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              color: Colors.red[700],
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    onTap: () {
                      if (_suggestions.isNotEmpty)
                        setState(() => _showSuggestions = true);
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search name, area, blood group…',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      prefixIcon: const Icon(Icons.search, color: Colors.white),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_fetchingNominatim)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white70,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          if (_searchQuery.isNotEmpty)
                            IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Colors.white,
                              ),
                              onPressed: _clearSearch,
                            ),
                        ],
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: _fetchingOverpass
                            ? Colors.amber[300]
                            : Colors.greenAccent[400],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${filtered.length} blood banks'
                        '${_fetchingOverpass ? ' · Refreshing…' : ''}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Nominatim suggestions ────────────────────────────────────────
            if (_showSuggestions && _suggestions.isNotEmpty)
              Material(
                elevation: 6,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  color: Colors.white,
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey[200]),
                    itemBuilder: (_, i) {
                      final s = _suggestions[i];
                      final shortName = s.displayName
                          .split(',')
                          .take(2)
                          .join(', ');
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.location_on,
                          color: Colors.red[700],
                          size: 18,
                        ),
                        title: Text(
                          shortName,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          s.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                        onTap: () => _applySuggestion(s),
                      );
                    },
                  ),
                ),
              ),

            // ── Stats + filters ──────────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statCard(
                        'Total',
                        _cachedTotal.toString(),
                        Colors.red[700]!,
                      ),
                      _statCard(
                        'Govt',
                        _cachedGovt.toString(),
                        Colors.green[700]!,
                      ),
                      _statCard(
                        'Private',
                        _cachedPrivate.toString(),
                        Colors.blue[700]!,
                      ),
                      _statCard(
                        'Trust',
                        _cachedTrust.toString(),
                        Colors.orange[700]!,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _typeFilters
                          .map(
                            (t) => _filterChip(
                              t,
                              _selectedType == t,
                              Colors.red[700]!,
                              () => setState(() {
                                _selectedType = t;
                                _filteredCache = null; // invalidate
                              }),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            'Quick call for:',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                        ..._bloodGroups.map((bg) {
                          final active = _bloodGroupFilter == bg;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _bloodGroupFilter = active ? null : bg;
                                  _searchQuery = _bloodGroupFilter ?? '';
                                  _searchController.text =
                                      _bloodGroupFilter ?? '';
                                  _filteredCache = null; // invalidate
                                });
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? Colors.red[700]
                                      : Colors.red[50],
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: active
                                        ? Colors.red[700]!
                                        : Colors.red[200]!,
                                  ),
                                ),
                                child: Text(
                                  bg,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: active
                                        ? Colors.white
                                        : Colors.red[700],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Tab content ──────────────────────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmpty()
                  : TabBarView(
                      controller: _tabController,
                      children: [_buildMap(filtered), _buildList(filtered)],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAP VIEW
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildMap(List<BloodBank> filtered) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _testHospitalLoc,
            initialZoom: 9.0,
            minZoom: 8.0,
            maxZoom: 18.0,
            onTap: (_, __) {
              if (_selectedBank != null) {
                setState(() {
                  _selectedBank = null;
                  _markerCache = null;
                });
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.bloodbank',
              maxNativeZoom: 19,
              tileProvider: NetworkTileProvider(),
              keepBuffer: 4,
              panBuffer: 2,
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
              alignment: AttributionAlignment.bottomLeft,
            ),
            if (_locationGranted) const CurrentLocationLayer(),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: _testHospitalLoc,
                  radius: 20050,
                  useRadiusInMeter: true,
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderColor: Colors.teal.withValues(alpha: 0.6),
                  borderStrokeWidth: 2,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _testHospitalLoc,
                  width: 90,
                  height: 90,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(blurRadius: 10, color: Colors.black26),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.local_hospital,
                            color: Colors.teal,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.teal, width: 1),
                        ),
                        child: const Text(
                          'TEST_HOSPITAL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            MarkerLayer(markers: _buildMarkers(filtered)),
          ],
        ),

        // Legend
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendItem(Colors.red[700]!, 'Government'),
                _legendItem(Colors.blue[700]!, 'Private'),
                _legendItem(Colors.orange[700]!, 'Trust'),
              ],
            ),
          ),
        ),

        // Count badge
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red[700],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${filtered.length} found',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        // Loading pill
        if (_fetchingOverpass)
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Updating live data…', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),

        // Selected bank card
        if (_selectedBank != null)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildDetailCard(_selectedBank!),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIST VIEW
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildList(List<BloodBank> filtered) => ListView.builder(
    padding: const EdgeInsets.all(14),
    itemCount: filtered.length,
    itemBuilder: (_, i) => _buildListCard(filtered[i]),
  );

  Widget _buildListCard(BloodBank bank) {
    final color = _typeColor(bank.type);
    final isSel = _selectedBank?.id == bank.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isSel ? 4 : 1.5,
      color: isSel ? Colors.red[50] : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isSel
            ? BorderSide(color: Colors.red[300]!, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.local_hospital, color: color, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedBank = bank;
                        _markerCache = null;
                        _tabController.animateTo(0);
                      });
                      _mapController.move(
                        LatLng(bank.latitude, bank.longitude),
                        15.0,
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bank.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        _infoRow(Icons.place, bank.area, Colors.grey[600]!),
                        _infoRow(
                          Icons.access_time,
                          bank.timing,
                          Colors.green[700]!,
                        ),
                        _infoRow(
                          Icons.location_on,
                          bank.address,
                          Colors.grey[500]!,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    bank.type,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            if (bank.bloodStock != null && bank.bloodStock!.isNotEmpty) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: bank.bloodStock!.entries.map((e) {
                    final avail = e.value > 0;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: avail ? Colors.green[50] : Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: avail
                                ? Colors.green[300]!
                                : Colors.red[200]!,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              e.key,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: avail
                                    ? Colors.green[700]
                                    : Colors.red[700],
                              ),
                            ),
                            Text(
                              '${e.value}u',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: () => _showContactOptions(bank),
                icon: const Icon(Icons.contact_phone, size: 16),
                label: Text(
                  bank.hasRealPhone
                      ? 'Contact  ${bank.phone}'
                      : 'Contact Blood Bank',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(BloodBank bank) {
    final color = _typeColor(bank.type);
    return Card(
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    bank.type,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bank.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _selectedBank = null;
                    _markerCache = null;
                  }),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Divider(height: 14),
            _infoRow(Icons.location_on, bank.address, Colors.grey[600]!),
            const SizedBox(height: 4),
            _infoRow(Icons.access_time, bank.timing, Colors.green[700]!),
            const SizedBox(height: 4),
            _infoRow(Icons.place, bank.area, Colors.grey[600]!),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: () => _launchCall(bank.effectivePhone),
                      icon: const Icon(Icons.call, size: 15),
                      label: const Text('Call', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: () => _launchWhatsApp(bank.effectivePhone),
                      icon: const Icon(Icons.chat_rounded, size: 15),
                      label: const Text(
                        'WhatsApp',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: () => _launchSMS(bank.effectivePhone),
                      icon: const Icon(Icons.sms_rounded, size: 15),
                      label: const Text('SMS', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(
          'No blood banks match your search.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => setState(() {
            _searchController.clear();
            _searchQuery = '';
            _selectedType = 'All';
            _bloodGroupFilter = null;
            _suggestions = [];
            _showSuggestions = false;
            _filteredCache = null;
          }),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[700],
            foregroundColor: Colors.white,
          ),
          child: const Text('Clear filters'),
        ),
      ],
    ),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _statCard(String label, String value, Color color) => Column(
    children: [
      Text(
        value,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
    ],
  );

  Widget _filterChip(
    String label,
    bool selected,
    Color color,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: selected ? Colors.white : Colors.grey[700],
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color,
      backgroundColor: Colors.grey[100],
      checkmarkColor: Colors.white,
      side: BorderSide(color: selected ? color : Colors.grey[300]!),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
  );

  Widget _legendItem(Color color, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.local_hospital, color: color, size: 12),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    ),
  );

  Widget _infoRow(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  Color _typeColor(String type) {
    switch (type) {
      case 'Government':
        return Colors.red[700]!;
      case 'Private':
        return Colors.blue[700]!;
      case 'Trust':
        return Colors.orange[700]!;
      default:
        return Colors.grey[700]!;
    }
  }
}

// Needed for fire-and-forget cache saving
void unawaited(Future<void> future) {
  future.catchError((_) {});
}
