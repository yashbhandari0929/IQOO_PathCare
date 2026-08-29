// lib/screens/supervisor/view_reports_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

class SupervisorViewReportsScreen extends StatefulWidget {
  const SupervisorViewReportsScreen({Key? key}) : super(key: key);

  @override
  State<SupervisorViewReportsScreen> createState() =>
      _SupervisorViewReportsScreenState();
}

class _SupervisorViewReportsScreenState
    extends State<SupervisorViewReportsScreen> {
  SupabaseClient get _supabase => Supabase.instance.client;

  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _filterType;
  final _searchController = TextEditingController();

  final List<String> _reportTypes = [
    'Blood Test', 'Urine Test', 'X-Ray', 'MRI',
    'CT Scan', 'ECG', 'Ultrasound', 'Biopsy', 'General', 'Other',
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

  // ── Load all reports submitted by this supervisor ───────────
  Future<void> _loadReports() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser == null) return;

      // Get supervisor's own ID
      final supervisorData = await _supabase
          .from('supervisors')
          .select('id')
          .eq('auth_id', authUser.id)
          .maybeSingle();

      if (supervisorData == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final supervisorId = supervisorData['id'] as String;

      // Fetch all reports uploaded by this supervisor
      final data = await _supabase
          .from('patient_reports')
          .select(
        'id, report_name, report_type, description, file_url, file_path, created_at, patients(id, full_name)',
      )
          .eq('uploaded_by', supervisorId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _reports = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('Error loading reports: $e', isError: true);
      }
    }
  }

  // ── Delete report ───────────────────────────────────────────
  Future<void> _deleteReport(String reportId, String filePath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Text('Delete Report'),
          ],
        ),
        content: Text(
            'This report will be permanently deleted. The patient will no longer be able to view it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: TextStyle(color: Colors.grey[700]))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Optimistic remove
    setState(() => _reports.removeWhere((r) => r['id'] == reportId));

    try {
      if (filePath.isNotEmpty) {
        await _supabase.storage
            .from('patient-reports')
            .remove([filePath]);
      }
      await _supabase
          .from('patient_reports')
          .delete()
          .eq('id', reportId);
      _showSnack('Report deleted successfully');
    } catch (e) {
      _showSnack('Error deleting: $e', isError: true);
      _loadReports(); // restore on failure
    }
  }

  // ── Open report URL ─────────────────────────────────────────
  Future<void> _openReport(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnack('Could not open report', isError: true);
    }
  }

  // ── Show report detail bottom sheet ────────────────────────
  void _showDetail(Map<String, dynamic> report) {
    final createdAt =
        DateTime.tryParse(report['created_at'] ?? '') ?? DateTime.now();
    final formatted =
    DateFormat('dd MMMM yyyy, hh:mm a').format(createdAt.toLocal());
    final color = _typeColor(report['report_type']);
    final patientName =
        (report['patients'] as Map?)?['full_name'] ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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

            // Header
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_typeIcon(report['report_type']),
                      color: color, size: 32),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(report['report_name'] ?? '',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(report['report_type'] ?? '',
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                                fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),

            _detailRow(Icons.person, 'Patient', patientName),
            _detailRow(Icons.calendar_today, 'Uploaded', formatted),
            if ((report['description'] ?? '').toString().isNotEmpty)
              _detailRow(
                  Icons.notes, 'Description', report['description']),

            SizedBox(height: 24),

            // View button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openReport(report['file_url'] ?? '');
                },
                icon: Icon(Icons.open_in_new),
                label: Text('View / Download Report',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            SizedBox(height: 12),

            // Delete button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _deleteReport(
                      report['id'], report['file_path'] ?? '');
                },
                icon: Icon(Icons.delete_outline, color: Colors.red),
                label: Text('Delete Report',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
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
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500)),
              SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Filtered list ───────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    return _reports.where((r) {
      final name = (r['report_name'] ?? '').toString().toLowerCase();
      final patient =
      ((r['patients'] as Map?)?['full_name'] ?? '').toString().toLowerCase();
      final type = r['report_type'] ?? '';
      final matchSearch = _searchQuery.isEmpty ||
          name.contains(_searchQuery.toLowerCase()) ||
          patient.contains(_searchQuery.toLowerCase());
      final matchType = _filterType == null || type == _filterType;
      return matchSearch && matchType;
    }).toList();
  }

  // ── BUILD ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('Submitted Reports'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadReports,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.teal))
          : Column(
        children: [
          // ── Stats banner ────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
                horizontal: 20, vertical: 14),
            color: Colors.teal,
            child: Row(
              children: [
                _statPill('Total', '${_reports.length}'),
                SizedBox(width: 12),
                _statPill(
                  'Showing',
                  '${filtered.length}',
                ),
                SizedBox(width: 12),
                _statPill(
                  'Blood Tests',
                  '${_reports.where((r) => r['report_type'] == 'Blood Test').length}',
                ),
              ],
            ),
          ),

          // ── Search ──────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _searchController,
              onChanged: (v) =>
                  setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search by name or patient...',
                prefixIcon:
                Icon(Icons.search, color: Colors.teal),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.close,
                      color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  BorderSide(color: Colors.teal, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                EdgeInsets.symmetric(vertical: 0, horizontal: 14),
              ),
            ),
          ),

          // ── Filter chips ─────────────────────────────
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 12),
              children: [
                // "All" chip
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 4, vertical: 6),
                  child: FilterChip(
                    label: Text('All',
                        style: TextStyle(
                            fontSize: 12,
                            color: _filterType == null
                                ? Colors.white
                                : Colors.grey[700])),
                    selected: _filterType == null,
                    onSelected: (_) =>
                        setState(() => _filterType = null),
                    selectedColor: Colors.teal,
                    backgroundColor: Colors.white,
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    side: BorderSide(
                        color: _filterType == null
                            ? Colors.teal
                            : Colors.grey[300]!),
                  ),
                ),
                ..._reportTypes.map((type) {
                  final selected = _filterType == type;
                  return Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 4, vertical: 6),
                    child: FilterChip(
                      label: Text(type,
                          style: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? Colors.white
                                  : Colors.grey[700])),
                      selected: selected,
                      onSelected: (_) => setState(
                              () => _filterType =
                          selected ? null : type),
                      selectedColor: Colors.teal,
                      backgroundColor: Colors.white,
                      checkmarkColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(20)),
                      side: BorderSide(
                          color: selected
                              ? Colors.teal
                              : Colors.grey[300]!),
                    ),
                  );
                }),
              ],
            ),
          ),

          // ── List ─────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadReports,
              color: Colors.teal,
              child: filtered.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                padding: EdgeInsets.all(14),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) =>
                    _buildCard(filtered[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 72, color: Colors.grey[300]),
          SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty || _filterType != null
                ? 'No reports match your filter'
                : 'No reports submitted yet',
            style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 8),
          Text(
            'Reports you upload will appear here.',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> report) {
    final patientName =
        (report['patients'] as Map?)?['full_name'] ?? 'Unknown';
    final createdAt =
        DateTime.tryParse(report['created_at'] ?? '') ?? DateTime.now();
    final formatted =
    DateFormat('dd MMM yyyy').format(createdAt.toLocal());
    final color = _typeColor(report['report_type']);

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetail(report),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              // Icon
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_typeIcon(report['report_type']),
                    color: color, size: 26),
              ),
              SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report['report_name'] ?? '',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 13, color: Colors.grey[500]),
                        SizedBox(width: 4),
                        Text(patientName,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600])),
                      ],
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            report['report_type'] ?? '',
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(formatted,
                            style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 11)),
                      ],
                    ),
                    if ((report['description'] ?? '')
                        .toString()
                        .isNotEmpty) ...[
                      SizedBox(height: 4),
                      Text(
                        report['description'],
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Actions
              Column(
                children: [
                  IconButton(
                    icon: Icon(Icons.open_in_new,
                        color: Colors.teal, size: 20),
                    tooltip: 'View',
                    onPressed: () =>
                        _openReport(report['file_url'] ?? ''),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: Colors.red[400], size: 20),
                    tooltip: 'Delete',
                    onPressed: () => _deleteReport(
                        report['id'], report['file_path'] ?? ''),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statPill(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          SizedBox(width: 4),
          Text(label,
              style:
              TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'Blood Test':  return Colors.red;
      case 'Urine Test':  return Colors.amber.shade700;
      case 'X-Ray':       return Colors.purple;
      case 'MRI':         return Colors.teal;
      case 'CT Scan':     return Colors.indigo;
      case 'ECG':         return Colors.pink;
      case 'Ultrasound':  return Colors.cyan.shade700;
      default:            return Colors.blue;
    }
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'Blood Test':  return Icons.bloodtype;
      case 'Urine Test':  return Icons.science;
      case 'X-Ray':       return Icons.contrast;
      case 'MRI':         return Icons.radio;
      case 'CT Scan':     return Icons.rotate_90_degrees_ccw;
      case 'ECG':         return Icons.monitor_heart;
      case 'Ultrasound':  return Icons.waves;
      default:            return Icons.description;
    }
  }
}