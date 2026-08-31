import 'package:flutter/material.dart';
import 'package:final_app/services/hospital_3d_service.dart';
import 'package:intl/intl.dart';

class RoomDetailsBottomSheet extends StatefulWidget {
  final String roomNumber;

  const RoomDetailsBottomSheet({super.key, required this.roomNumber});

  @override
  State<RoomDetailsBottomSheet> createState() => _RoomDetailsBottomSheetState();
}

class _RoomDetailsBottomSheetState extends State<RoomDetailsBottomSheet> {
  final Hospital3DService _service = Hospital3DService();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.8,
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _service.getRoomDetails(widget.roomNumber),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Room details not found'));
          }

          final data = snapshot.data!;
          final doctor = data['doctor'] as Map<String, dynamic>?;
          final queue = data['queue'] as List<Map<String, dynamic>>? ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['roomNumber'],
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${data['department']} • ${data['floor']}',
                        style: const TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 30),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatCard('Waiting', data['waiting'].toString(), Colors.orange),
                  _buildStatCard('In Progress', data['inProgress'].toString(), Colors.red),
                  _buildStatCard('Completed', data['completed'].toString(), Colors.green),
                ],
              ),
              const SizedBox(height: 24),
              if (doctor != null) ...[
                const Text('Assigned Doctor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text(doctor['name'][0], style: const TextStyle(color: Colors.blue)),
                  ),
                  title: Text(doctor['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(doctor['email']),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: doctor['available'] ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      doctor['available'] ? 'Available' : 'Busy',
                      style: TextStyle(color: doctor['available'] ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const Text('Patient Queue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: queue.isEmpty
                    ? const Center(child: Text('No patients in queue', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: queue.length,
                        itemBuilder: (context, index) {
                          final p = queue[index];
                          final timeStr = p['scheduledTime'] != null 
                            ? DateFormat.jm().format(DateTime.parse(p['scheduledTime']).toLocal()) 
                            : 'N/A';
                            
                          Color statusColor = Colors.grey;
                          if (p['status'] == 'reached') statusColor = Colors.orange;
                          else if (p['status'] == 'in_progress') statusColor = Colors.red;
                          else if (p['status'] == 'completed') statusColor = Colors.green;

                          return Card(
                            elevation: 0,
                            color: Colors.grey.shade50,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(p['patientName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${p['testName']} • $timeStr'),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: statusColor),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  (p['status'] as String).toUpperCase().replaceAll('_', ' '),
                                  style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
