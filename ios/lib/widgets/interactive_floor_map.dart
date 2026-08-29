// lib/widgets/interactive_floor_map.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';
import '../models/room_position.dart';
import '../services/navigation_service.dart';

class InteractiveFloorMap extends StatefulWidget {
  final String floor;
  final String? currentLocation;
  final String? destination;
  final List<PathSegment> pathSegments;
  final VoidCallback? onRoomTapped;

  const InteractiveFloorMap({
    Key? key,
    required this.floor,
    this.currentLocation,
    this.destination,
    required this.pathSegments,
    this.onRoomTapped,
  }) : super(key: key);

  @override
  State<InteractiveFloorMap> createState() => _InteractiveFloorMapState();
}

class _InteractiveFloorMapState extends State<InteractiveFloorMap> {
  String? _svgString;
  bool _isLoading = true;
  TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _loadAndModifySvg();
  }

  @override
  void didUpdateWidget(InteractiveFloorMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.floor != widget.floor ||
        oldWidget.currentLocation != widget.currentLocation ||
        oldWidget.destination != widget.destination ||
        oldWidget.pathSegments.length != widget.pathSegments.length) {
      _loadAndModifySvg();
    }
  }

  Future<void> _loadAndModifySvg() async {
    setState(() => _isLoading = true);

    try {
      // Determine which SVG file to load
      String assetPath;
      switch (widget.floor) {
        case 'Ground Floor':
          assetPath = 'assets/maps/ground_floor.svg';
          break;
        case '1st Floor':
          assetPath = 'assets/maps/first_floor.svg';
          break;
        case '2nd Floor':
          assetPath = 'assets/maps/second_floor.svg';
          break;
        default:
          assetPath = 'assets/maps/ground_floor.svg';
      }

      // Load SVG as string
      String svgString = await rootBundle.loadString(assetPath);

      // Parse and modify SVG
      String modifiedSvg = _modifySvg(svgString);

      setState(() {
        _svgString = modifiedSvg;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading SVG: $e');
      setState(() => _isLoading = false);
    }
  }

  String _modifySvg(String svgString) {
    try {
      final document = XmlDocument.parse(svgString);

      // Get destination position
      RoomPosition? destPos;
      if (widget.destination != null) {
        destPos = RoomPositions.getPosition(widget.destination!, widget.floor);
      }

      // Get current location position
      RoomPosition? currentPos;
      if (widget.currentLocation != null) {
        currentPos = RoomPositions.getPosition(widget.currentLocation!, widget.floor);
      }

      // ========================================
      // HIGHLIGHT ALL PATH SEGMENTS FOR CURRENT FLOOR
      // ========================================
      final currentFloorSegments = widget.pathSegments
          .where((segment) => segment.floor == widget.floor)
          .toList();

      print('🗺️ Highlighting ${currentFloorSegments.length} path segments on ${widget.floor}');

      for (var segment in currentFloorSegments) {
        if (segment.pathId.isEmpty) continue;

        print('  → Looking for path: ${segment.pathId}');

        // Find the path element by ID
        final pathElement = document.findAllElements('path')
            .firstWhere(
              (element) => element.getAttribute('id') == segment.pathId,
          orElse: () => XmlElement(XmlName('path')), // dummy element
        );

        if (pathElement.getAttribute('id') == segment.pathId) {
          print('  ✅ Found and highlighting: ${segment.pathId}');

          // Make path visible with blue color and animation
          pathElement.setAttribute('stroke', '#2196F3');
          pathElement.setAttribute('stroke-width', '8');
          pathElement.setAttribute('opacity', '0.9');
          pathElement.setAttribute('stroke-dasharray', '10,5');
          pathElement.setAttribute('stroke-linecap', 'round');
          pathElement.setAttribute('stroke-linejoin', 'round');

          // Add animation element for moving dashes
          // Remove existing animate elements first
          pathElement.children.removeWhere((child) => child is XmlElement && child.name.local == 'animate');

          final animateElement = XmlElement(XmlName('animate'));
          animateElement.setAttribute('attributeName', 'stroke-dashoffset');
          animateElement.setAttribute('from', '0');
          animateElement.setAttribute('to', '-30');
          animateElement.setAttribute('dur', '1s');
          animateElement.setAttribute('repeatCount', 'indefinite');
          pathElement.children.add(animateElement);
        } else {
          print('  ❌ Path not found: ${segment.pathId}');
        }
      }

      // ========================================
      // POSITION CURRENT LOCATION MARKER
      // ========================================
      if (currentPos != null) {
        final markerIds = [
          'current_location_marker',
          'current_location_marker_1f',
          'current_location_marker_2f'
        ];

        XmlElement? currentMarker;
        for (var markerId in markerIds) {
          currentMarker = document.findAllElements('g')
              .firstWhere(
                (element) => element.getAttribute('id') == markerId,
            orElse: () => XmlElement(XmlName('g')),
          );
          if (currentMarker.getAttribute('id') == markerId) break;
        }

        if (currentMarker != null && currentMarker.getAttribute('id') != null) {
          currentMarker.setAttribute('opacity', '1');
          currentMarker.setAttribute('transform', 'translate(${currentPos.x}, ${currentPos.y})');
          print('📍 Current location marker positioned at (${currentPos.x}, ${currentPos.y})');
        }
      }

      // ========================================
      // POSITION DESTINATION MARKER
      // ========================================
      if (destPos != null) {
        final markerIds = [
          'destination_marker',
          'destination_marker_1f',
          'destination_marker_2f'
        ];

        XmlElement? destMarker;
        for (var markerId in markerIds) {
          destMarker = document.findAllElements('g')
              .firstWhere(
                (element) => element.getAttribute('id') == markerId,
            orElse: () => XmlElement(XmlName('g')),
          );
          if (destMarker.getAttribute('id') == markerId) break;
        }

        if (destMarker != null && destMarker.getAttribute('id') != null) {
          destMarker.setAttribute('opacity', '1');
          destMarker.setAttribute('transform', 'translate(${destPos.x}, ${destPos.y})');
          print('🎯 Destination marker positioned at (${destPos.x}, ${destPos.y})');
        }
      }

      // ========================================
      // HIGHLIGHT DESTINATION ROOM
      // ========================================
      if (destPos != null) {
        final roomElement = document.findAllElements('rect')
            .firstWhere(
              (element) => element.getAttribute('id') == destPos?.roomId,
          orElse: () => XmlElement(XmlName('rect')),
        );

        if (roomElement.getAttribute('id') == destPos.roomId) {
          // Add glow effect to destination room
          roomElement.setAttribute('filter', 'url(#glow)');

          // Add glow filter definition if not exists
          var defs = document.findAllElements('defs').firstOrNull;
          if (defs == null) {
            defs = XmlElement(XmlName('defs'));
            document.rootElement.children.insert(0, defs);
          }

          // Check if glow filter already exists
          final existingFilter = defs.findAllElements('filter')
              .firstWhere(
                (element) => element.getAttribute('id') == 'glow',
            orElse: () => XmlElement(XmlName('filter')),
          );

          if (existingFilter.getAttribute('id') != 'glow') {
            // Create glow filter
            final filter = XmlElement(XmlName('filter'));
            filter.setAttribute('id', 'glow');
            filter.setAttribute('x', '-50%');
            filter.setAttribute('y', '-50%');
            filter.setAttribute('width', '200%');
            filter.setAttribute('height', '200%');

            final feGaussianBlur = XmlElement(XmlName('feGaussianBlur'));
            feGaussianBlur.setAttribute('stdDeviation', '4');
            feGaussianBlur.setAttribute('result', 'coloredBlur');

            final feMerge = XmlElement(XmlName('feMerge'));
            final feMergeNode1 = XmlElement(XmlName('feMergeNode'));
            feMergeNode1.setAttribute('in', 'coloredBlur');
            final feMergeNode2 = XmlElement(XmlName('feMergeNode'));
            feMergeNode2.setAttribute('in', 'SourceGraphic');

            feMerge.children.addAll([feMergeNode1, feMergeNode2]);
            filter.children.addAll([feGaussianBlur, feMerge]);
            defs.children.add(filter);
          }

          print('✨ Destination room highlighted: ${destPos.roomId}');
        }
      }

      return document.toXmlString(pretty: true);
    } catch (e) {
      print('❌ Error modifying SVG: $e');
      return svgString;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 400,
        alignment: Alignment.center,
        child: CircularProgressIndicator(),
      );
    }

    if (_svgString == null) {
      return Container(
        height: 400,
        alignment: Alignment.center,
        child: Text('Error loading map'),
      );
    }

    return Container(
      height: 500,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Interactive SVG with zoom and pan
            InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 3.0,
              boundaryMargin: EdgeInsets.all(20),
              child: SvgPicture.string(
                _svgString!,
                fit: BoxFit.contain,
              ),
            ),

            // Zoom controls
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'zoom_in',
                    onPressed: _zoomIn,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.add, color: Colors.blue),
                  ),
                  SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoom_out',
                    onPressed: _zoomOut,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.remove, color: Colors.blue),
                  ),
                  SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'reset_zoom',
                    onPressed: _resetZoom,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.center_focus_strong, color: Colors.blue),
                  ),
                ],
              ),
            ),

            // Floor label
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.floor,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),

            // Path info indicator (shows active segments)
            if (widget.pathSegments.where((s) => s.floor == widget.floor).isNotEmpty)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.navigation, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Active Route',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _zoomIn() {
    final matrix = _transformationController.value.clone();
    matrix.scale(1.2);
    _transformationController.value = matrix;
  }

  void _zoomOut() {
    final matrix = _transformationController.value.clone();
    matrix.scale(0.8);
    _transformationController.value = matrix;
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }
}