// lib/screens/doctor/doctor_dashboard.dart
//
// SUMMARY SECTION — queries two existing tables directly. No RPCs. No new tables.
//
//  ┌─────────────────────────────────────────────────────────────────────────┐
//  │  PATIENTS TREATED TODAY                                                  │
//  │  Source: patient_treatments table                                        │
//  │  Query:  SELECT COUNT(*) WHERE doctor_id = X                            │
//  │          AND completed_at >= today 00:00 AND <= today 23:59             │
//  │  Works because HospitalNavigationScreen already inserts a row here      │
//  │  every time a patient taps "Mark Test as Completed".                    │
//  │  Patient A done → 1. Patient B done → 2. Patient C done → 3. etc.      │
//  ├─────────────────────────────────────────────────────────────────────────┤
//  │  TIME SPENT TODAY                                                        │
//  │  Source: doctor_room_sessions table                                      │
//  │  Query:  SELECT start_time, end_time WHERE doctor_id = X                │
//  │          AND session_date = today                                        │
//  │  Dart sums: (end_time ?? now) - start_time for every session row.       │
//  │  Active session (end_time IS NULL) → counted up to right now.           │
//  └─────────────────────────────────────────────────────────────────────────┘
//
//  Both values update via Supabase Realtime:
//    • patient_treatments INSERT  → _patientsToday ticks up
//    • doctor_room_sessions ANY   → _todayMinutes recalculates

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/doctor_service.dart';
import 'room_selection_screen.dart';
import 'patient_list_screen_v3.dart';
import 'doctor_analysis_screen.dart';
import 'doctor_settings_screen.dart';

