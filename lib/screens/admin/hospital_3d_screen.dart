import 'package:flutter/material.dart';
import 'package:final_app/models/room_position.dart';
import 'package:final_app/services/hospital_3d_service.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class Hospital3DScreen extends StatefulWidget {
  const Hospital3DScreen({super.key});

  @override
  State<Hospital3DScreen> createState() => _Hospital3DScreenState();
}

class _Hospital3DScreenState extends State<Hospital3DScreen> {
  final Hospital3DService _service = Hospital3DService();

  String _buildHotspotsHtml(Map<String, Map<String, dynamic>> roomStats) {
    StringBuffer html = StringBuffer();
    for (var room in RoomPositions.allRooms) {
      final stats = roomStats[room.roomNumber.replaceAll(' ', '')] ?? {
        'waiting': 0,
        'inProgress': 0,
        'completed': 0,
      };

      final int waiting = stats['waiting'];
      final int inProgress = stats['inProgress'];

      String stateClass = 'available';
      String badgeText = '';

      if (inProgress > 0) {
        stateClass = 'busy';
        badgeText = 'In Progress';
      } else if (waiting > 0) {
        stateClass = 'waiting';
        badgeText = '$waiting Waiting';
      } else {
        badgeText = 'Available';
      }

      html.writeln('''
        <button slot="hotspot-${room.hotspotId}" 
                data-position="${room.x3d} ${room.y3d} ${room.z3d}" 
                data-normal="0 1 0" 
                class="hotspot $stateClass"
                onclick="RoomChannel.postMessage('${room.roomNumber}');">
          <div class="hotspot-badge">$badgeText</div>
        </button>
      ''');
    }
    return html.toString();
  }

  final String _css = '''
    .hotspot {
      display: block;
      width: 15px;
      height: 15px;
      border-radius: 50%;
      border: none;
      background-color: #22c55e;
      box-sizing: border-box;
      cursor: pointer;
      box-shadow: 0 2px 10px rgba(0,0,0,0.2);
      transition: all 0.3s ease;
      position: relative;
    }
    
    .hotspot.available {
      background-color: #22c55e; /* Green */
    }
    
    .hotspot.waiting {
      background-color: #eab308; /* Yellow */
      width: 20px;
      height: 20px;
    }
    
    .hotspot.busy {
      background-color: #ef4444; /* Red */
      animation: pulse 1.5s infinite;
      width: 20px;
      height: 20px;
    }
    
    .hotspot-badge {
      position: absolute;
      top: -30px;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(255, 255, 255, 0.95);
      color: #0f172a;
      padding: 4px 10px;
      border-radius: 12px;
      font-size: 12px;
      font-family: sans-serif;
      font-weight: bold;
      white-space: nowrap;
      box-shadow: 0 4px 12px rgba(0,0,0,0.1);
      pointer-events: none;
      opacity: 0;
      transition: opacity 0.3s;
    }
    
    .hotspot:hover .hotspot-badge {
      opacity: 1;
    }
    
    .hotspot.busy .hotspot-badge, .hotspot.waiting .hotspot-badge {
      opacity: 1;
    }
    
    @keyframes pulse {
      0% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.7); }
      70% { box-shadow: 0 0 0 10px rgba(239, 68, 68, 0); }
      100% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0); }
    }
  ''';

  void _onRoomTapped(String roomNumber) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildPremiumBottomSheet(roomNumber),
    );
  }

  Widget _buildPremiumBottomSheet(String roomNumber) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roomNumber,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Department • General',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const SizedBox(height: 20),
          const Center(child: Text('Live data fetching from Supabase...')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Digital Twin', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _service.watchRoomUpdates(),
        builder: (context, snapshot) {
          final roomStatsList = snapshot.data ?? [];
          final roomStats = <String, Map<String, dynamic>>{
            for (var item in roomStatsList) 
              item['room'] as String: item
          };
          final htmlHotspots = _buildHotspotsHtml(roomStats);

          return ModelViewer(
            src: 'assets/3d/hospital.glb',
            alt: '3D Hospital Digital Twin',
            cameraControls: true,
            disableZoom: false,
            autoRotate: false,
            ar: false,
            interactionPrompt: InteractionPrompt.none,
            innerModelViewerHtml: htmlHotspots,
            relatedCss: _css,
            javascriptChannels: {
              JavascriptChannel(
                'RoomChannel',
                onMessageReceived: (message) {
                  _onRoomTapped(message.message);
                },
              ),
            },
          );
        },
      ),
    );
  }
}
