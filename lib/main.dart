// lib/main.dart
// This is the main entry point for the Campus Navigation application.
/// It sets up the Flutter environment, initializes the app theme, and launches the [MapScreen].
/// 
/// Key features include:
/// - Interactive map with pan and zoom.
/// - Floor switching (Ground vs First Floor).
/// - Pathfinding (A*) between nodes.
/// - Manual (Joystick) and Automatic navigation modes.

import 'dart:async'; // [Key Concept] 'import' makes code from other libraries available. 'dart:async' handles Timers and Futures.
import 'dart:convert'; // [Method] jsonDecode comes from here, used to parse JSON strings into Dart objects.
import 'dart:math'; // [Method] Provides mathematical constants and functions like sqrt() and atan2().
import 'package:flutter/material.dart'; // [Framework] The core Flutter UI library containing widgets like MaterialApp, Scaffold, etc.
import 'package:flutter/services.dart'; // [Framework] Access to platform services like status bar control (SystemChrome) and asset loading (rootBundle).
import 'package:flutter_svg/flutter_svg.dart'; // [External Package] A third-party package for rendering SVG images.
import 'package:vector_math/vector_math_64.dart' as vm; // [Keyword] 'as' allows us to give a library a prefix (vm) to avoid naming conflicts.

// [Keyword] 'void' indicates this function returns no value.
// [Method] 'main' is the entry point of every Dart application.
void main() {
  // [Method] ensureInitialized() ensures that the Flutter binding (bridge between framework and engine) is ready before using platform channels.
  WidgetsFlutterBinding.ensureInitialized();
  // [Method] setEnabledSystemUIMode controls the visibility of system overlays (status bar, nav bar).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // [Method] runApp() inflates the given widget (MyApp) and attaches it to the screen.
  // [Keyword] 'const' creates a compile-time constant, optimizing performance by creating the object only once.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  // [Keyword] 'super.key' forwards the key to the parent class (StatelessWidget).
  const MyApp({super.key});

  // [Keyword] '@override' indicates we are redefining a method from the parent class.
  // [Method] 'build' describes the part of the user interface represented by this widget.
  // [Parameter] 'context' (BuildContext) contains information about the location of this widget in the widget tree.
  @override
  Widget build(BuildContext context) {
    // [Widget] MaterialApp is the root widget that wraps a number of widgets that are commonly required for material design applications.
    return MaterialApp(
      title: 'Campus Navigation',
      debugShowCheckedModeBanner: false, // Remove debug banner
      
      // Configure the global application theme
      theme: ThemeData.dark().copyWith(
        // Define color scheme seeded from a primary color (Indigo/Purple)
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B73FF),
          brightness: Brightness.dark,
        ),
        // Set default background color for scaffolds
        scaffoldBackgroundColor: const Color(0xFF121212),
        // Customize app bar appearance globally
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        // Define default styling for text input fields
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

/// Represents a location on the map (e.g., a room, a hallway junction, or a stairwell).
class Node {
  /// Unique identifier for the node (e.g., "G_Room101").
  // [Keyword] 'final' means these variables can only be set once (immutable after initialization).
  final String id;
  /// Human-readable name for the location.
  final String name;
  /// X coordinate on the map canvas.
  final double x;
  /// Y coordinate on the map canvas.
  final double y;
  /// The floor level this node belongs to (0 for Ground, 1 for First).
  final int floor;
  
  // [Constructor] Initializes a Node instance.
  // [Keyword] 'required' means these named parameters must be provided by the caller; they cannot be null.
  Node(
      {required this.id,
      required this.name,
      required this.x,
      required this.y,
      required this.floor});
}

/// Represents a connection between two [Node]s in the graph.
class Edge {
  /// The ID of the starting node.
  final String from;
  /// The ID of the ending node.
  final String to;
  /// The movement cost associated with this edge (usually distance).
  final double cost;
  
  Edge({required this.from, required this.to, required this.cost});
}

///// --- Main screen
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

// [Keyword] 'extends' creates a subclass. State<MapScreen> holds the mutable state for the MapScreen.
// [Keyword] 'with' acts as a mixin, adding capabilities (TickerProvider) to this class without inheritance.
class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  // [Keyword] 'late' indicates a variable will be initialized later (before use), but is non-nullable.
  final TransformationController _controller = TransformationController();
  final GlobalKey _svgKey = GlobalKey();
  late AnimationController _animationController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- Graph Data ---
  /// Stores all nodes loaded from JSON, keyed by their ID.
  Map<String, Node> nodes = {};
  /// Stores all edges loaded from JSON (graph connections).
  final List<Edge> edges = [];

  // --- Floor State ---
  /// Current active floor index (0: Ground, 1: First).
  int currentFloor = 0; 
  /// Path to the currently displayed SVG map asset.
  String currentSvg = 'assets/A_Block_Ground.svg';

  // --- Segments (Geometry) ---
  /// Geometric segments for "snapping" logic.
  /// Each entry contains 'from', 'to' node IDs and 'a', 'b' Offsets.
  List<Map<String, dynamic>> segments = [];

  // --- Route & Navigation State ---
  /// The constructed path (list of Node IDs) from start to destination.
  List<String> currentRoute = [];
  /// Current position of the user marker on the map (map coordinates).
  Offset markerMapPos = Offset.zero;
  /// Current rotation angle of the marker/map.
  double markerAngle = 0.0;
  /// Selected start node ID (for route planning).
  String? selectedFrom;
  /// Selected destination node ID (for route planning).
  String? selectedTo;

  // --- Navigation Control ---
  /// Timer for handling automatic navigation updates.
  Timer? _navigationTimer;

  // --- Reroute & Off-Path Logic ---
  /// Timer to debounce rerouting when user goes off-path.
  Timer? offPathTimer;
  /// Flag indicating if the user is currently off the planned route.
  bool isOffRoute = false;

  // --- Tuning Parameters ---
  /// Max distance to snap a click/tap to the nearest segment.
  final double snapRadius = 80.0;
  /// Distance threshold to consider a node "reached".
  final double reachNodeThreshold = 14.0;
  /// Delay before triggering a reroute.
  final Duration rerouteDelay = const Duration(seconds: 4);

  // --- Zoom Limits ---
  final double minScale = 0.5;
  final double maxScale = 5.0;

  // --- Animation ---
  /// Flag to prevent conflicting animations.
  bool _isAnimating = false;

  // --- User Session ---
  bool _isLoggedIn = false;
  String _username = '';

  // --- Joystick State ---
  bool _upPressed = false;
  bool _downPressed = false;
  bool _leftPressed = false;
  bool _rightPressed = false;
  Timer? _joystickTimer;

  // --- Current Navigation Segment ---
  /// Details of the edge the user is currently traversing.
  Map<String, dynamic>? _currentSegment;
  /// Index of the current step in [currentRoute].
  int _currentRouteIndex = 0;

  // --- Destination State ---
  bool _destinationReached = false;
  final List<Map<String, dynamic>> _routeHistory = [];

  // --- Navigation Mode ---
  /// Toggle between Manual (Joystick) and Automatic navigation.
  // --- Navigation Mode ---
  /// Toggle between Manual (Joystick) and Automatic navigation.
  bool _isAutoMode = true;
  double _navigationSpeed = 3.0; // Default speed 3.0

  /// Current smoothed rotation of the camera (radians).
  /// Used to interpolate rotation for smoother turns.
  double? _currentCameraRotation;

  // [Method] initState() is called once when this state object is inserted into the tree.
  // Perfect for initialization that depends on 'this' or 'context'.
  @override
  void initState() {
    // [Keyword] 'super' allows calling the method from the parent class (State).
    super.initState();
    /// Initialize animation controller for smooth camera movements.
    // [Parameter] 'vsync: this' uses the TickerProviderMixin to prevent animations from running when off-screen.
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    /// Kick off asset loading (nodes, edges, maps).
    loadAssets();
  }

  @override
  void dispose() {
    /// Dispose resource controllers to prevent memory leaks.
    _animationController.dispose();
    offPathTimer?.cancel();
    _navigationTimer?.cancel();
    _joystickTimer?.cancel();
    super.dispose();
  }

  /// Loads graph data (nodes/edges) from JSON assets for both floors.
  // [Keyword] 'Future<void>' indicates this function performs asynchronous work and eventually completes with no value.
  // [Keyword] 'async' enables the use of 'await' within this function.
  Future<void> loadAssets() async {
    // --- 1. Load Ground Floor Data ---
    // [Keyword] 'await' pauses execution until the future (loadString) completes.
    // [Method] rootBundle.loadString reads a text file from the app's assets.
    // [Method] jsonDecode parses the string into a dynamic Dart object (List/Map).
    final groundNodesJson =
        jsonDecode(await rootBundle.loadString('assets/nodes.json')) as List;
    final groundEdgesJson =
        jsonDecode(await rootBundle.loadString('assets/edges.json')) as List;

    // --- 2. Load First Floor Data ---
    final firstNodesJson =
        jsonDecode(await rootBundle.loadString('assets/first_floor_nodes.json'))
            as List;
    final firstEdgesJson =
        jsonDecode(await rootBundle.loadString('assets/first_floor_edges.json'))
            as List;

    // --- 3. Load Second Floor Data ---
    final secondNodesJson =
        jsonDecode(await rootBundle.loadString('assets/second_floor_nodes.json'))
            as List;
    final secondEdgesJson =
        jsonDecode(await rootBundle.loadString('assets/second_floor_edges.json'))
            as List;

    // --- 4. Process Nodes ---
    // Helper closure to process raw JSON node data.
    // Adds a prefix to IDs to distinguish between floors (e.g., G_101 vs F1_101, F2_101).
    void addNodes(List data, String prefix, int floorOverride) {
      String suffix;
      if (floorOverride == 0) {
        suffix = ' (G)';
      } else if (floorOverride == 1) {
        suffix = ' (1F)';
      } else {
        suffix = ' (2F)';
      }
      
      for (var n in data) {
        final id = '$prefix${n['id']}';
        nodes[id] = Node(
          id: id,
          name: (n['name'] ?? id) + suffix, 
          x: (n['x'] as num).toDouble(), 
          y: (n['y'] as num).toDouble(),
          floor: floorOverride,
        );
      }
    }

    // Process nodes for each floor with appropriate prefixes
    addNodes(groundNodesJson, 'G_', 0);
    addNodes(firstNodesJson, 'F1_', 1);
    addNodes(secondNodesJson, 'F2_', 2);

    // --- 5. Process Edges ---
    // Helper to process edges with prefix.
    void addEdges(List data, String prefix) {
      for (var e in data) {
        edges.add(Edge(
          from: '$prefix${e['from']}',
          to: '$prefix${e['to']}',
          cost: (e['cost'] as num).toDouble(),
        ));
      }
    }

    addEdges(groundEdgesJson, 'G_');
    addEdges(firstEdgesJson, 'F1_');
    addEdges(secondEdgesJson, 'F2_');

    // --- 6. Synthesize Vertical Edges (Stairs) ---
    // A. Ground <-> First Floor (Matches by ID suffix 'Stairs_mid', etc.)
    final connectorIds = ['Stairs_mid', 'stairs_left', 'stairs_right'];
    for (var cid in connectorIds) {
      final gId = 'G_$cid';
      final f1Id = 'F1_$cid';
      if (nodes.containsKey(gId) && nodes.containsKey(f1Id)) {
        edges.add(Edge(from: gId, to: f1Id, cost: 50.0));
        edges.add(Edge(from: f1Id, to: gId, cost: 50.0));
      }
    }

    // B. First Floor <-> Second Floor
    // Explicit connection: F1 Stairs Node <-> F2 Stairs Node
    const f1Connector = 'F1_Stairs_to_Second';
    const f2Connector = 'F2_Stairs_mid_Second';
    
    if (nodes.containsKey(f1Connector) && nodes.containsKey(f2Connector)) {
      edges.add(Edge(from: f1Connector, to: f2Connector, cost: 60.0));
      edges.add(Edge(from: f2Connector, to: f1Connector, cost: 60.0));
    }

    // --- 7. Make Graph Undirected ---
    // Add mirrored edges for every existing edge to allow two-way travel.
    final mirrored = <Edge>[];
    for (var e in edges) {
      mirrored.add(Edge(from: e.to, to: e.from, cost: e.cost));
    }
    edges.addAll(mirrored);

    // --- 8. Build Geometric Segments ---
    // used for "snapping"
    segments = edges
        .map((e) {
          final nodeA = nodes[e.from]!;
          final nodeB = nodes[e.to]!;
          
          // Only create geometric segment if both nodes are on the same floor.
          if (nodeA.floor == nodeB.floor) {
            return {
              'from': e.from,
              'to': e.to,
              'a': Offset(nodeA.x, nodeA.y),
              'b': Offset(nodeB.x, nodeB.y),
              'floor': nodeA.floor
            };
          }
          return null; 
        })
        .whereType<Map<String, dynamic>>() 
        .toList();

    // --- 9. Set Initial Position ---
    if (nodes.containsKey('G_A104_Door')) {
      final start = nodes['G_A104_Door']!;
      markerMapPos = Offset(start.x, start.y);
      currentFloor = 0;
      currentSvg = 'assets/A_Block_Ground.svg';
    } else if (nodes.isNotEmpty) {
      final first = nodes.values.first;
      markerMapPos = Offset(first.x, first.y);
      currentFloor = first.floor;
      currentSvg = _getSvgForFloor(currentFloor);
    }
    setState(() {});
  }

  String _getSvgForFloor(int floor) {
    if (floor == 0) return 'assets/A_Block_Ground.svg';
    if (floor == 1) return 'assets/A-BLOCK_first.svg';
    if (floor == 2) return 'assets/A-BLOCK-second.svg';
    return '';
  }

  // ------------ geometry helpers ------------

  /// Calculates the Euclidean distance between two offsets [a] and [b].
  double _distance(Offset a, Offset b) =>
      sqrt((a.dx - b.dx) * (a.dx - b.dx) + (a.dy - b.dy) * (a.dy - b.dy));

  /// Projects point [p] onto the line segment defined by [a] and [b].
  /// Returns the closest point on segment [ab] to point [p].
  Offset projectPointToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return a; // Segment is a point
    // t is the projection factor (0.0 to 1.0)
    var t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
    // [Method] 'clamp' ensures the value stays within the given range (inclusive).
    t = t.clamp(0.0, 1.0);
    return Offset(a.dx + t * dx, a.dy + t * dy);
  }

  /// Finds the nearest segment to point [p] within [maxRadius].
  /// Iterates through ALL segments to find the best match.
  /// Returns a map containing the segment details and the projection point.
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

  /// Converts the current [currentRoute] (list of node IDs) into a list of geometric segments.
  /// Used for checking if the user is staying on the path.
  List<Map<String, dynamic>> _routeSegments() {
    final segs = <Map<String, dynamic>>[];
    for (int i = 0; i < currentRoute.length - 1; i++) {
      // Need to handle missing nodes gracefully, though computePath guarantees existence.
      if (nodes[currentRoute[i]] == null || nodes[currentRoute[i+1]] == null) continue;
      
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

  /// Projects point [p] onto the *active route* polyline.
  /// Iterate through all segments of the route to find the closest point.
  /// Returns the best projection result or null if the route is too short.
  Map<String, dynamic>? projectOntoRoute(Offset p) {
    if (currentRoute.length < 2) return null;
    double best = double.infinity;
    Map<String, dynamic>? bestRes;
    final segs = _routeSegments();
    // Iterate overlapping segments to find the closest point on the polyline.
    for (int i = 0; i < segs.length; i++) {
      final a = segs[i]['a']!;
      final b = segs[i]['b']!;
      final proj = projectPointToSegment(p, a, b);
      final d = _distance(p, proj);
      
      // Keep track of the global minimum distance
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

  /// Computes the shortest path from [startId] to [goalId] using A* algorithm.
  /// Returns a list of Node IDs representing the path, or null if no path found.
  List<String>? computePath(String startId, String goalId) {
    // Basic validation
    if (!nodes.containsKey(startId) || !nodes.containsKey(goalId)) return null;

    // Open set: Nodes to be evaluated
    // [Collection] Sets (<String>{}) store unique values and provide fast lookups.
    final open = <String>{startId};
    
    // CameFrom: Map to reconstruct the path (Navigated to Key from Value)
    final cameFrom = <String, String>{};

    // [Keyword] 'double.infinity' represents positive infinity, useful for initial minimum comparisons.
    final gScore = <String, double>{
      for (var k in nodes.keys) k: double.infinity
    };
    
    // fScore: Estimated total cost (gScore + heuristic)
    final fScore = <String, double>{
      for (var k in nodes.keys) k: double.infinity
    };

    gScore[startId] = 0;
    fScore[startId] = _heuristic(startId, goalId);

    // Helper to pick node with lowest fScore from open set
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

      // Goal reached? Reconstruct path.
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

      // Evaluate neighbors
      for (var e in edges.where((ed) => ed.from == current)) {
        final tentative = (gScore[current] ?? double.infinity) + e.cost;
        
        // If this path to neighbor is better than any previous one...
        if (tentative < (gScore[e.to] ?? double.infinity)) {
          // Record the best path to this neighbor
          cameFrom[e.to] = current;
          gScore[e.to] = tentative;
          // Calculate fScore = gScore + h(n)
          fScore[e.to] = tentative + _heuristic(e.to, goalId);
          
          // Add neighbor to open set if not already there to be explored expectedly
          open.add(e.to); 
        }
      }
    }
    return null; // No path found
  }

  /// Heuristic function for A* (Euclidean distance).
  double _heuristic(String aId, String bId) {
    final a = nodes[aId]!;
    final b = nodes[bId]!;
    return _distance(Offset(a.x, a.y), Offset(b.x, b.y));
  }

  /// Stops all active navigation timers and animations.
  void _stopNavigation() {
    _navigationTimer?.cancel();
    // _navigationSpeed = 0;
    setState(() {});
  }

  /// Called when the user reaches the destination.
  /// Triggers the success dialog and reset logic.
  void _handleDestinationReached() {
    if (_destinationReached) return; // Prevent multiple triggers

    setState(() {
      _destinationReached = true;
    });

    // Stop all navigation
    _stopNavigation();
    _joystickTimer?.cancel();

    // Add to history
    final timestamp = DateTime.now();
    _routeHistory.insert(0, {
      'from': selectedFrom,
      'to': selectedTo,
      'fromName': nodes[selectedFrom!]?.name ?? 'Unknown',
      'toName': nodes[selectedTo!]?.name ?? 'Unknown',
      'timestamp': timestamp,
      'dateStr': "${timestamp.day}/${timestamp.month}/${timestamp.year}",
      'timeStr': "${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}"
    });

    // Show destination reached popup
    _showDestinationReachedDialog();
  }

  /// Displays a dialog congratulating the user on reaching the destination.
  // Display a modal material design dialog.
  void _showDestinationReachedDialog() {
    // [Method] showDialog displays a material dialog above the current contents of the app.
    // [Parameter] 'builder' returns the widget to be displayed.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        // [Widget] AlertDialog is a specific type of dialog with title, content, and actions.
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          // Dialog Title with Icon
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
          // Dialog Content containing destination name
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
          // Dialog Actions (Close / New Route)
          actions: [
            TextButton(
              onPressed: () {
                // [Method] Navigator.of(context).pop() closes the top-most route (the dialog).
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

  /// Sets a new active route and initializes the navigation state.
  /// Moves marker to start, focuses camera, and aligns map orientation.
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

        // Calculate initial angle (pointing towards next node)
        final dx = next.x - start.x;
        final dy = next.y - start.y;
        markerAngle = atan2(dy, dx) + pi / 2; // +pi/2 because marker is likely drawn pointing up
      }

      // Focus camera on the marker and rotate map
      _focusCameraOnMarker();
      _rotateMapToDirection();
    }
    // [Method] setState triggers a UI rebuild to reflect the new route and marker position.
    setState(() {});
  }

  // ------------ camera focus animation ------------

  /// Animates the camera to center the user's marker on the screen.
  /// Maintains the current zoom level.
  void _focusCameraOnMarker() {
    if (_isAnimating) return;

    final screenSize = MediaQuery.of(context).size;
    final markerScreenPos = _mapToScreen(markerMapPos);
    final currentMatrix = _controller.value;

    // Calculate the desired translation to center the marker
    final desiredScreenCenter =
        Offset(screenSize.width / 2, screenSize.height / 2);

    final translationAdjustment = desiredScreenCenter - markerScreenPos;

    // [Keyword] 'final' variable initialized with a cascade operator (..) to chain method calls.
    // [Class] Matrix4 represents a 4x4 transformation matrix (translation, rotation, scale).
    final endMatrix = Matrix4.identity()
      ..translate(
        currentMatrix[12] + translationAdjustment.dx,
        currentMatrix[13] + translationAdjustment.dy,
      )
      ..scale(currentMatrix[0]); // Keep the same scale

    // Animate the transformation
    _isAnimating = true;
    _animationController.reset();
    // [Class] Matrix4Tween interpolates between two matrices.
    // [Method] animate() drives the tween using the controller and a curve.
    final animation = Matrix4Tween(begin: currentMatrix, end: endMatrix).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // [Method] addListener attaches a callback that runs every time the animation value changes.
    animation.addListener(() {
      _controller.value = animation.value;
    });

    // [Method] forward() starts the animation.
    // [Method] then() registers a callback to runs when the future completes.
    _animationController.forward().then((_) {
      _isAnimating = false;
    });
  }

  /// Rotates the map so that the forward path direction points UP.
  /// This implements the "Heads-Up" navigation style with smoothing.
  void _rotateMapToDirection() {
    if (_currentSegment == null) return;

    final a = _currentSegment!['a'] as Offset;
    final b = _currentSegment!['b'] as Offset;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;

    // We want the segment vector (dx, dy) to point UP on the screen.
    // Screen UP is -Y (angle -pi/2).
    final segmentAngle = atan2(dy, dx);
    final targetRotation = -pi / 2 - segmentAngle;

    // Initialize if null
    _currentCameraRotation ??= targetRotation;

    // Smoothly interpolate towards target
    // Calculate shortest angular difference
    double diff = targetRotation - _currentCameraRotation!;
    // Normalize diff to [-pi, pi]
    while (diff > pi) diff -= 2 * pi;
    while (diff <= -pi) diff += 2 * pi;

    // Apply smoothing factor (lower = smoother/slower)
    const double smoothingFactor = 0.08; 
    _currentCameraRotation = _currentCameraRotation! + diff * smoothingFactor;

    final screenSize = MediaQuery.of(context).size;
    final focalPoint = Offset(screenSize.width / 2, screenSize.height / 2);

    // Get current scale, default to 1.0 if not set
    final currentMatrix = _controller.value;
    final scale = currentMatrix.getMaxScaleOnAxis();

    // Rebuild matrix from scratch to ensure marker is centered and rotated correctly.
    // M = T(center) * R(angle) * S(scale) * T(-marker)
    final newMatrix = Matrix4.identity()
      ..translate(focalPoint.dx, focalPoint.dy)
      ..rotateZ(_currentCameraRotation!)
      ..scale(scale)
      ..translate(-markerMapPos.dx, -markerMapPos.dy);

    _controller.value = newMatrix;
  }

  /// Projects a map coordinate to its current screen coordinate
  /// based on the transformation matrix.
  Offset _mapToScreen(Offset mapOffset) {
    final matrix = _controller.value;
    final transformed =
        matrix.transform3(vm.Vector3(mapOffset.dx, mapOffset.dy, 0));
    return Offset(transformed.x, transformed.y);
  }

  // ------------ zoom helpers ------------
  double _currentScale() => _controller.value.getMaxScaleOnAxis();

  /// Zooms the map by [factor], respecting current navigation state (keeping marker centered if navigating).
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

    if (_currentSegment != null) {
      // Re-calculating the matrix using _rotateMapToDirection logic with new scale is safest
      // to maintain rotation + center focus.
      
      // Use smoothed rotation if available, otherwise calculate from segment
      double rotationAngle;
      if (_currentCameraRotation != null) {
        rotationAngle = _currentCameraRotation!;
      } else {
         final a = _currentSegment!['a'] as Offset;
         final b = _currentSegment!['b'] as Offset;
         final dx = b.dx - a.dx;
         final dy = b.dy - a.dy;
         final segmentAngle = atan2(dy, dx);
         rotationAngle = -pi / 2 - segmentAngle;
      }

      final newMatrix = Matrix4.identity()
        ..translate(focalPoint.dx, focalPoint.dy)
        ..rotateZ(rotationAngle)
        ..scale(targetScale)
        ..translate(-markerMapPos.dx, -markerMapPos.dy);

      _controller.value = newMatrix;
    } else {
      // Standard zoom if not navigating (fallback, centers on screen middle).
      final double effectiveFactor = targetScale / curScale;
      final Offset focal = Offset(
          screenSize.width / 2,
          (kToolbarHeight + 20) +
              (screenSize.height - (kToolbarHeight + 20)) / 2);
      final vm.Matrix4 t1 = vm.Matrix4.identity()
        ..translate(-focal.dx, -focal.dy);
      final vm.Matrix4 s = vm.Matrix4.identity()
        ..scale(effectiveFactor, effectiveFactor, 1.0);
      final vm.Matrix4 t2 = vm.Matrix4.identity()
        ..translate(focal.dx, focal.dy);
      final vm.Matrix4 newMatrix = t2 * s * t1 * _controller.value;
      _controller.value = newMatrix;
    }
  }

  void zoomIn() => zoomBy(1.25);
  void zoomOut() => zoomBy(1 / 1.25);

  // --- Intersection State ---
  /// Flag to show/hide the directional arrows overlay at intersections.
  bool _showTurnControls = false;
  /// List of valid directions ('left', 'right', 'straight') at the current intersection.
  final List<String> _validTurnDirections = []; 
  /// The correct direction to take to stay on the path.
  String _correctTurnDirection = ''; 
  /// Helper to prevent accidental 'up' release triggering 'straight' too easily.
  bool _ignoreNextUpRelease = false; 

  // ------------ joystick control ------------

  /// Starts the joystick timer loop.
  /// Runs every 50ms to update position based on held buttons or auto-mode.
  void _startJoystick() {
    _joystickTimer?.cancel();
    // [Method] Timer.periodic creates a repeating timer.
    // [Parameter] (timer) is the callback function executed at each interval.
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

  /// Moves the user automatically along the route.
  /// Advances position towards the next node in the path.
  /// Handles seamless segment transitions and overshooting.
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
    // Auto mode always moves forward
    double moveSpeed = _navigationSpeed;

    // Calculate potential new position
    var newPos = Offset(
      currentPos.dx + dirX * moveSpeed,
      currentPos.dy + dirY * moveSpeed,
    );

    final distToTarget = _distance(currentPos, targetPos);

    // If we are close enough OR we overshot
    if (distToTarget <= moveSpeed ||
        _distance(newPos, startPos) > segmentDist) {
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
      if (overshoot < 0) {
        overshoot = 0;
      }

      // Advance segment immediately
      _advanceSegment();

      // Apply overshoot to the NEW segment
      // [Keyword] 'if' checks if the value is not null.
      if (_currentSegment != null) {
        // [Keyword] 'as' casts the dynamic Value from the map to a specific Type (Offset).
        final newStart = _currentSegment!['a'] as Offset;
        final newEnd = _currentSegment!['b'] as Offset;
        final newDx = newEnd.dx - newStart.dx;
        final newDy = newEnd.dy - newStart.dy;
        final newLen = _distance(newStart, newEnd);

        if (newLen > 0) {
          final newDirX = newDx / newLen;
          final newDirY = newDy / newLen;

          final carriedPos = Offset(newStart.dx + newDirX * overshoot,
              newStart.dy + newDirY * overshoot);

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

  /// Moves the user manually (Joystick control).
  /// Handles intersection pauses, allowing the user to select a turn direction.
  /// Also supports backward movement.
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
      if (distToTarget <= moveSpeed ||
          _distance(newPos, startPos) > segmentDist) {
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
        // Check exits connected to the reached node
        // [Keyword] 'where' filters a list based on a condition (predicate).
        final connectedEdges = edges.where((e) => e.from == nodeId).toList();
        final incomingNodeId = currentRoute[_currentRouteIndex];

        // Filter valid exits (exclude the path we just came from)
        // Using Set to ensure unique exit IDs
        // [Method] 'map' transforms the Edge objects into String IDs.
        // [Method] 'toSet' removes duplicates.
        final validExits = connectedEdges
            .where((e) => e.to != incomingNodeId)
            .map((e) => e.to)
            .toSet()
            .toList();

        if (validExits.length == 1) {
          // STRAIGHT PATH (or only one way to go).
          // SMOOTH MOVEMENT: Advance segment and carry over the remaining distance.

          double overshoot = moveSpeed - distToTarget;
          if (overshoot < 0) {
            overshoot = 0; // Should not happen if logic is correct
          }

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

              final carriedPos = Offset(newStart.dx + newDirX * overshoot,
                  newStart.dy + newDirY * overshoot);

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

  /// Identifies valid exits at an intersection and presents turn options to the user.
  /// Used in Manual Mode when approaching a node with multiple outgoing paths.
  void _checkForIntersection(String nodeId, {bool dryRun = false}) {
    // Find all edges connected to this node
    final connectedEdges = edges.where((e) => e.from == nodeId).toList();

    // Filter out the edge we just came from
    final incomingNodeId = currentRoute[_currentRouteIndex];

    // Use Set to handle duplicate edges
    // Identify valid exits (excluding where we came from)
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
    // [Method] addPostFrameCallback schedules a callback to run after the current frame is drawn.
    // Useful for showing dialogs or changing state immediately after a layout pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // [Property] 'mounted' is true if the State object is currently in a tree.
      if (!mounted) return;
      setState(() {
        _showTurnControls = true;
        // Ignore the release of the current 'up' press to prevent accidental selection
        if (_upPressed) {
          _ignoreNextUpRelease = true;
        }

        // [Method] 'clear' removes all objects from the list.
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

          // Calculate relative angle difference
          var diff = outAngle - inAngle;
          
          // Normalize difference to range [-pi, pi]
          // [Loop] 'while' loop repeats as long as the condition is true.
          while (diff > pi) {
            diff -= 2 * pi;
          }
          while (diff <= -pi) {
            diff += 2 * pi;
          }

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

  /// Move to the next route segment.
  /// Updates `_currentRouteIndex` and sets up the new `_currentSegment`.
  /// Handles floor switching detection and map rotation update.
  void _advanceSegment() {
    if (_currentRouteIndex < currentRoute.length - 2) {
      _currentRouteIndex++;
      final prevNode = nodes[currentRoute[_currentRouteIndex]]!;
      final currNode = nodes[currentRoute[_currentRouteIndex + 1]]!;

      // Check for floor switch
      if (currNode.floor != currentFloor) {
        // Floor switch happened!
        currentFloor = currNode.floor;
        currentSvg = _getSvgForFloor(currentFloor);

        // When switching floors via "vertical" edges, the x,y coordinates
        // should be roughly the same. We shouldn't need large coordinate jumps.

        // Recursively advance to the next segment if this was a vertical edge
        // so we don't halt at the stair connection.
        // Recursively advance to the next segment if this was a vertical edge
        // so we don't halt at the stair connection.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _advanceSegment();
        });
      }

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

        // Only update angle if there is significant movement (avoid vertical edge weirdness)
        if (dx.abs() > 0.1 || dy.abs() > 0.1) {
          markerAngle = atan2(dy, dx) + pi / 2;
        }

        _showTurnControls = false;

        // Rotate map to new direction
        _rotateMapToDirection();
      });
    }
  }

  /// Processes a turn choice (Left, Right, Straight) made by the user at an intersection.
  /// If valid, advances the segment. If invalid (wrong way), triggers rerouting.
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
      
      // Normalize angle difference
      while (diff > pi) {
        diff -= 2 * pi;
      }
      while (diff <= -pi) {
        diff += 2 * pi;
      }

      String dir = 'straight';
      // Thresholds for classifying turns based on angle
      // Right turn: > ~30 degrees (0.5 radians)
      // Left turn: < ~-30 degrees
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
        // User selected a path not in the current route (Wrong Turn).
        // Trigger rerouting logic.
        setState(() {
          isOffRoute = true;
          _showTurnControls = false; // Hide controls while rerouting
        });

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Recalculating route...'),
          duration: Duration(seconds: 1),
        ));

        // Reroute: Compute new path from the selected node (where user turned) to original destination.
        // Reroute: Compute new path from the selected node (where user turned) to original destination.
        final newPath = computePath(selectedExitId, selectedTo!);
        if (newPath != null) {
          setCurrentRoute(newPath); // Activate new route
          isOffRoute = false;
        }
      }
    }
  }

  /// Call this when a joystick button is pressed or released.
  /// Updates the pressed state of direction buttons (Up, Down, Left, Right).
  /// Triggers proper handlers if turn controls are active.
  void _handleJoystickButton(bool pressed, String direction) {
    // Don't allow joystick input if destination is reached
    // Don't allow joystick input if destination is reached
    // if (_destinationReached) return; // Removed to allow backward movement

    // Handle turn buttons (Left/Right)
    if ((direction == 'left' || direction == 'right') && _showTurnControls) {
      if (!pressed) {
        // On release (tap)
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

  /// Simulates a login/logout flow with a dialog.
  /// Toggles [_isLoggedIn] and displays a snackbar.
  void _handleLogin() {
    if (_isLoggedIn) {
      setState(() {
        _isLoggedIn = false;
        _username = '';
      });
      // [Widget] ScaffoldMessenger manages SnackBar notifications.
      // [Method] showSnackBar displays a transient message at the bottom of the screen.
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
            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            // Login Confirm Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B73FF),
              ),
              onPressed: () {
                // [Method] pop removes the top route from the navigator.
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

  /// Builds the side navigation drawer.
  /// Contains profile info, navigation mode toggle, and settings.
  Widget _buildSidebar() {
    // [Widget] Drawer is a material design panel that slides in horizontally.
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E),
      // [Widget] ListView is a scrollable list of widgets.
      // [Property] padding: EdgeInsets.zero ensures the header touches the top edge.
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
            onTap: () {
              Navigator.pop(context); // Close drawer first
              _showProfileDialog();
            },
          ),
          /* Navigation Mode moved to Settings
          ExpansionTile(...)
          */
          ListTile(
            leading: const Icon(Icons.history, color: Colors.white70),
            title: const Text('Route History',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context); // Close drawer first
              _showRouteHistoryDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.white70),
            title:
                const Text('Settings', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _showSettingsDialog();
            },
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

  /// Builds the on-screen joystick or simple drive button (Auto mode).
  /// Hidden when destination is reached.
  Widget _buildJoystick() {
    // Hide joystick when destination is reached
    if (_destinationReached) return const SizedBox.shrink();

    // Auto Mode: Show a single "Drive" button
    if (_isAutoMode) {
      // [Widget] Positioned aligns a child within a Stack.
      return Positioned(
        right: 40,
        bottom: 40,
        // [Widget] GestureDetector detects gestures like taps, drags, and scaling.
        child: GestureDetector(
          // [Callback] onTapDown is called when the user touches the screen.
          onTapDown: (_) {
            setState(() {
              _upPressed = true;
            });
            _startJoystick();
          },
          // [Callback] onTapUp is called when the user lifts their finger.
          onTapUp: (_) {
            setState(() {
              _upPressed = false;
            });
            _joystickTimer?.cancel();
          },
          // [Callback] onTapCancel is called when the gesture is interrupted (e.g., finger drags out of bounds).
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
          // Up button (Move Forward)
          GestureDetector(
            onTapDown: (_) => _handleJoystickButton(true, 'up'),
            onTapUp: (_) => _handleJoystickButton(false, 'up'),
            onTapCancel: () => _handleJoystickButton(false, 'up'),
            // [Widget] AnimatedContainer implicitly animates changes to its properties (width, height, color) over 'duration'.
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                // Ternary operator (?) selects color based on pressed state for visual feedback
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
                              color: const Color(0xFF6B73FF)
                                  .withValues(alpha: 0.8),
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
                              color: const Color(0xFF6B73FF)
                                  .withValues(alpha: 0.8),
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

  /// Builds the zoom-in, zoom-out, and re-center control buttons.
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
              // [Method] zoomIn is a custom method defined in this class.
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

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('User Profile', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFF6B73FF),
              child: Icon(Icons.person, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              _isLoggedIn ? _username : 'Guest User',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isLoggedIn
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isLoggedIn ? Colors.green : Colors.orange,
                ),
              ),
              child: Text(
                _isLoggedIn ? 'Active Member' : 'Guest Access',
                style: TextStyle(
                  color: _isLoggedIn ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showRouteHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.history, color: Color(0xFF6B73FF)),
            SizedBox(width: 12),
            Text('Route History', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: _routeHistory.isEmpty
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_toggle_off,
                        size: 48, color: Colors.white24),
                    SizedBox(height: 16),
                    Text(
                      'No routes completed yet',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _routeHistory.length,
                  itemBuilder: (context, index) {
                    final item = _routeHistory[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF6B73FF),
                          child: Icon(Icons.check,
                              color: Colors.white, size: 16),
                        ),
                        title: Text(
                          "${item['fromName']} → ${item['toName']}",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        subtitle: Text(
                          "${item['dateStr']} at ${item['timeStr']}",
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _routeHistory.clear();
              });
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Clear History'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        // Use StatefulBuilder to manage slider state inside the dialog
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.settings, color: Color(0xFF6B73FF)),
                  SizedBox(width: 12),
                  Text('Settings', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Navigation Speed',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.speed, color: Colors.white70, size: 20),
                      Expanded(
                        child: Slider(
                          value: _navigationSpeed,
                          min: 1.0,
                          max: 10.0,
                          divisions: 9,
                          label: "${_navigationSpeed.toStringAsFixed(1)}x",
                          activeColor: const Color(0xFF6B73FF),
                          inactiveColor: Colors.white24,
                          onChanged: (value) {
                            setStateDialog(() {
                              _navigationSpeed = value;
                            });
                            // Also update parent state
                            setState(() {
                              _navigationSpeed = value;
                            });
                          },
                        ),
                      ),
                      Text(
                        "${_navigationSpeed.toStringAsFixed(1)}x",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  const Text('Navigation Mode',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  RadioListTile<bool>(
                    title: const Text('Manual (Joystick)',
                        style: TextStyle(color: Colors.white70)),
                    value: false,
                    groupValue: _isAutoMode,
                    activeColor: const Color(0xFF6B73FF),
                    onChanged: (bool? value) {
                      setStateDialog(() {
                        _isAutoMode = value!;
                      });
                      setState(() {
                        _isAutoMode = value!;
                      });
                    },
                  ),
                  RadioListTile<bool>(
                    title: const Text('Auto Navigation',
                        style: TextStyle(color: Colors.white70)),
                    value: true,
                    groupValue: _isAutoMode,
                    activeColor: const Color(0xFF6B73FF),
                    onChanged: (bool? value) {
                      setStateDialog(() {
                        _isAutoMode = value!;
                      });
                      setState(() {
                        _isAutoMode = value!;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ------------ UI ------------
  @override
  Widget build(BuildContext context) {
    // Show loading spinner if nodes are not yet loaded
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
    // [Collection] Sets allow efficient checking for duplicates.
    final seen = <String>{};
    final uniqueEdges = <Edge>[];
    // [Loop] 'for-in' iterates through every edge in the list.
    for (var e in edges) {
      // Create a normalized key (ordered) to identify the edge regardless of direction
      final key = (e.from.compareTo(e.to) <= 0)
          ? '${e.from}|||${e.to}'
          : '${e.to}|||${e.from}';
      
      // [Method] contains checks if the key is already in the set.
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueEdges.add(e);
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
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
          // --- Top Navigation Bar (Start / End Selection) ---
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
                // Start Location Dropdown
                // [Widget] Expanded forces the child to fill available horizontal space.
                Expanded(
                  // [Widget] DropdownButtonFormField creates a dropdown menu embedded in a form.
                  child: DropdownButtonFormField<String>(
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Start Location',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    value: selectedFrom,
                    // [Method] map converts the list of nodes into a list of DropdownMenuItems.
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
                // Destination Location Dropdown
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
                // "Navigate" Button
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
                  Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
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
                      SvgPicture.asset(currentSvg, key: _svgKey),
                      // painter overlay (draws edges and route on top of map)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _MapPainter(
                            nodes: nodes,
                            edges: uniqueEdges,
                            currentRoute: currentRoute,
                            isOffRoute: isOffRoute,
                            currentFloor: currentFloor,
                            markerPos: markerMapPos,
                            currentRouteIndex: _currentRouteIndex,
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

/// Custom painter to draw the map graph (nodes, edges) and the current route overlay.
/// Handles selective rendering based on the current floor.
// [Class] CustomPainter allows drawing custom shapes and paths on a canvas.
class _MapPainter extends CustomPainter {
  final Map<String, Node> nodes;
  final List<Edge> edges;
  final List<String> currentRoute;
  final bool isOffRoute;
  final int currentFloor;
  final Offset? markerPos;
  final int currentRouteIndex;

  _MapPainter({
    required this.nodes,
    required this.edges,
    required this.currentRoute,
    required this.isOffRoute,
    required this.currentFloor,
    required this.markerPos,
    required this.currentRouteIndex,
  });

  // [Method] paint is called whenever the visual representation needs to be updated.
  // [Parameter] canvas is the drawing surface.
  // [Parameter] size is the dimensions of the area to paint.
  @override
  void paint(Canvas canvas, Size size) {
    // Paints for Edges, Route, and Nodes
    // [Class] Paint defines the style (color, stroke width) for drawing.
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

    // draw edges (only if both nodes are on current floor)
    for (var e in edges) {
      if (!nodes.containsKey(e.from) || !nodes.containsKey(e.to)) continue;
      final nodeA = nodes[e.from]!;
      final nodeB = nodes[e.to]!;

      // Only draw edges on current floor
      if (nodeA.floor == currentFloor && nodeB.floor == currentFloor) {
        final a = Offset(nodeA.x, nodeA.y);
        final b = Offset(nodeB.x, nodeB.y);
        canvas.drawLine(a, b, paintEdge);
      }
    }

    final paintTraversed = Paint()
      ..color = Colors.grey
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // draw route polyline (only parts on current floor)
    if (currentRoute.isNotEmpty) {
      for (int i = 0; i < currentRoute.length - 1; i++) {
        final id1 = currentRoute[i];
        final id2 = currentRoute[i + 1];
        if (!nodes.containsKey(id1) || !nodes.containsKey(id2)) continue;

        final n1 = nodes[id1]!;
        final n2 = nodes[id2]!;

        if (n1.floor == currentFloor && n2.floor == currentFloor) {
          final p1 = Offset(n1.x, n1.y);
          final p2 = Offset(n2.x, n2.y);

          if (i < currentRouteIndex) {
            // Already traversed: Gray
            canvas.drawLine(p1, p2, paintTraversed);
          } else if (i == currentRouteIndex && markerPos != null) {
            // Currently traversing: Split at marker
            // Start -> Marker (Traversed)
            canvas.drawLine(p1, markerPos!, paintTraversed);
            // Marker -> End (Remaining)
            canvas.drawLine(markerPos!, p2, paintRoute);
          } else {
            // Future segment: Blue (or Orange if off-route)
            canvas.drawLine(p1, p2, paintRoute);
          }
        }
      }
    }

    // draw nodes (small) - only on current floor
    for (var n in nodes.values) {
      if (n.floor == currentFloor) {
        // [Method] drawCircle draws a filled or stroked circle.
        canvas.drawCircle(Offset(n.x, n.y), 4, paintNode);
      }
    }

    // Draw node labels for important nodes (on current floor)
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
      'G_Lobby_Centre',
      'G_Cross-A-Ground',
      'G_Stairs_mid',
      'G_porch_Blocka',
      'F1_Cross-A-First',
      'F1_Stairs_mid',
      'F1_A202_Door',
      'F1_A205_Door'
    ];
    for (var n in nodes.values) {
      if (n.floor == currentFloor && keyNodes.contains(n.id)) {
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

  // [Method] shouldRepaint determines if the painting needs to be refreshed when logic changes.
  // Returning 'true' triggers a call to 'paint'.
  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.currentRoute != currentRoute ||
      old.isOffRoute != isOffRoute ||
      old.currentFloor != currentFloor ||
      old.markerPos != markerPos ||
      old.currentRouteIndex != currentRouteIndex;
}
