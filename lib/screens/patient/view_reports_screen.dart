// lib/screens/patient/view_reports_screen.dart
//
// REQUIRED pubspec.yaml packages:
//   url_launcher: ^6.2.0
//   intl: ^0.19.0

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'patient_help_chat_screen.dart';

final supabase = Supabase.instance.client;

class ViewReportsScreen extends StatefulWidget {
  const ViewReportsScreen({Key? key}) : super(key: key);

  @override
  State<ViewReportsScreen> createState() => _ViewReportsScreenState();
}

class _ViewReportsScreenState extends State<ViewReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<String> _filters = [
    'All',
    'Blood Test',
    'Urine Test',
    'X-Ray',
    'MRI',
    'CT Scan',
    'ECG',
    'Ultrasound',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    try {
      final authUser = supabase.auth.currentUser!;
      final patientData = await supabase
          .from('patients')
          .select('id')
          .eq('auth_id', authUser.id)
          .single();
      final patientId = patientData['id'];

      final data = await supabase
          .from('patient_reports')
          .select('*')
          .eq('patient_id', patientId)
          .order('created_at', ascending: false);

      setState(() {
        _reports = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Error loading reports: $e', isError: true);
    }
  }

  List<Map<String, dynamic>> get _filteredReports {
    return _reports.where((r) {
      final matchesFilter =
          _selectedFilter == 'All' || r['report_type'] == _selectedFilter;
      final query = _searchQuery.toLowerCase();
      final matchesSearch =
          query.isEmpty ||
          (r['report_name'] ?? '').toLowerCase().contains(query) ||
          (r['report_type'] ?? '').toLowerCase().contains(query);
      return matchesFilter && matchesSearch;
    }).toList();
  }

  Future<void> _openReport(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnack('Could not open report', isError: true);
    }
  }

  // ── Navigate to help chat ──────────────────────────────────────────────────
  void _openHelpChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PatientHelpChatScreen()),
    );
  }

  void _showReportDetail(Map<String, dynamic> report) {
    final createdAt =
        DateTime.tryParse(report['created_at'] ?? '') ?? DateTime.now();
    final formattedDate = DateFormat(
      'dd MMMM yyyy, hh:mm a',
    ).format(createdAt.toLocal());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final typeColor = _typeColor(report['report_type']);
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _typeIcon(report['report_type']),
                      color: typeColor,
                      size: 32,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report['report_name'] ?? '',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            report['report_type'] ?? '',
                            style: TextStyle(
                              color: typeColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              _detailRow(Icons.calendar_today, 'Date', formattedDate),
              if ((report['description'] ?? '').isNotEmpty)
                _detailRow(Icons.notes, 'Description', report['description']),
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openReport(report['file_url']);
                  },
                  icon: Icon(Icons.open_in_new),
                  label: Text(
                    'View / Download Report',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey[500], size: 18),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Stats Banner + Chat Icon ──────────────────────────
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(color: Colors.blue),
                  child: Row(
                    children: [
                      // ── stat pills ──────────────────────────────────
                      Expanded(
                        child: Row(
                          children: [
                            _statPill(
                              'Total',
                              '${_reports.length}',
                              Colors.white,
                            ),
                            SizedBox(width: 12),
                            _statPill(
                              'Blood Tests',
                              '${_reports.where((r) => r['report_type'] == 'Blood Test').length}',
                              Colors.red.shade200,
                            ),
                            SizedBox(width: 12),
                            _statPill(
                              'Imaging',
                              '${_reports.where((r) => ['X-Ray', 'MRI', 'CT Scan', 'Ultrasound'].contains(r['report_type'])).length}',
                              Colors.purple.shade200,
                            ),
                          ],
                        ),
                      ),

                      // ── Chat with supervisor icon button ────────────
                      Tooltip(
                        message: 'Chat with Supervisor',
                        child: InkWell(
                          onTap: _openHelpChat,
                          borderRadius: BorderRadius.circular(50),
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.support_agent_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Search ────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search reports...',
                      prefixIcon: Icon(Icons.search, color: Colors.blue),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),

                // ── Filter Chips ──────────────────────────────
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filters.length,
                    itemBuilder: (ctx, i) {
                      final f = _filters[i];
                      final selected = _selectedFilter == f;
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: ChoiceChip(
                          label: Text(f),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _selectedFilter = f),
                          selectedColor: Colors.blue,
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : Colors.grey[700],
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          backgroundColor: Colors.white,
                        ),
                      );
                    },
                  ),
                ),

                // ── Reports List ──────────────────────────────
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadReports,
                    child: _filteredReports.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: EdgeInsets.all(14),
                            itemCount: _filteredReports.length,
                            itemBuilder: (ctx, i) =>
                                _buildReportCard(_filteredReports[i]),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 72, color: Colors.grey[300]),
          SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty || _selectedFilter != 'All'
                ? 'No reports match your filter'
                : 'No reports uploaded yet',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Your doctor will upload your reports here.',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final createdAt =
        DateTime.tryParse(report['created_at'] ?? '') ?? DateTime.now();
    final formattedDate = DateFormat('dd MMM yyyy').format(createdAt.toLocal());
    final typeColor = _typeColor(report['report_type']);

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showReportDetail(report),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _typeIcon(report['report_type']),
                  color: typeColor,
                  size: 28,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report['report_name'] ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            report['report_type'] ?? '',
                            style: TextStyle(
                              color: typeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          formattedDate,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if ((report['description'] ?? '').isNotEmpty) ...[
                      SizedBox(height: 4),
                      Text(
                        report['description'],
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statPill(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          SizedBox(width: 4),
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'Blood Test':
        return Colors.red;
      case 'Urine Test':
        return Colors.amber.shade700;
      case 'X-Ray':
        return Colors.purple;
      case 'MRI':
        return Colors.teal;
      case 'CT Scan':
        return Colors.indigo;
      case 'ECG':
        return Colors.pink;
      case 'Ultrasound':
        return Colors.cyan.shade700;
      default:
        return Colors.blue;
    }
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'Blood Test':
        return Icons.bloodtype;
      case 'Urine Test':
        return Icons.science;
      case 'X-Ray':
        return Icons.contrast;
      case 'MRI':
        return Icons.radio;
      case 'CT Scan':
        return Icons.rotate_90_degrees_ccw;
      case 'ECG':
        return Icons.monitor_heart;
      case 'Ultrasound':
        return Icons.waves;
      default:
        return Icons.description;
    }
  }
}