class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({Key? key}) : super(key: key);

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  final DoctorService _doctorService = DoctorService();
  final SupabaseClient _supabase = Supabase.instance.client;

  int _currentTabIndex = 0;
  int _analyticsKey = 0;

  Map<String, dynamic>? _doctorProfile;
  Map<String, dynamic>? _activeSession;
  bool _isLoading = true;

  // ── The two summary numbers ───────────────────────────────────────────────
  int _patientsToday = 0; // from patient_treatments
  int _todayMinutes  = 0; // from doctor_room_sessions

  // ── Realtime channels ─────────────────────────────────────────────────────
  RealtimeChannel? _treatmentsChannel; // watches patient_treatments INSERTs
  RealtimeChannel? _sessionsChannel;   // watches doctor_room_sessions changes

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _treatmentsChannel?.unsubscribe();
    _sessionsChannel?.unsubscribe();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DATA FETCHING
  // ══════════════════════════════════════════════════════════════════════════

  /// Counts rows in patient_treatments for this doctor today.
  /// One row = one patient test completed = +1 to the count.
  Future<int> _fetchPatientsToday(String doctorId) async {
    try {
      final today = _todayStr();
      final rows = await _supabase
          .from('patient_treatments')
          .select('id')
          .eq('doctor_id', doctorId)
          .gte('completed_at', '${today}T00:00:00.000')
          .lte('completed_at', '${today}T23:59:59.999');
      return (rows as List).length;
    } catch (e) {
      debugPrint('❌ [Dashboard] _fetchPatientsToday: $e');
      return 0;
    }
  }

  /// Sums time across all doctor_room_sessions rows for today.
  /// For ended sessions:  end_time   - start_time
  /// For active sessions: DateTime.now() - start_time
  /// Result is returned in whole minutes.
  Future<int> _fetchTodayMinutes(String doctorId) async {
    try {
      final today = _todayStr();
      final rows = await _supabase
          .from('doctor_room_sessions')
          .select('start_time, end_time, status')
          .eq('doctor_id', doctorId)
          .eq('session_date', today);

      if (rows == null || (rows as List).isEmpty) return 0;

      int totalMinutes = 0;
      final now = DateTime.now();

      for (final row in rows as List) {
        final startRaw = row['start_time'];
        if (startRaw == null) continue;

        // start_time may be a full ISO timestamp or a time-only string.
        // We normalise to a DateTime either way.
        DateTime start;
        try {
          // Try full ISO first (e.g. "2025-04-22T09:00:00+00:00")
          start = DateTime.parse(startRaw.toString()).toLocal();
        } catch (_) {
          // Fallback: time-only string (e.g. "09:00:00") → attach today's date
          start = DateTime.parse('${today}T${startRaw}').toLocal();
        }

        final endRaw  = row['end_time'];
        DateTime end;
        if (endRaw != null) {
          try {
            end = DateTime.parse(endRaw.toString()).toLocal();
          } catch (_) {
            end = DateTime.parse('${today}T${endRaw}').toLocal();
          }
        } else {
          // Session still active — count up to right now
          end = now;
        }

        final diff = end.difference(start).inMinutes;
        if (diff > 0) totalMinutes += diff;
      }

      return totalMinutes;
    } catch (e) {
      debugPrint('❌ [Dashboard] _fetchTodayMinutes: $e');
      return 0;
    }
  }

  // ── Main load ─────────────────────────────────────────────────────────────

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      _doctorProfile = await _doctorService.getCurrentDoctor();

      if (_doctorProfile != null) {
        final doctorId = _doctorProfile!['id'] as String;

        // Run both summary queries in parallel for speed
        final results = await Future.wait([
          _fetchPatientsToday(doctorId),
          _fetchTodayMinutes(doctorId),
          _doctorService.getActiveSession(doctorId),
        ]);

        _patientsToday = results[0] as int;
        _todayMinutes  = results[1] as int;
        _activeSession = results[2] as Map<String, dynamic>?;

        // Start realtime listeners after the first fetch
        _subscribeRealtime(doctorId);
      }
    } catch (e) {
      debugPrint('❌ [Dashboard] _loadDashboardData: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REALTIME SUBSCRIPTIONS
  // ══════════════════════════════════════════════════════════════════════════

  void _subscribeRealtime(String doctorId) {
    // ── Channel 1: patient_treatments INSERT ──────────────────────────────
    // Fires every time HospitalNavigationScreen inserts a treatment row,
    // i.e. every time a patient completes a test in this doctor's room.
    _treatmentsChannel?.unsubscribe();
    _treatmentsChannel = _supabase
        .channel('dash_treatments_$doctorId')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'patient_treatments',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'doctor_id',
        value: doctorId,
      ),
      callback: (_) async {
        debugPrint('🔔 [Dashboard] New treatment — refreshing count');
        final count = await _fetchPatientsToday(doctorId);
        if (mounted) setState(() => _patientsToday = count);
      },
    )
        .subscribe();

    // ── Channel 2: doctor_room_sessions INSERT/UPDATE ─────────────────────
    // Fires when a new session starts (INSERT) or an active session ends
    // (UPDATE sets end_time). Re-calculates the total minutes.
    _sessionsChannel?.unsubscribe();
    _sessionsChannel = _supabase
        .channel('dash_sessions_$doctorId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'doctor_room_sessions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'doctor_id',
        value: doctorId,
      ),
      callback: (_) async {
        debugPrint('🔔 [Dashboard] Session changed — refreshing time');
        final minutes = await _fetchTodayMinutes(doctorId);
        if (mounted) setState(() => _todayMinutes = minutes);
      },
    )
        .subscribe();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NAVIGATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _handleStartWorking() async {
    final selectedRoom = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const RoomSelectionScreen()),
    );
    if (selectedRoom != null && mounted) {
      // ── START SESSION in DB so _getDoctorIdForRoom() can find this doctor ──
      if (_doctorProfile != null) {
        final doctorId   = _doctorProfile!['id'] as String;
        final roomNumber = selectedRoom['room_number'] as String;
        await _doctorService.startSession(doctorId, roomNumber);
        print('✅ Session started: doctor=$doctorId room=$roomNumber');
      }

      await _loadDashboardData();
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PatientListScreen(
              roomNumber: selectedRoom['room_number'],
              roomName: selectedRoom['room_number'],
              floor: selectedRoom['floor'] ?? '',
            ),
          ),
        );
        if (mounted) _loadDashboardData();
      }
    }
  }

  Future<void> _handleChangeRoom() async {
    if (_activeSession != null) {
      await _doctorService.endSession(_activeSession!['id']);
    }
    await _handleStartWorking();
  }

  Future<void> _handleContinueWorking() async {
    if (_activeSession == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientListScreen(
          roomNumber: _activeSession!['room_number'],
          roomName: _activeSession!['room_number'],
          floor: '',
        ),
      ),
    );
    if (mounted) _loadDashboardData();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('PathCare',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DoctorSettingsScreen()),
            ).then((_) => _loadDashboardData()),
          ),
        ],
      ),
      body: _currentTabIndex == 0 ? _buildHomeTab() : _buildAnalyticsTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) {
          setState(() {
            _currentTabIndex = index;
            if (index == 1) _analyticsKey++;
          });
          if (index == 0) _loadDashboardData();
        },
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HOME TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildHomeTab() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 24),
            _buildCurrentRoomStatus(),
            const SizedBox(height: 24),
            _buildSummaryStats(),       // ← the fixed section
            const SizedBox(height: 24),
            _buildGoToAnalyticsBanner(),
            const SizedBox(height: 24),
            if (_activeSession == null) _buildQuickTip(),
          ],
        ),
      ),
    );
  }

  // ── Profile header ────────────────────────────────────────────────────────

  Widget _buildProfileHeader() {
    final doctorName = (_doctorProfile?['full_name'] as String?) ??
        (_doctorProfile?['name'] as String?) ??
        'Doctor';
    final specialization = (_doctorProfile?['specialization'] as String?) ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, size: 30, color: Colors.blue.shade700),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '👨‍⚕️ Dr. $doctorName',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (specialization.isNotEmpty)
                  Text(
                    specialization,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Room status card ──────────────────────────────────────────────────────

  Widget _buildCurrentRoomStatus() {
    final active = _activeSession != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: active
              ? [Colors.green.shade400, Colors.green.shade600]
              : [Colors.grey.shade400, Colors.grey.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (active ? Colors.green : Colors.grey).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active) ...[
            Row(children: [
              const Icon(Icons.meeting_room, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                'Room ${_activeSession!['room_number']}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'Session started at ${_formatSessionTime(_activeSession!['start_time'])}',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.9), fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _handleContinueWorking,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Continue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _handleChangeRoom,
                  icon: const Icon(Icons.swap_horiz, color: Colors.white),
                  label: const Text('Change Room',
                      style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
          ] else ...[
            const Text(
              'Not Working',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a room to start your day',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.9), fontSize: 14),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _handleStartWorking,
                icon: const Icon(Icons.local_hospital),
                label: const Text('Start Working'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── SUMMARY STATS ─────────────────────────────────────────────────────────

  Widget _buildSummaryStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with live pulse dot when an active session exists
        Row(children: [
          const Text(
            '📊 TODAY\'S SUMMARY',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2),
          ),
          if (_activeSession != null) ...[
            const SizedBox(width: 8),
            _PulseDot(color: Colors.green.shade500),
            const SizedBox(width: 4),
            Text('Live',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600)),
          ],
        ]),
        const SizedBox(height: 12),
        Row(
          children: [
            // ── Card 1: Time spent in rooms today ──────────────────────────
            Expanded(
              child: _StatCard(
                icon: Icons.access_time_rounded,
                iconColor: Colors.orange,
                // Summed from doctor_room_sessions rows today.
                // Active session counts up to NOW() — pull-to-refresh to see latest.
                value: _formatMinutes(_todayMinutes),
                label: 'Time Today',
                subtitle: 'In rooms',
              ),
            ),
            const SizedBox(width: 12),
            // ── Card 2: Patients treated today ─────────────────────────────
            Expanded(
              child: _StatCard(
                icon: Icons.people_alt_rounded,
                iconColor: Colors.blue,
                // Counted from patient_treatments rows today.
                // Increments instantly when a patient completes a test.
                value: '$_patientsToday',
                label: 'Treated Today',
                subtitle: 'Patients',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Analytics banner ──────────────────────────────────────────────────────

  Widget _buildGoToAnalyticsBanner() {
    return GestureDetector(
      onTap: () => setState(() => _currentTabIndex = 1),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo.shade500, Colors.indigo.shade800],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.indigo.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bar_chart_rounded,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Performance Analytics',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Today · Monthly · Yearly · All-time',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white60, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickTip() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Select your first room to begin seeing patients today',
              style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANALYTICS TAB — unchanged
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildAnalyticsTab() {
    if (_isLoading || _doctorProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return DoctorAnalysisScreen(
      key: ValueKey(_analyticsKey),
      doctorProfile: _doctorProfile!,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String _formatMinutes(int minutes) {
    if (minutes <= 0) return '0 min';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  String _formatSessionTime(String? timestamp) {
    if (timestamp == null) return '--:--';
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    } catch (_) {
      return '--:--';
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String subtitle;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
          Text(subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

/// Animated pulsing dot shown next to "Live" label when session is active.
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.25, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 7,
      height: 7,
      decoration:
      BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}