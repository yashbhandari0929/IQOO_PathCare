// lib/screens/doctor/doctor_analysis_screen.dart
//
// Analytics screen: Today / Month / Year patient counts + bar charts.
//
// ✅ NEW: Subscribes to Supabase Realtime on `patient_treatments` filtered by
//        doctor_id. Every time a patient completes a test in the doctor's room,
//        a new row is inserted and the Today count increments INSTANTLY — no
//        polling, no manual refresh needed.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorAnalysisScreen extends StatefulWidget {
  final Map<String, dynamic> doctorProfile;

  /// Optional live count passed from PatientListScreen.
  /// When non-null and greater than the DB count, shown with a live badge.
  final int? liveCompletedToday;

  const DoctorAnalysisScreen({
    Key? key,
    required this.doctorProfile,
    this.liveCompletedToday,
  }) : super(key: key);

  @override
  State<DoctorAnalysisScreen> createState() => _DoctorAnalysisScreenState();
}

class _DoctorAnalysisScreenState extends State<DoctorAnalysisScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  // Doctor info — populated instantly from widget.doctorProfile in initState()
  String? _doctorId;
  bool _initLoading = true;
  String? _initError;

  // ── Day ───────────────────────────────────────────────────────────────────
  int _dayCount = 0;
  bool _dayLoading = false;
  bool _isLiveCount = false;
  DateTime _selectedDate = DateTime.now();

  // ── Month ─────────────────────────────────────────────────────────────────
  int _monthCount = 0;
  List<_DayBar> _monthBars = [];
  bool _monthLoading = false;
  int _selMonth = DateTime.now().month;
  int _selMonthYear = DateTime.now().year;

  // ── Year ──────────────────────────────────────────────────────────────────
  int _yearCount = 0;
  List<_MonthBar> _yearBars = [];
  bool _yearLoading = false;
  int _selYear = DateTime.now().year;

  // ✅ NEW: Realtime channel for patient_treatments
  RealtimeChannel? _treatmentChannel;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _bootstrap();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging || _doctorId == null) return;
    switch (_tabController.index) {
      case 0:
        _loadDay();
        break;
      case 1:
        _loadMonth();
        break;
      case 2:
        _loadYear();
        break;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    // ✅ Unsubscribe from Realtime on dispose
    _treatmentChannel?.unsubscribe();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ NEW: Subscribe to patient_treatments for this doctor
  //
  // Every INSERT into patient_treatments with matching doctor_id triggers
  // an immediate Today count refresh. This means as soon as any patient
  // clicks "I've Completed My Tests" in that room, this screen updates.
  // ─────────────────────────────────────────────────────────────────────────
  void _subscribeTreatmentUpdates(String doctorId) {
    _treatmentChannel?.unsubscribe();

    _treatmentChannel = _supabase
        .channel('treatments_doctor_$doctorId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'patient_treatments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'doctor_id',
            value: doctorId,
          ),
          callback: (payload) {
            debugPrint(
              '[DoctorAnalysis] ✅ New treatment recorded — refreshing Today count',
            );
            // Only refresh the day count — month/year can wait for manual tab switch
            _loadDay();
          },
        )
        .subscribe((status, [error]) {
          if (error != null) {
            debugPrint('[DoctorAnalysis] ⚠️ Realtime error: $error');
          } else {
            debugPrint('[DoctorAnalysis] Realtime subscribed: $status');
          }
        });
  }

  // ── Bootstrap ─────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() {
      _initLoading = true;
      _initError = null;
    });
    try {
      final profile = widget.doctorProfile;

      final id = profile['id'] as String?;
      if (id == null || id.isEmpty) {
        throw Exception(
          'Doctor profile is missing an "id" field.\n'
          'Make sure getCurrentDoctor() returns the full doctors row.',
        );
      }

      _doctorId = id;

      if (!mounted) return;
      setState(() => _initLoading = false);

      // ✅ Start listening BEFORE loading so no event is missed
      _subscribeTreatmentUpdates(id);

      // Load all three tabs in parallel
      await Future.wait([_loadDay(), _loadMonth(), _loadYear()]);

      _applyLiveCountIfHigher();
    } catch (e) {
      debugPrint('[DoctorAnalysis] bootstrap error: $e');
      if (mounted) {
        setState(() {
          _initLoading = false;
          _initError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // ── Fetchers ──────────────────────────────────────────────────────────────

  Future<void> _loadDay() async {
    if (_doctorId == null || !mounted) return;
    setState(() => _dayLoading = true);
    try {
      // ✅ Query patient_treatments directly for an accurate today count.
      // This is the source of truth now — treatments are written at the
      // exact moment the patient taps "I've Completed My Tests".
      final today = _fmtDate(_selectedDate);
      final rows = await _supabase
          .from('patient_treatments')
          .select('id')
          .eq('doctor_id', _doctorId!)
          .gte('completed_at', '${today}T00:00:00')
          .lte('completed_at', '${today}T23:59:59');

      final count = (rows as List?)?.length ?? 0;

      if (mounted) {
        setState(() {
          _dayCount = count;
          _dayLoading = false;
          _isLiveCount = false;
        });
        _applyLiveCountIfHigher();
      }
    } catch (e) {
      // Fallback to original RPC if patient_treatments table doesn't exist yet
      debugPrint(
        '[DoctorAnalysis] patient_treatments query failed, falling back to RPC: $e',
      );
      try {
        final result = await _supabase.rpc(
          'get_doctor_patients_on_date',
          params: {'p_doctor_id': _doctorId, 'p_date': _fmtDate(_selectedDate)},
        );
        if (mounted) {
          setState(() {
            _dayCount = _toInt(result);
            _dayLoading = false;
            _isLiveCount = false;
          });
          _applyLiveCountIfHigher();
        }
      } catch (rpcError) {
        debugPrint('[DoctorAnalysis] day RPC error: $rpcError');
        if (mounted) setState(() => _dayLoading = false);
      }
    }
  }

  /// If [widget.liveCompletedToday] is set and we are viewing today's date,
  /// show the larger of (DB count, live count) with a live badge.
  void _applyLiveCountIfHigher() {
    if (!mounted) return;
    final live = widget.liveCompletedToday;
    if (live == null || !_isToday(_selectedDate)) return;
    if (live > _dayCount) {
      setState(() {
        _dayCount = live;
        _isLiveCount = true;
      });
    }
  }

  Future<void> _loadMonth() async {
    if (_doctorId == null || !mounted) return;
    setState(() => _monthLoading = true);
    try {
      final results = await Future.wait([
        _supabase.rpc(
          'get_doctor_month_analytics',
          params: {
            'p_doctor_id': _doctorId,
            'p_year': _selMonthYear,
            'p_month': _selMonth,
          },
        ),
        _supabase.rpc(
          'get_doctor_daily_breakdown',
          params: {
            'p_doctor_id': _doctorId,
            'p_year': _selMonthYear,
            'p_month': _selMonth,
          },
        ),
      ]);

      final totRow = _firstRow(results[0]);
      final bars = _toList(results[1])
          .map(
            (r) => _DayBar(
              day: _toInt(r['day_number']),
              count: _toInt(r['patients_count']),
            ),
          )
          .toList();

      if (mounted) {
        setState(() {
          _monthCount = _toInt(totRow['patients_attended']);
          _monthBars = bars;
          _monthLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[DoctorAnalysis] month error: $e');
      if (mounted) setState(() => _monthLoading = false);
    }
  }

  Future<void> _loadYear() async {
    if (_doctorId == null || !mounted) return;
    setState(() => _yearLoading = true);
    try {
      final results = await Future.wait([
        _supabase.rpc(
          'get_doctor_year_analytics',
          params: {'p_doctor_id': _doctorId, 'p_year': _selYear},
        ),
        _supabase.rpc(
          'get_doctor_monthly_breakdown',
          params: {'p_doctor_id': _doctorId, 'p_year': _selYear},
        ),
      ]);

      final totRow = _firstRow(results[0]);
      final rawBars = _toList(results[1]);
      final Map<int, int> monthMap = {
        for (var r in rawBars)
          _toInt(r['month_number']): _toInt(r['patients_count']),
      };
      final fullBars = List.generate(
        12,
        (i) => _MonthBar(month: i + 1, count: monthMap[i + 1] ?? 0),
      );

      if (mounted) {
        setState(() {
          _yearCount = _toInt(totRow['patients_attended']);
          _yearBars = fullBars;
          _yearLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[DoctorAnalysis] year error: $e');
      if (mounted) setState(() => _yearLoading = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtDisplay(DateTime d) =>
      '${d.day} ${_kMonths[d.month - 1]} ${d.year}';

  int _toInt(dynamic v) => (v as num?)?.toInt() ?? 0;

  Map<String, dynamic> _firstRow(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map<String, dynamic>) return raw;
    if (raw is List && raw.isNotEmpty) return raw.first as Map<String, dynamic>;
    return {};
  }

  List<Map<String, dynamic>> _toList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  static const _kMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _kMonthsFull = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  // ── Root build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_initLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 56),
                const SizedBox(height: 16),
                Text(
                  _initError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _bootstrap,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: Colors.blue,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Month'),
            Tab(text: 'Year'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDayTab(), _buildMonthTab(), _buildYearTab()],
      ),
    );
  }

  // ── TODAY TAB ─────────────────────────────────────────────────────────────

  Widget _buildDayTab() {
    return RefreshIndicator(
      onRefresh: _loadDay,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _NavCard(
              label: _isToday(_selectedDate)
                  ? 'Today  •  ${_fmtDisplay(_selectedDate)}'
                  : _fmtDisplay(_selectedDate),
              onPrev: () {
                setState(
                  () => _selectedDate = _selectedDate.subtract(
                    const Duration(days: 1),
                  ),
                );
                _loadDay();
              },
              onNext: _isToday(_selectedDate)
                  ? null
                  : () {
                      setState(
                        () => _selectedDate = _selectedDate.add(
                          const Duration(days: 1),
                        ),
                      );
                      _loadDay();
                    },
              onTap: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (p != null) {
                  setState(() => _selectedDate = p);
                  _loadDay();
                }
              },
            ),
            const SizedBox(height: 20),
            _BigCountCard(
              count: _dayCount,
              label: 'Patients Attended',
              sublabel: _isToday(_selectedDate)
                  ? 'Today'
                  : _fmtDisplay(_selectedDate),
              color: Colors.blue,
              icon: Icons.people_alt_rounded,
              loading: _dayLoading,
              isLive: _isLiveCount && _isToday(_selectedDate),
            ),
            // ✅ NEW: Live indicator note
            if (_isToday(_selectedDate)) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    _PulseDot(color: Colors.green.shade500),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Live — count updates instantly when a patient completes tests',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── MONTH TAB ─────────────────────────────────────────────────────────────

  Widget _buildMonthTab() {
    final now = DateTime.now();
    final atCurrent = _selMonthYear == now.year && _selMonth == now.month;

    return RefreshIndicator(
      onRefresh: _loadMonth,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _NavCard(
              label: '${_kMonthsFull[_selMonth - 1]}  $_selMonthYear',
              onPrev: () {
                setState(() {
                  if (_selMonth == 1) {
                    _selMonth = 12;
                    _selMonthYear--;
                  } else {
                    _selMonth--;
                  }
                });
                _loadMonth();
              },
              onNext: atCurrent
                  ? null
                  : () {
                      setState(() {
                        if (_selMonth == 12) {
                          _selMonth = 1;
                          _selMonthYear++;
                        } else {
                          _selMonth++;
                        }
                      });
                      _loadMonth();
                    },
            ),
            const SizedBox(height: 20),
            _BigCountCard(
              count: _monthCount,
              label: 'Patients This Month',
              sublabel: '${_kMonthsFull[_selMonth - 1]} $_selMonthYear',
              color: Colors.purple,
              icon: Icons.calendar_month_rounded,
              loading: _monthLoading,
            ),
            const SizedBox(height: 20),
            _ChartCard(
              title:
                  'Daily Patients  •  ${_kMonths[_selMonth - 1]} $_selMonthYear',
              loading: _monthLoading,
              isEmpty: _monthBars.isEmpty,
              child: _DailyBarChart(bars: _monthBars),
            ),
          ],
        ),
      ),
    );
  }

  // ── YEAR TAB ──────────────────────────────────────────────────────────────

  Widget _buildYearTab() {
    return RefreshIndicator(
      onRefresh: _loadYear,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _NavCard(
              label: '$_selYear',
              onPrev: () {
                setState(() => _selYear--);
                _loadYear();
              },
              onNext: _selYear >= DateTime.now().year
                  ? null
                  : () {
                      setState(() => _selYear++);
                      _loadYear();
                    },
            ),
            const SizedBox(height: 20),
            _BigCountCard(
              count: _yearCount,
              label: 'Patients This Year',
              sublabel: '$_selYear',
              color: Colors.teal,
              icon: Icons.bar_chart_rounded,
              loading: _yearLoading,
            ),
            const SizedBox(height: 20),
            _ChartCard(
              title: 'Monthly Patients  •  $_selYear',
              loading: _yearLoading,
              isEmpty: _yearBars.every((b) => b.count == 0),
              child: _MonthlyBarChart(bars: _yearBars, currentYear: _selYear),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════ REUSABLE WIDGETS ═══════════════════════════════

class _NavCard extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onTap;

  const _NavCard({
    required this.label,
    required this.onPrev,
    this.onNext,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          GestureDetector(
            onTap: onTap,
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: onNext == null ? Colors.grey[300] : Colors.black87,
            ),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────

class _BigCountCard extends StatelessWidget {
  final int count;
  final String label;
  final String sublabel;
  final Color color;
  final IconData icon;
  final bool loading;
  final bool isLive;

  const _BigCountCard({
    required this.count,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.icon,
    required this.loading,
    this.isLive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: loading
          ? const SizedBox(
              height: 80,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          : Row(
              children: [
                Icon(
                  icon,
                  color: Colors.white.withValues(alpha: 0.85),
                  size: 56,
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                          if (isLive) ...[
                            const SizedBox(width: 8),
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.shade400,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        isLive ? '$sublabel  •  updated from room' : sublabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final bool loading;
  final bool isEmpty;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.loading,
    required this.isEmpty,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          if (loading)
            const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (isEmpty)
            const SizedBox(
              height: 100,
              child: Center(
                child: Text(
                  'No data for this period',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            child,
        ],
      ),
    );
  }
}

// ═════════════════════════ BAR CHARTS ════════════════════════════════════

class _DayBar {
  final int day, count;
  const _DayBar({required this.day, required this.count});
}

class _DailyBarChart extends StatelessWidget {
  final List<_DayBar> bars;
  const _DailyBarChart({required this.bars});

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();
    final maxVal = bars.map((b) => b.count).reduce((a, b) => a > b ? a : b);
    final safeMax = maxVal == 0 ? 1 : maxVal;
    const barH = 90.0;
    final todayDay = DateTime.now().day;

    return SizedBox(
      height: barH + 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: bars.length,
        itemBuilder: (_, i) {
          final b = bars[i];
          final h = ((b.count / safeMax) * barH).clamp(2.0, barH);
          final isToday = b.day == todayDay;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (b.count > 0)
                  Text(
                    '${b.count}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 2),
                Container(
                  width: 22,
                  height: h,
                  decoration: BoxDecoration(
                    color: isToday
                        ? Colors.orange.shade400
                        : Colors.blue.shade400,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${b.day}',
                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────

class _MonthBar {
  final int month, count;
  const _MonthBar({required this.month, required this.count});
}

class _MonthlyBarChart extends StatelessWidget {
  final List<_MonthBar> bars;
  final int currentYear;
  const _MonthlyBarChart({required this.bars, required this.currentYear});

  static const _names = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final maxVal = bars.map((b) => b.count).reduce((a, b) => a > b ? a : b);
    final safeMax = maxVal == 0 ? 1 : maxVal;
    const barH = 90.0;
    final curMonth = DateTime.now().month;
    final curYear = DateTime.now().year;

    return Column(
      children: [
        SizedBox(
          height: barH + 44,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: bars.map((b) {
              final h = ((b.count / safeMax) * barH).clamp(2.0, barH);
              final isCurrent = b.month == curMonth && currentYear == curYear;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (b.count > 0)
                        Text(
                          '${b.count}',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Container(
                        height: h,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? Colors.orange.shade400
                              : Colors.teal.shade400,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _names[b.month - 1],
                        style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 10, height: 10, color: Colors.teal.shade400),
            const SizedBox(width: 4),
            const Text('Patients', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 16),
            Container(width: 10, height: 10, color: Colors.orange.shade400),
            const SizedBox(width: 4),
            const Text('Current month', style: TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

// ── Pulsing live dot ──────────────────────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _a = Tween<double>(begin: 0.25, end: 1.0).animate(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _a,
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}
