// lib/models/appointment.dart
class Appointment {
  final String id;
  final String patientId;
  final DateTime appointmentDate;
  final String appointmentTime;
  final String status; // scheduled, completed, cancelled
  final String? specialInstructions;
  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  Appointment({
    required this.id,
    required this.patientId,
    required this.appointmentDate,
    required this.appointmentTime,
    required this.status,
    this.specialInstructions,
    required this.createdAt,
    this.completedAt,
    this.cancelledAt,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      appointmentDate: DateTime.parse(json['appointment_date'] as String),
      appointmentTime: json['appointment_time'] as String,
      status: json['status'] as String? ?? 'scheduled',
      specialInstructions: json['special_instructions'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'appointment_date': appointmentDate.toIso8601String().split('T')[0],
      'appointment_time': appointmentTime,
      'status': status,
      'special_instructions': specialInstructions,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
    };
  }
}
