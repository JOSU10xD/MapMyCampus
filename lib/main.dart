// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  // Remove debug banner
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Campus Navigation',
      debugShowCheckedModeBanner: false, // Remove debug banner
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B73FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      home: const MapScreen(),
    );
  }
}

///// --- Data models
class Node {
  final String id;
  final String name;
  final double x;
  final double y;
  final int floor;
  Node(
      {required this.id,
      required this.name,
      required this.x,
      required this.y,
      required this.floor});
}

class Edge {
  final String from;
  final String to;
  final double cost;
  Edge({required this.from, required this.to, required this.cost});
}

///// --- Main screen
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  final GlobalKey _svgKey = GlobalKey();
  late AnimationController _animationController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Graph data
  Map<String, Node> nodes = {};
  List<Edge> edges = [];

  // Segments: each entry contains from,to,a,b (Offset)
  List<Map<String, dynamic>> segments = [];

  // Route & marker
  List<String> currentRoute = [];
  Offset markerMapPos = Offset.zero;
  double markerAngle = 0.0;
  String? selectedFrom, selectedTo;

  // Navigation control
  Timer? _navigationTimer;
  // double _navigationSpeed = 0.0; // Removed

  // Reroute & off-path
  Timer? offPathTimer;
  bool isOffRoute = false;

  // tuning params
  final double snapRadius = 80.0;
  final double reachNodeThreshold = 14.0;
  final Duration rerouteDelay = const Duration(seconds: 4);

  // zoom limits
  final double minScale = 0.5;
  final double maxScale = 5.0;

  // Animation for camera focus
  bool _isAnimating = false;

  // UI state
  bool _isLoggedIn = false;
  String _username = '';

  // Joystick state
  bool _upPressed = false;
  bool _downPressed = false;
  bool _leftPressed = false;
  bool _rightPressed = false;
  Timer? _joystickTimer;

  // Current segment info
  Map<String, dynamic>? _currentSegment;
  int _currentRouteIndex = 0;

  // Destination reached state
  bool _destinationReached = false;

  // Navigation Mode
  bool _isAutoMode = false; // false = Manual, true = Auto

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    loadAssets();
  }

  @override
  void dispose() {
    _animationController.dispose();
    offPathTimer?.cancel();
    _navigationTimer?.cancel();
    _joystickTimer?.cancel();
    super.dispose();
  }

  Future<void> loadAssets() async {
    // Load nodes.json & edges.json from assets
    final nodesJson =
        jsonDecode(await rootBundle.loadString('assets/nodes.json')) as List;
    final edgesJson =
        jsonDecode(await rootBundle.loadString('assets/edges.json')) as List;

    nodes = {
      for (var n in nodesJson)
        n['id']: Node(
          id: n['id'],
          name: n['name'] ?? n['id'],
          x: (n['x'] as num).toDouble(),
          y: (n['y'] as num).toDouble(),
          floor: n['floor'] ?? 0,
        )
    };

    edges = [
      for (var e in edgesJson)
        Edge(from: e['from'], to: e['to'], cost: (e['cost'] as num).toDouble())
    ];

    // ensure undirected by adding mirrored edges (safe for pathfinding)
    final mirrored = <Edge>[];
    for (var e in edges) {
      mirrored.add(Edge(from: e.to, to: e.from, cost: e.cost));
    }
    edges.addAll(mirrored);

    // build segments list
    segments = edges.map((e) {
      final a = Offset(nodes[e.from]!.x, nodes[e.from]!.y);
      final b = Offset(nodes[e.to]!.x, nodes[e.to]!.y);
      return {'from': e.from, 'to': e.to, 'a': a, 'b': b};
    }).toList();

    // initial marker position
    if (nodes.isNotEmpty) {
      final first = nodes.values.first;
      markerMapPos = Offset(first.x, first.y);
    }
    setState(() {});
  }

  // ------------ geometry helpers ------------
  double _distance(Offset a, Offset b) =>
      sqrt((a.dx - b.dx) * (a.dx - b.dx) + (a.dy - b.dy) * (a.dy - b.dy));

  Offset projectPointToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return a;
    var t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    return Offset(a.dx + t * dx, a.dy + t * dy);
  }

  /// find best projection among ALL segments but only if within snapRadius
  Map<String, dynamic>? findNearestSegmentWithin(Offset p, double maxRadius) {
    double best = double.infinity;
    Map<String, dynamic>? bestEntry;
    for (int i = 0; i < segments.length; i++) {
      final s = segments[i];
      final a = s['a'] as Offset;
      final b = s['b'] as Offset;
      final proj = projectPointToSegment(p, a, b);
      final d = _distance(p, proj);
      if (d < best && d <= maxRadius) {
        best = d;
        bestEntry = {
          'index': i,
          'from': s['from'],
          'to': s['to'],
          'proj': proj,
          'dist': d,
          'a': a,
          'b': b
        };
      }
    }
    return bestEntry;
  }

  /// If route active, build polyline segments from currentRoute
  List<Map<String, dynamic>> _routeSegments() {
    final segs = <Map<String, dynamic>>[];
    for (int i = 0; i < currentRoute.length - 1; i++) {
      final a = Offset(nodes[currentRoute[i]]!.x, nodes[currentRoute[i]]!.y);
      final b =
          Offset(nodes[currentRoute[i + 1]]!.x, nodes[currentRoute[i + 1]]!.y);
      segs.add({
        'a': a,
        'b': b,
        'from': currentRoute[i],
        'to': currentRoute[i + 1],
      });
    }
    return segs;
  }

  /// project to route polyline (returns best projection or null)
  Map<String, dynamic>? projectOntoRoute(Offset p) {
    if (currentRoute.length < 2) return null;
    double best = double.infinity;
    Map<String, dynamic>? bestRes;
    final segs = _routeSegments();
    for (int i = 0; i < segs.length; i++) {
      final a = segs[i]['a']!;
      final b = segs[i]['b']!;
      final proj = projectPointToSegment(p, a, b);
      final d = _distance(p, proj);
      if (d < best) {
        best = d;
        bestRes = {
          'segIndex': i,
          'from': segs[i]['from'],
          'to': segs[i]['to'],
          'proj': proj,
          'dist': d,
          'a': a,
          'b': b
        };
      }
    }
    return bestRes;
  }

  // ------------ pathfinding (A*) ------------
  List<String>? computePath(String startId, String goalId) {
    if (!nodes.containsKey(startId) || !nodes.containsKey(goalId)) return null;
    final open = <String>{startId};
    final cameFrom = <String, String>{};
    final gScore = <String, double>{
      for (var k in nodes.keys) k: double.infinity
    };
    final fScore = <String, double>{
      for (var k in nodes.keys) k: double.infinity
    };

    gScore[startId] = 0;
    fScore[startId] = _heuristic(startId, goalId);

    String? pickLowestF() {
      String? best;
      double bestV = double.infinity;
      for (var id in open) {
        final v = fScore[id] ?? double.infinity;
        if (v < bestV) {
          bestV = v;
          best = id;
        }
      }
      return best;
    }

    while (open.isNotEmpty) {
      final current = pickLowestF();
      if (current == null) break;
      if (current == goalId) {
        final path = <String>[];
        var cur = current;
        while (true) {
          path.insert(0, cur);
          if (!cameFrom.containsKey(cur)) break;
          cur = cameFrom[cur]!;
        }
        return path;
      }
      open.remove(current);
      for (var e in edges.where((ed) => ed.from == current)) {
        final tentative = (gScore[current] ?? double.infinity) + e.cost;
        if (tentative < (gScore[e.to] ?? double.infinity)) {
          cameFrom[e.to] = current;
          gScore[e.to] = tentative;
          fScore[e.to] = tentative + _heuristic(e.to, goalId);
          open.add(e.to);
        }
      }
    }
    return null;
  }

  double _heuristic(String aId, String bId) {
    final a = nodes[aId]!;
    final b = nodes[bId]!;
    return _distance(Offset(a.x, a.y), Offset(b.x, b.y));
  }

  void _stopNavigation() {
    _navigationTimer?.cancel();
    // _navigationSpeed = 0;
    setState(() {});
  }

  // Handle destination reached
  void _handleDestinationReached() {
    if (_destinationReached) return; // Prevent multiple triggers

    setState(() {
      _destinationReached = true;
    });

    // Stop all navigation
    _stopNavigation();
    _joystickTimer?.cancel();

    // Show destination reached popup
    _showDestinationReachedDialog();
  }

  // Show destination reached dialog
  void _showDestinationReachedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFF6B73FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Destination Reached!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have successfully arrived at:',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  nodes[selectedTo!]?.name ?? 'Destination',
                  style: const TextStyle(
                    color: Color(0xFF6B73FF),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Navigation has been stopped.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _destinationReached = false;
                  selectedFrom = null;
                  selectedTo = null;
                });
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text('CLOSE'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _destinationReached = false;
                  // Keep the current destination for potential reuse
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B73FF),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('NEW ROUTE'),
            ),
          ],
        );
      },
    );
  }

  void setCurrentRoute(List<String> route) {
    currentRoute = route;
    _currentRouteIndex = 0;
    _destinationReached = false; // Reset destination reached flag

    if (currentRoute.isNotEmpty) {
      final start = nodes[currentRoute.first]!;
      markerMapPos = Offset(start.x, start.y);

      // Set current segment
      if (currentRoute.length > 1) {
        final next = nodes[currentRoute[1]]!;
        _currentSegment = {
          'a': markerMapPos,
          'b': Offset(next.x, next.y),
          'from': currentRoute[0],
          'to': currentRoute[1],
        };

        // Calculate initial angle
        final dx = next.x - start.x;
        final dy = next.y - start.y;
        markerAngle = atan2(dy, dx) + pi / 2;
      }

      // Focus camera on the marker and rotate map
      _focusCameraOnMarker();
      _rotateMapToDirection();
    }
    setState(() {});
  }

  // ------------ camera focus animation ------------
  void _focusCameraOnMarker() {
    if (_isAnimating) return;

    final screenSize = MediaQuery.of(context).size;
    final markerScreenPos = _mapToScreen(markerMapPos);
    final currentMatrix = _controller.value;

    // Calculate the desired translation to center the marker
    final desiredScreenCenter =
        Offset(screenSize.width / 2, screenSize.height / 2);

    final translationAdjustment = desiredScreenCenter - markerScreenPos;

    // Create a tween for the animation
    final beginMatrix = currentMatrix;
    final endMatrix = Matrix4.identity()
      ..translate(
        currentMatrix[12] + translationAdjustment.dx,
        currentMatrix[13] + translationAdjustment.dy,
      )
      ..scale(currentMatrix[0]); // Keep the same scale

    // Animate the transformation
    _isAnimating = true;
    _animationController.reset();
    final animation = Matrix4Tween(begin: beginMatrix, end: endMatrix).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    animation.addListener(() {
      _controller.value = animation.value;
    });

    _animationController.forward().then((_) {
      _isAnimating = false;
    });
  }

  // Rotate map to match current direction
  void _rotateMapToDirection() {
    if (_currentSegment == null) return;

    final a = _currentSegment!['a'] as Offset;
    final b = _currentSegment!['b'] as Offset;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;

    // We want the segment vector (dx, dy) to point UP on the screen.
    // Screen UP is -Y (angle -pi/2).
    final segmentAngle = atan2(dy, dx);
    final rotationAngle = -pi / 2 - segmentAngle;

    final screenSize = MediaQuery.of(context).size;
    final focalPoint = Offset(screenSize.width / 2, screenSize.height / 2);

    // Get current scale, default to 1.0 if not set
    final currentMatrix = _controller.value;
    final scale = currentMatrix.getMaxScaleOnAxis();

    // Rebuild matrix from scratch to ensure marker is centered
    // M = T(center) * R(angle) * S(scale) * T(-marker)
    final newMatrix = Matrix4.identity()
      ..translate(focalPoint.dx, focalPoint.dy)
      ..rotateZ(rotationAngle)
      ..scale(scale)
      ..translate(-markerMapPos.dx, -markerMapPos.dy);

    _controller.value = newMatrix;
  }

  // Convert map coordinates to screen coordinates
  Offset _mapToScreen(Offset mapOffset) {
    final matrix = _controller.value;
    final transformed =
        matrix.transform3(vm.Vector3(mapOffset.dx, mapOffset.dy, 0));
    return Offset(transformed.x, transformed.y);
  }

  // ------------ zoom helpers ------------
  double _currentScale() => _controller.value.getMaxScaleOnAxis();

  void zoomBy(double factor) {
    final double curScale = _currentScale();
    double targetScale = (curScale * factor).clamp(minScale, maxScale);
    if ((targetScale - curScale).abs() < 1e-9) return;
    
    // We want to zoom while keeping the marker centered (since we are in navigation mode)
    // If we are not navigating, we might want standard zoom. 
    // But given the requirement "rotate map with arrow as its middle", 
    // it implies the arrow (marker) is the anchor.
    
    final screenSize = MediaQuery.of(context).size;
    final focalPoint = Offset(screenSize.width / 2, screenSize.height / 2);

    // If we simply scale the matrix, we need to make sure we respect the current rotation and translation
    // Re-calculating the matrix using _rotateMapToDirection logic with new scale is safest
    // but _rotateMapToDirection relies on _currentSegment.
    
    if (_currentSegment != null) {
       // We are navigating, so rebuild matrix with new scale
       final a = _currentSegment!['a'] as Offset;
       final b = _currentSegment!['b'] as Offset;
       final dx = b.dx - a.dx;
       final dy = b.dy - a.dy;
       final segmentAngle = atan2(dy, dx);
       final rotationAngle = -pi / 2 - segmentAngle;
       
       final newMatrix = Matrix4.identity()
        ..translate(focalPoint.dx, focalPoint.dy)
        ..rotateZ(rotationAngle)
        ..scale(targetScale)
        ..translate(-markerMapPos.dx, -markerMapPos.dy);
       
       _controller.value = newMatrix;
    } else {
       // Standard zoom if not navigating (fallback)
       final double effectiveFactor = targetScale / curScale;
       final Offset focal = Offset(
          screenSize.width / 2,
          (kToolbarHeight + 20) +
              (screenSize.height - (kToolbarHeight + 20)) / 2);
       final vm.Matrix4 t1 = vm.Matrix4.identity()
        ..translate(-focal.dx, -focal.dy);
       final vm.Matrix4 s = vm.Matrix4.identity()
        ..scale(effectiveFactor, effectiveFactor, 1.0);
       final vm.Matrix4 t2 = vm.Matrix4.identity()..translate(focal.dx, focal.dy);
       final vm.Matrix4 newMatrix = t2 * s * t1 * _controller.value;
       _controller.value = newMatrix;
    }
  }

  void zoomIn() => zoomBy(1.25);
  void zoomOut() => zoomBy(1 / 1.25);

  // Intersection state
  bool _showTurnControls = false;
  final List<String> _validTurnDirections = []; // 'left', 'right', 'straight'
  String _correctTurnDirection = ''; // 'left', 'right', 'straight'
  bool _ignoreNextUpRelease = false; // To prevent accidental straight selection

  // ------------ joystick control ------------
  void _startJoystick() {
    _joystickTimer?.cancel();
    _joystickTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      // If destination is reached, allow backward movement only
      if (_destinationReached) {
        if (!_downPressed) {
           _stopNavigation();
           return;
        }
        // If down pressed, we allow movement to potentially back away
      }

      // If we have a current route
      if (currentRoute.isNotEmpty) {
        if (_isAutoMode) {
           // Only move if the "Drive" button is held (reusing _upPressed)
           if (_upPressed) {
             _moveAutomaticallyOnRoute();
           }
        } else {
           // Manual mode
           if (!_upPressed && !_downPressed && !_leftPressed && !_rightPressed) {
             return;
           }
           _moveManuallyOnRoute();
        }
      }
    });
  }



  void _moveAutomaticallyOnRoute() {
    if (_currentRouteIndex >= currentRoute.length - 1) return;

    final nextNode = nodes[currentRoute[_currentRouteIndex + 1]]!;
    final currentNode = nodes[currentRoute[_currentRouteIndex]]!;
    
    final currentPos = markerMapPos;
    final targetPos = Offset(nextNode.x, nextNode.y);
    final startPos = Offset(currentNode.x, currentNode.y);

    // Calculate direction along the segment
    final dx = targetPos.dx - startPos.dx;
    final dy = targetPos.dy - startPos.dy;
    final segmentDist = _distance(startPos, targetPos);
    
    if (segmentDist == 0) return;
    
    final dirX = dx / segmentDist;
    final dirY = dy / segmentDist;

    // Auto mode always moves forward
    double moveSpeed = 2.0; 

    // Calculate potential new position
    var newPos = Offset(
      currentPos.dx + dirX * moveSpeed,
      currentPos.dy + dirY * moveSpeed,
    );

    final distToTarget = _distance(currentPos, targetPos);
       
    // If we are close enough OR we overshot
    if (distToTarget <= moveSpeed || _distance(newPos, startPos) > segmentDist) {
      // We reached the node.
      
      // Check if this is the final destination
      if (_currentRouteIndex >= currentRoute.length - 2) {
         setState(() {
           markerMapPos = targetPos;
           markerAngle = atan2(dy, dx) + pi / 2;
         });
         _handleDestinationReached();
         return;
      }

      // We are at an intermediate node.
      // In AUTO mode, we simply advance to the next segment.
      // The pathfinding already determined the correct sequence of nodes.
      
      double overshoot = moveSpeed - distToTarget;
      if (overshoot < 0) overshoot = 0;
      
      // Advance segment immediately
      _advanceSegment(); 
      
      // Apply overshoot to the NEW segment
      if (_currentSegment != null) {
          final newStart = _currentSegment!['a'] as Offset;
          final newEnd = _currentSegment!['b'] as Offset;
          final newDx = newEnd.dx - newStart.dx;
          final newDy = newEnd.dy - newStart.dy;
          final newLen = _distance(newStart, newEnd);
          
          if (newLen > 0) {
            final newDirX = newDx / newLen;
            final newDirY = newDy / newLen;
            
            final carriedPos = Offset(
              newStart.dx + newDirX * overshoot,
              newStart.dy + newDirY * overshoot
            );
            
            setState(() {
              markerMapPos = carriedPos;
              markerAngle = atan2(newDy, newDx) + pi / 2;
              _rotateMapToDirection();
            });
          }
      }
      return; 
    } 

    // Update position (moving along segment)
    setState(() {
      markerMapPos = newPos;
      markerAngle = atan2(dy, dx) + pi / 2;
      _rotateMapToDirection();
    });
  }

  void _moveManuallyOnRoute() {
    // If waiting for turn selection, don't move
    if (_showTurnControls) return;

    if (_currentRouteIndex >= currentRoute.length - 1) return;

    final nextNode = nodes[currentRoute[_currentRouteIndex + 1]]!;
    final currentNode = nodes[currentRoute[_currentRouteIndex]]!;
    
    final currentPos = markerMapPos;
    final targetPos = Offset(nextNode.x, nextNode.y);
    final startPos = Offset(currentNode.x, currentNode.y);

    // Calculate direction along the segment
    final dx = targetPos.dx - startPos.dx;
    final dy = targetPos.dy - startPos.dy;
    final segmentDist = _distance(startPos, targetPos);
    
    if (segmentDist == 0) return;
    
    final dirX = dx / segmentDist;
    final dirY = dy / segmentDist;

    // Determine movement direction based on input
    double moveSpeed = 0.0;
    if (_upPressed) moveSpeed = 2.0; // Human walking speed
    if (_downPressed) moveSpeed = -2.0;

    if (moveSpeed == 0) return;

    // Calculate potential new position
    var newPos = Offset(
      currentPos.dx + dirX * moveSpeed,
      currentPos.dy + dirY * moveSpeed,
    );

    // Check if we reached the target node (forward movement)
    if (moveSpeed > 0) {
       final distToTarget = _distance(currentPos, targetPos);
       
       // If we are close enough OR we overshot
       if (distToTarget <= moveSpeed || _distance(newPos, startPos) > segmentDist) {
         // We reached the node.
         
         // Check for intersection logic FIRST
         // We need to know if we should stop or continue smoothly.
         
         // Check if this is the final destination
         if (_currentRouteIndex >= currentRoute.length - 2) {
            setState(() {
              markerMapPos = targetPos;
              markerAngle = atan2(dy, dx) + pi / 2;
            });
            _handleDestinationReached();
            return;
         }

         final nodeId = currentRoute[_currentRouteIndex + 1];
         // Check exits
         final connectedEdges = edges.where((e) => e.from == nodeId).toList();
         final incomingNodeId = currentRoute[_currentRouteIndex];
         
         // Filter valid exits and ensure uniqueness (handle duplicate edges)
         final validExits = connectedEdges
             .where((e) => e.to != incomingNodeId)
             .map((e) => e.to)
             .toSet()
             .toList();

         if (validExits.length == 1) {
            // STRAIGHT PATH (or only one way to go).
            // SMOOTH MOVEMENT: Advance segment and carry over the remaining distance.
            
            double overshoot = moveSpeed - distToTarget;
            if (overshoot < 0) overshoot = 0; // Should not happen if logic is correct
            
            // Advance segment immediately
            _advanceSegment(); // This updates _currentRouteIndex, _currentSegment, markerMapPos (to start of new), markerAngle
            
            // Now apply overshoot to the NEW segment
            // _advanceSegment sets markerMapPos to the *start* of the new segment (which is the node we just reached)
            
            if (_currentSegment != null) {
               final newStart = _currentSegment!['a'] as Offset;
               final newEnd = _currentSegment!['b'] as Offset;
               final newDx = newEnd.dx - newStart.dx;
               final newDy = newEnd.dy - newStart.dy;
               final newLen = _distance(newStart, newEnd);
               
               if (newLen > 0) {
                 final newDirX = newDx / newLen;
                 final newDirY = newDy / newLen;
                 
                 final carriedPos = Offset(
                    newStart.dx + newDirX * overshoot,
                    newStart.dy + newDirY * overshoot
                 );
                 
                 setState(() {
                    markerMapPos = carriedPos;
                    // Angle is already updated by _advanceSegment, but let's ensure
                    markerAngle = atan2(newDy, newDx) + pi / 2;
                    // Update map rotation to keep marker centered and up
                    _rotateMapToDirection();
                 });
               }
            }
            return; // Done for this frame
         } else {
            // INTERSECTION (Multiple choices).
            // We MUST stop here.
            setState(() {
              markerMapPos = targetPos;
              markerAngle = atan2(dy, dx) + pi / 2;
              _rotateMapToDirection();
            });
            _checkForIntersection(nodeId);
            return;
         }
       }
    } 
    
    // Backward movement or normal forward movement (not reaching node yet)
    // Constrain to segment
    bool reachedStart = false;
    
    if (moveSpeed < 0) {
       if (_distance(newPos, startPos) < reachNodeThreshold) {
         newPos = startPos;
         reachedStart = true;
       }
    }

    // Update position
    setState(() {
      markerMapPos = newPos;
      // Ensure arrow points along the path (forward)
      markerAngle = atan2(dy, dx) + pi / 2;
      // Keep map centered on marker
      _rotateMapToDirection();
    });

    if (reachedStart) {
       // Moved back to start of segment. 
       if (_currentRouteIndex > 0) {
         _currentRouteIndex--;
         final prevNode = nodes[currentRoute[_currentRouteIndex]]!;
         final currNode = nodes[currentRoute[_currentRouteIndex + 1]]!;
         _currentSegment = {
            'a': Offset(prevNode.x, prevNode.y),
            'b': Offset(currNode.x, currNode.y),
            'from': currentRoute[_currentRouteIndex],
            'to': currentRoute[_currentRouteIndex + 1],
         };
         markerMapPos = startPos;
         _rotateMapToDirection();
       }
    }
  }

  void _checkForIntersection(String nodeId, {bool dryRun = false}) {
    // Find all edges connected to this node
    final connectedEdges = edges.where((e) => e.from == nodeId).toList();
    
    // Filter out the edge we just came from
    final incomingNodeId = currentRoute[_currentRouteIndex];
    
    // Use Set to handle duplicate edges
    final validExitIds = connectedEdges
        .where((e) => e.to != incomingNodeId)
        .map((e) => e.to)
        .toSet()
        .toList();

    if (validExitIds.isEmpty) return; // Dead end?

    if (validExitIds.length == 1) {
       // Only one way forward. Just advance the segment.
       if (!dryRun) _advanceSegment();
       return;
    }

    // Multiple choices (Intersection)
    // Use addPostFrameCallback to avoid setState during build/layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showTurnControls = true;
        // Ignore the release of the current 'up' press to prevent accidental selection
        if (_upPressed) {
          _ignoreNextUpRelease = true;
        }
        
        _validTurnDirections.clear();
        _correctTurnDirection = '';

        // Calculate angles to determine Left/Right/Straight
        // Incoming vector
        final incomingNode = nodes[incomingNodeId]!;
        final currentNode = nodes[nodeId]!;
        final inDx = currentNode.x - incomingNode.x;
        final inDy = currentNode.y - incomingNode.y;
        final inAngle = atan2(inDy, inDx);

        // Check bounds before accessing _currentRouteIndex + 2
        String? nextRouteNodeId;
        if (_currentRouteIndex + 2 < currentRoute.length) {
          nextRouteNodeId = currentRoute[_currentRouteIndex + 2];
        }

        for (var exitId in validExitIds) {
          final exitNode = nodes[exitId]!;
          final outDx = exitNode.x - currentNode.x;
          final outDy = exitNode.y - currentNode.y;
          final outAngle = atan2(outDy, outDx);

          // Calculate relative angle
          var diff = outAngle - inAngle;
          // Normalize to -pi to pi
          while (diff > pi) diff -= 2 * pi;
          while (diff <= -pi) diff += 2 * pi;

          String direction = 'straight';
          if (diff > 0.5) {
            direction = 'right';
          } else if (diff < -0.5) {
            direction = 'left';
          }
          
          // Store mapping or just check if it's the correct one
          if (nextRouteNodeId != null && exitId == nextRouteNodeId) {
            _correctTurnDirection = direction;
          }
          
          _validTurnDirections.add(direction);
        }
      });
    });
  }

  void _advanceSegment() {
    if (_currentRouteIndex < currentRoute.length - 2) {
      _currentRouteIndex++;
      final prevNode = nodes[currentRoute[_currentRouteIndex]]!;
      final currNode = nodes[currentRoute[_currentRouteIndex + 1]]!;
      
      setState(() {
        _currentSegment = {
          'a': Offset(prevNode.x, prevNode.y),
          'b': Offset(currNode.x, currNode.y),
          'from': currentRoute[_currentRouteIndex],
          'to': currentRoute[_currentRouteIndex + 1],
        };
        // Snap to start of new segment (will be overwritten if smoothing is applied)
        markerMapPos = Offset(prevNode.x, prevNode.y);
        
        // Update angle
        final dx = currNode.x - prevNode.x;
        final dy = currNode.y - prevNode.y;
        markerAngle = atan2(dy, dx) + pi / 2;
        
        _showTurnControls = false;
        
        // Rotate map to new direction
        _rotateMapToDirection();
      });
    }
  }

  void _handleTurn(String direction) {
    if (!_showTurnControls) return;

    // Check bounds
    if (_currentRouteIndex + 1 >= currentRoute.length) return;

    final nodeId = currentRoute[_currentRouteIndex + 1];
    final incomingNodeId = currentRoute[_currentRouteIndex];
    final connectedEdges = edges.where((e) => e.from == nodeId).toList();
    
    // Use Set to handle duplicate edges
    final validExitIds = connectedEdges
        .where((e) => e.to != incomingNodeId)
        .map((e) => e.to)
        .toSet()
        .toList();
    
    final incomingNode = nodes[incomingNodeId]!;
    final currentNode = nodes[nodeId]!;
    final inDx = currentNode.x - incomingNode.x;
    final inDy = currentNode.y - incomingNode.y;
    final inAngle = atan2(inDy, inDx);

    String? selectedExitId;

    for (var exitId in validExitIds) {
      final exitNode = nodes[exitId]!;
      final outDx = exitNode.x - currentNode.x;
      final outDy = exitNode.y - currentNode.y;
      final outAngle = atan2(outDy, outDx);

      var diff = outAngle - inAngle;
      while (diff > pi) diff -= 2 * pi;
      while (diff <= -pi) diff += 2 * pi;

      String dir = 'straight';
      if (diff > 0.5) {
        dir = 'right';
      } else if (diff < -0.5) {
        dir = 'left';
      }

      if (dir == direction) {
        selectedExitId = exitId;
        break;
      }
    }

    if (selectedExitId != null) {
      // Check if this is the correct path
      bool isCorrect = false;
      if (_currentRouteIndex + 2 < currentRoute.length) {
         if (currentRoute[_currentRouteIndex + 2] == selectedExitId) {
           isCorrect = true;
         }
      }

      if (isCorrect) {
        _advanceSegment();
      } else {
        // Wrong turn! Reroute.
        setState(() {
          isOffRoute = true;
          _showTurnControls = false; // Hide controls while rerouting
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recalculating route...'),
            duration: Duration(seconds: 1),
          )
        );

        // Compute new path from the selected node to destination
        final newPath = computePath(selectedExitId, selectedTo!);
        if (newPath != null) {
           setCurrentRoute(newPath);
           isOffRoute = false;
        }
      }
    }
  }

  void _handleJoystickButton(bool pressed, String direction) {
    // Don't allow joystick input if destination is reached
    // Don't allow joystick input if destination is reached
    // if (_destinationReached) return; // Removed to allow backward movement

    // Handle turn buttons (Left/Right)
    if ((direction == 'left' || direction == 'right') && _showTurnControls) {
       if (!pressed) { // On release (tap)
         _handleTurn(direction);
       }
       return;
    }

    bool shouldHandleStraight = false;

    setState(() {
      switch (direction) {
        case 'up':
          if (_showTurnControls && _validTurnDirections.contains('straight')) {
             if (!pressed) {
                // On release
                if (_ignoreNextUpRelease) {
                  _ignoreNextUpRelease = false;
                } else {
                  shouldHandleStraight = true;
                }
             }
          }
          _upPressed = pressed;
          break;
        case 'down':
          _downPressed = pressed;
          break;
        case 'left':
          _leftPressed = pressed;
          break;
        case 'right':
          _rightPressed = pressed;
          break;
      }
    });

    if (shouldHandleStraight) {
      _handleTurn('straight');
    }

    if (pressed) {
      _startJoystick();
    } else if (!_upPressed &&
        !_downPressed &&
        !_leftPressed &&
        !_rightPressed) {
      _joystickTimer?.cancel();
      // _navigationSpeed = 0;
    }
  }

  // ------------ UI helpers ------------
  void _handleLogin() {
    if (_isLoggedIn) {
      setState(() {
        _isLoggedIn = false;
        _username = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged out successfully')));
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text('Login', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Username',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) => _username = value,
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: TextStyle(color: Colors.white),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B73FF),
              ),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _isLoggedIn = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: const Color(0xFF6B73FF),
                  content: Text('Welcome, $_username!',
                      style: const TextStyle(color: Colors.white)),
                ));
              },
              child: const Text('Login', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSidebar() {
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF6B73FF),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Campus Navigation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLoggedIn ? 'Welcome, $_username!' : 'Guest User',
                  style: const TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.white70),
            title: const Text('Profile', style: TextStyle(color: Colors.white)),
            onTap: () {},
          ),
          ExpansionTile(
            leading: const Icon(Icons.tune, color: Colors.white70),
            title: const Text('Navigation Mode', style: TextStyle(color: Colors.white)),
            children: [
              RadioListTile<bool>(
                title: const Text('Manual (Joystick)', style: TextStyle(color: Colors.white)),
                value: false,
                groupValue: _isAutoMode,
                activeColor: const Color(0xFF6B73FF),
                onChanged: (bool? value) {
                  setState(() {
                    _isAutoMode = value!;
                  });
                  Navigator.pop(context); // Close drawer
                },
              ),
              RadioListTile<bool>(
                title: const Text('Auto Navigation', style: TextStyle(color: Colors.white)),
                value: true,
                groupValue: _isAutoMode,
                activeColor: const Color(0xFF6B73FF),
                onChanged: (bool? value) {
                  setState(() {
                    _isAutoMode = value!;
                  });
                  Navigator.pop(context); // Close drawer
                },
              ),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.white70),
            title: const Text('Route History',
                style: TextStyle(color: Colors.white)),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.white70),
            title:
                const Text('Settings', style: TextStyle(color: Colors.white)),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.help, color: Colors.white70),
            title: const Text('Help & Feedback',
                style: TextStyle(color: Colors.white)),
            onTap: () {},
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: Icon(_isLoggedIn ? Icons.logout : Icons.login,
                color: Colors.white70),
            title: Text(_isLoggedIn ? 'Logout' : 'Login',
                style: const TextStyle(color: Colors.white)),
            onTap: _handleLogin,
          ),
        ],
      ),
    );
  }

  Widget _buildJoystick() {
    // Hide joystick when destination is reached
    if (_destinationReached) return const SizedBox.shrink();

    // Auto Mode: Show a single "Drive" button
    if (_isAutoMode) {
      return Positioned(
        right: 40,
        bottom: 40,
        child: GestureDetector(
          onTapDown: (_) {
            setState(() {
              _upPressed = true;
            });
            _startJoystick();
          },
          onTapUp: (_) {
            setState(() {
              _upPressed = false;
            });
            _joystickTimer?.cancel();
          },
          onTapCancel: () {
            setState(() {
              _upPressed = false;
            });
            _joystickTimer?.cancel();
          },
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF6B73FF),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_upward,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
      );
    }

    return Positioned(
      right: 20,
      bottom: 100,
      child: Column(
        children: [
          // Up button
          GestureDetector(
            onTapDown: (_) => _handleJoystickButton(true, 'up'),
            onTapUp: (_) => _handleJoystickButton(false, 'up'),
            onTapCancel: () => _handleJoystickButton(false, 'up'),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: _upPressed
                    ? const Color(0xFF6B73FF)
                    : const Color(0xFF6B73FF).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(35),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child:
                  const Icon(Icons.arrow_upward, color: Colors.white, size: 36),
            ),
          ),
          const SizedBox(height: 15),
          // Left/Right buttons (only show if needed)
          if (_showTurnControls)
            Row(
              children: [
                if (_validTurnDirections.contains('left'))
                  GestureDetector(
                    onTapDown: (_) => _handleJoystickButton(true, 'left'),
                    onTapUp: (_) => _handleJoystickButton(false, 'left'),
                    onTapCancel: () => _handleJoystickButton(false, 'left'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: _leftPressed
                            ? const Color(0xFF6B73FF)
                            : const Color(0xFF6B73FF).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(35),
                        boxShadow: [
                          if (_correctTurnDirection == 'left')
                            BoxShadow(
                              color: const Color(0xFF6B73FF).withValues(alpha: 0.8),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        border: _correctTurnDirection == 'left'
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 36),
                    ),
                  ),
                const SizedBox(width: 15),
                if (_validTurnDirections.contains('right'))
                  GestureDetector(
                    onTapDown: (_) => _handleJoystickButton(true, 'right'),
                    onTapUp: (_) => _handleJoystickButton(false, 'right'),
                    onTapCancel: () => _handleJoystickButton(false, 'right'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: _rightPressed
                            ? const Color(0xFF6B73FF)
                            : const Color(0xFF6B73FF).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(35),
                        boxShadow: [
                          if (_correctTurnDirection == 'right')
                            BoxShadow(
                              color: const Color(0xFF6B73FF).withValues(alpha: 0.8),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        border: _correctTurnDirection == 'right'
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: const Icon(Icons.arrow_forward,
                          color: Colors.white, size: 36),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 15),
          // Down button
          GestureDetector(
            onTapDown: (_) => _handleJoystickButton(true, 'down'),
            onTapUp: (_) => _handleJoystickButton(false, 'down'),
            onTapCancel: () => _handleJoystickButton(false, 'down'),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: _downPressed
                    ? const Color(0xFF6B73FF)
                    : const Color(0xFF6B73FF).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(35),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_downward,
                  color: Colors.white, size: 36),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControls() {
    return Positioned(
      top: 160, // Position below the navigation box
      right: 20,
      child: Column(
        children: [
          // Zoom in button
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF6B73FF),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.zoom_in, color: Colors.white),
              onPressed: zoomIn,
            ),
          ),
          const SizedBox(height: 15),
          // Zoom out button
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF6B73FF),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.zoom_out, color: Colors.white),
              onPressed: zoomOut,
            ),
          ),
          const SizedBox(height: 15),
          // Recenter button
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF6B73FF),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.my_location, color: Colors.white),
              onPressed: _focusCameraOnMarker,
            ),
          ),
        ],
      ),
    );
  }

  // ------------ UI ------------
  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary),
          ),
        ),
      );
    }

    // Build unique undirected edges for painting (avoid double-draw)
    final seen = <String>{};
    final uniqueEdges = <Edge>[];
    for (var e in edges) {
      final key = (e.from.compareTo(e.to) <= 0)
          ? '${e.from}|||${e.to}'
          : '${e.to}|||${e.from}';
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueEdges.add(e);
      }
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildSidebar(),
      appBar: AppBar(
        title: const Text('Campus Navigation - Block A Ground Floor'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Start Location',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    value: selectedFrom,
                    items: nodes.values
                        .map((node) => DropdownMenuItem(
                              value: node.id,
                              child: Text(node.name,
                                  style: const TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => selectedFrom = v),
                    icon: const Icon(Icons.arrow_drop_down,
                        color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Destination',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    value: selectedTo,
                    items: nodes.values
                        .map((node) => DropdownMenuItem(
                              value: node.id,
                              child: Text(node.name,
                                  style: const TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => selectedTo = v),
                    icon: const Icon(Icons.arrow_drop_down,
                        color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6B73FF), Color(0xFF4D55E0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6B73FF).withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.directions, color: Colors.white),
                    label: const Text('Navigate',
                        style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      if (selectedFrom == null || selectedTo == null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                          backgroundColor: Color(0xFF6B73FF),
                          content: Text(
                              'Please select both start and destination',
                              style: TextStyle(color: Colors.white)),
                        ));
                        return;
                      }
                      final route = computePath(selectedFrom!, selectedTo!);
                      if (route == null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                          backgroundColor: Color(0xFF6B73FF),
                          content: Text('No route found',
                              style: TextStyle(color: Colors.white)),
                        ));
                      } else {
                        setCurrentRoute(route);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          if (currentRoute.isNotEmpty && !_destinationReached)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isOffRoute
                    ? const Color(0x44FF9800)
                    : const Color(0x446B73FF),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.route,
                      color:
                          isOffRoute ? Colors.orange : const Color(0xFF6B73FF),
                      size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Route: ${nodes[currentRoute.first]?.name} to ${nodes[currentRoute.last]?.name}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  if (isOffRoute)
                    const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange, size: 16),
                        SizedBox(width: 4),
                        Text('Rerouting...',
                            style: TextStyle(color: Colors.orange)),
                      ],
                    ),
                ],
              ),
            ),
          if (_destinationReached)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle,
                      color: Color(0xFF4CAF50), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Destination Reached!',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4CAF50)),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _controller,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  constrained: false,
                  minScale: minScale,
                  maxScale: maxScale,
                  scaleEnabled: true,
                  child: Stack(
                    children: [
                      // map svg
                      SvgPicture.asset('assets/A_Block_Ground.svg',
                          key: _svgKey),
                      // painter overlay
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _MapPainter(
                            nodes: nodes,
                            edges: uniqueEdges,
                            currentRoute: currentRoute,
                            isOffRoute: isOffRoute,
                          ),
                        ),
                      ),
                      // marker overlay (positioned in same child coordinate space)
                      Positioned(
                        left: markerMapPos.dx - 20,
                        top: markerMapPos.dy - 20,
                        width: 40,
                        height: 40,
                        child: Transform.rotate(
                          angle: markerAngle,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _destinationReached
                                  ? const Color(0xFF4CAF50)
                                  : Colors.white,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color.fromRGBO(0, 0, 0, 0.4),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ],
                              border: Border.all(
                                color: isOffRoute
                                    ? Colors.orange
                                    : _destinationReached
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFF6B73FF),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.arrow_upward,
                                size: 24,
                                color: isOffRoute
                                    ? Colors.orange
                                    : _destinationReached
                                        ? Colors.white
                                        : const Color(0xFF6B73FF),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildJoystick(),
                _buildZoomControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Painter draws the base edges and the current route (blue)
class _MapPainter extends CustomPainter {
  final Map<String, Node> nodes;
  final List<Edge> edges;
  final List<String> currentRoute;
  final bool isOffRoute;

  _MapPainter({
    required this.nodes,
    required this.edges,
    required this.currentRoute,
    required this.isOffRoute,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintEdge = Paint()
      ..color = Colors.grey.shade700
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintRoute = Paint()
      ..color = isOffRoute ? Colors.orange : const Color(0xFF6B73FF)
      ..strokeWidth = 16
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintNode = Paint()..color = Colors.white;

    // draw edges
    for (var e in edges) {
      if (!nodes.containsKey(e.from) || !nodes.containsKey(e.to)) continue;
      final a = Offset(nodes[e.from]!.x, nodes[e.from]!.y);
      final b = Offset(nodes[e.to]!.x, nodes[e.to]!.y);
      canvas.drawLine(a, b, paintEdge);
    }

    // draw route polyline (remaining nodes)
    if (currentRoute.isNotEmpty) {
      final path = Path();
      for (int i = 0; i < currentRoute.length; i++) {
        final id = currentRoute[i];
        if (!nodes.containsKey(id)) continue;
        final p = Offset(nodes[id]!.x, nodes[id]!.y);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paintRoute);
    }

    // draw nodes (small)
    for (var n in nodes.values) {
      canvas.drawCircle(Offset(n.x, n.y), 4, paintNode);
    }

    // Draw node labels for important nodes
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      shadows: [
        Shadow(
          blurRadius: 2.0,
          color: Colors.black,
          offset: Offset(1.0, 1.0),
        ),
      ],
    );
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Draw labels only for key nodes to avoid clutter
    const keyNodes = [
      'Lobby_Centre',
      'Cross-A-Ground',
      'Stairs_mid',
      'porch_Blocka'
    ];
    for (var n in nodes.values) {
      if (keyNodes.contains(n.id)) {
        textPainter.text = TextSpan(
          text: n.name,
          style: textStyle,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(n.x - textPainter.width / 2, n.y - 20),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.currentRoute != currentRoute || old.isOffRoute != isOffRoute;
}
