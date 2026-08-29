// lib/screens/admin/upload_report_screen.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class UploadReportScreen extends StatefulWidget {
  const UploadReportScreen({Key? key}) : super(key: key);

  @override
  State<UploadReportScreen> createState() => _UploadReportScreenState();
}

class _UploadReportScreenState extends State<UploadReportScreen> {
  SupabaseClient get _supabase => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  final _reportNameController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<Map<String, dynamic>> _patients = [];
  String? _selectedPatientId;
  String _selectedReportType = 'Blood Test';

  PlatformFile? _pickedFile;
  Uint8List? _fileBytes;

  bool _isUploading = false;
  bool _isLoadingPatients = true;
  List<Map<String, dynamic>> _recentReports = [];
  bool _isLoadingReports = false;

  final List<String> _reportTypes = [
    'Blood Test', 'Urine Test', 'X-Ray', 'MRI',
    'CT Scan', 'ECG', 'Ultrasound', 'Biopsy', 'General', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadPatients();
    _loadRecentReports();
  }

  @override
  void dispose() {
    _reportNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ── Load Patients ───────────────────────────────────────────
  Future<void> _loadPatients() async {
    try {
      final data = await _supabase
          .from('patients')
          .select('id, full_name')
          .order('full_name');
      if (mounted) {
        setState(() {
          _patients = List<Map<String, dynamic>>.from(data);
          _isLoadingPatients = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPatients = false);
        _showSnack('Error loading patients: $e', isError: true);
      }
    }
  }

  // ── Load Recent Reports ─────────────────────────────────────
  Future<void> _loadRecentReports() async {
    if (mounted) setState(() => _isLoadingReports = true);
    try {
      final data = await _supabase
          .from('patient_reports')
          .select(
          'id, report_name, report_type, file_path, created_at, patients(full_name)')
          .order('created_at', ascending: false)
          .limit(10);
      if (mounted) {
        setState(() {
          _recentReports = List<Map<String, dynamic>>.from(data);
          _isLoadingReports = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingReports = false);
    }
  }

  // ── Pick File ───────────────────────────────────────────────
  Future<void> _pickFile() async {
    try {
      if (mounted) setState(() { _pickedFile = null; _fileBytes = null; });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
        allowCompression: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? bytes;

      if (file.bytes != null && file.bytes!.isNotEmpty) {
        bytes = file.bytes!;
      } else if (file.path != null && file.path!.isNotEmpty) {
        final ioFile = File(file.path!);
        if (await ioFile.exists()) bytes = await ioFile.readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        _showSnack('Could not read the file. Please try a different file.',
            isError: true);
        return;
      }
      if (mounted) setState(() { _pickedFile = file; _fileBytes = bytes; });
    } catch (e) {
      _showSnack('Error selecting file: $e', isError: true);
    }
  }

  // ── Resolve uploader ID — works for BOTH supervisor & admin ─
  // Uses maybeSingle() so it never throws PGRST116 (0 rows error)
  Future<String?> _getUploaderId(String authUserId) async {
    // Try supervisors first
    try {
      final d = await _supabase
          .from('supervisors')
          .select('id')
          .eq('auth_id', authUserId)
          .maybeSingle();
      if (d != null) return d['id'] as String;
    } catch (_) {}

    // Fall back to admins
    try {
      final d = await _supabase
          .from('admins')
          .select('id')
          .eq('auth_id', authUserId)
          .maybeSingle();
      if (d != null) return d['id'] as String;
    } catch (_) {}

    return null;
  }

  // ── Upload Report ───────────────────────────────────────────
  Future<void> _uploadReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPatientId == null) {
      _showSnack('Please select a patient', isError: true);
      return;
    }
    if (_pickedFile == null || _fileBytes == null || _fileBytes!.isEmpty) {
      _showSnack('Please select a file to upload', isError: true);
      return;
    }

    if (mounted) setState(() => _isUploading = true);

    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser == null) {
        _showSnack('Session expired. Please log in again.', isError: true);
        return;
      }

      // ✅ Safe lookup — never throws even if user is supervisor not admin
      final uploaderId = await _getUploaderId(authUser.id);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = (_pickedFile!.extension ?? 'pdf').toLowerCase();
      final safeName =
      _pickedFile!.name.replaceAll(RegExp(r'[^\w\-.]'), '_');
      final storagePath =
          'reports/$_selectedPatientId/${timestamp}_$safeName';

      final contentType = ext == 'pdf'
          ? 'application/pdf'
          : ext == 'png'
          ? 'image/png'
          : 'image/jpeg';

      // Upload to Supabase Storage
      await _supabase.storage.from('patient-reports').uploadBinary(
        storagePath,
        _fileBytes!,
        fileOptions:
        FileOptions(contentType: contentType, upsert: false),
      );

      // Get public URL for the patient to open
      final publicUrl = _supabase.storage
          .from('patient-reports')
          .getPublicUrl(storagePath);

      // Insert into patient_reports table
      await _supabase.from('patient_reports').insert({
        'patient_id': _selectedPatientId,
        if (uploaderId != null) 'uploaded_by': uploaderId, // ✅ safe insert
        'report_name': _reportNameController.text.trim(),
        'report_type': _selectedReportType,
        'description': _descriptionController.text.trim(),
        'file_url': publicUrl,
        'file_path': storagePath,
      });

      if (mounted) {
        setState(() {
          _pickedFile = null;
          _fileBytes = null;
          _selectedPatientId = null;
          _selectedReportType = 'Blood Test';
          _reportNameController.clear();
          _descriptionController.clear();
        });
        _showSnack('Report uploaded! Patient can now view it.');
        _loadRecentReports();
      }
    } catch (e) {
      _showSnack('Upload failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Delete Report ───────────────────────────────────────────
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
            child:
            Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

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
      _showSnack('Report deleted');
      _loadRecentReports();
    } catch (e) {
      _showSnack('Error deleting: $e', isError: true);
    }
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

  // ── BUILD ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('Upload Patient Report'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            _buildForm(),
            SizedBox(height: 28),
            _buildRecentUploads(),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Upload Form ─────────────────────────────────────────────
  Widget _buildForm() {
    return Card(
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.upload_file,
                        color: Colors.teal, size: 26),
                  ),
                  SizedBox(width: 12),
                  Text('New Report',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              SizedBox(height: 20),

              // Patient dropdown
              _isLoadingPatients
                  ? Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                value: _selectedPatientId,
                decoration: _dec('Select Patient', Icons.person),
                isExpanded: true,
                items: _patients
                    .map((p) => DropdownMenuItem<String>(
                  value: p['id'] as String,
                  child: Text(p['full_name'] ?? 'Unknown',
                      overflow: TextOverflow.ellipsis),
                ))
                    .toList(),
                onChanged: (val) =>
                    setState(() => _selectedPatientId = val),
                validator: (val) =>
                val == null ? 'Please select a patient' : null,
              ),
              SizedBox(height: 14),

              // Report name
              TextFormField(
                controller: _reportNameController,
                decoration: _dec('Report Name', Icons.description),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter a report name'
                    : null,
              ),
              SizedBox(height: 14),

              // Report type
              DropdownButtonFormField<String>(
                value: _selectedReportType,
                decoration: _dec('Report Type', Icons.category),
                items: _reportTypes
                    .map((t) =>
                    DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) =>
                    setState(() => _selectedReportType = val!),
              ),
              SizedBox(height: 14),

              // Description
              TextFormField(
                controller: _descriptionController,
                decoration:
                _dec('Description (optional)', Icons.notes),
                maxLines: 2,
              ),
              SizedBox(height: 18),

              // File picker
              GestureDetector(
                onTap: _isUploading ? null : _pickFile,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _fileBytes != null
                          ? Colors.green
                          : Colors.teal.shade300,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: _fileBytes != null
                        ? Colors.green.withOpacity(0.05)
                        : Colors.teal.withOpacity(0.04),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _fileBytes != null
                            ? Icons.check_circle_outline
                            : Icons.cloud_upload_outlined,
                        color: _fileBytes != null
                            ? Colors.green
                            : Colors.teal,
                        size: 44,
                      ),
                      SizedBox(height: 10),
                      Text(
                        _pickedFile != null
                            ? _pickedFile!.name
                            : 'Tap to select PDF or Image',
                        style: TextStyle(
                          color: _fileBytes != null
                              ? Colors.green
                              : Colors.teal,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_fileBytes != null) ...[
                        SizedBox(height: 4),
                        Text(
                          '${(_fileBytes!.length / 1024).toStringAsFixed(1)} KB  •  Tap to change',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),

              // Upload button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _uploadReport,
                  icon: _isUploading
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : Icon(Icons.upload),
                  label: Text(
                    _isUploading ? 'Uploading...' : 'Upload Report',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.teal.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Recent Uploads ──────────────────────────────────────────
  Widget _buildRecentUploads() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Uploads',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: _loadRecentReports,
              icon: Icon(Icons.refresh, size: 16, color: Colors.teal),
              label:
              Text('Refresh', style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
        SizedBox(height: 10),
        if (_isLoadingReports)
          Center(child: CircularProgressIndicator(color: Colors.teal))
        else if (_recentReports.isEmpty)
          Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.folder_open,
                      size: 48, color: Colors.grey[400]),
                  SizedBox(height: 8),
                  Text('No reports uploaded yet',
                      style: TextStyle(color: Colors.grey[500])),
                ],
              ),
            ),
          )
        else
          ...(_recentReports.map((r) => _buildTile(r))),
      ],
    );
  }

  Widget _buildTile(Map<String, dynamic> report) {
    final patientName =
        (report['patients'] as Map?)?['full_name'] ?? 'Unknown';
    final createdAt =
        DateTime.tryParse(report['created_at'] ?? '') ?? DateTime.now();
    final formatted =
    DateFormat('dd MMM yyyy, hh:mm a').format(createdAt.toLocal());
    final color = _typeColor(report['report_type']);

    return Card(
      margin: EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding:
        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.picture_as_pdf, color: color),
        ),
        title: Text(report['report_name'] ?? '',
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient: $patientName',
                style: TextStyle(fontSize: 12)),
            Row(
              children: [
                Container(
                  margin: EdgeInsets.only(top: 4),
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
                Flexible(
                  child: Text(formatted,
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () =>
              _deleteReport(report['id'], report['file_path'] ?? ''),
        ),
        isThreeLine: true,
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

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.teal),
      border:
      OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.teal, width: 2),
      ),
      contentPadding:
      EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}