Last Updated: 2025-11-28

# File Walkthrough

## Top-Level Directories

*   `android/`: Native Android configuration and build files.
*   `ios/`: Native iOS configuration and build files.
*   `lib/`: Contains all the Dart source code for the application.
*   `assets/`: Stores static resources like the map image (SVG) and graph data (JSON).
*   `test/`: Contains unit and widget tests.
*   `web/`: Configuration for deploying the app to the web.
*   `windows/`, `linux/`, `macos/`: Desktop-specific configuration files.

## Key Files

### `lib/main.dart`
**Purpose:** The entry point and the entire application logic (currently a monolithic file).
**Contains:**
*   `MyApp`: The root widget setting up the theme.
*   `MapScreen`: The primary screen displaying the map.
*   `_MapScreenState`: Handles loading data, pathfinding, user input, and rendering.
*   `Node` & `Edge`: Data models for the graph.

**Code Excerpt: Pathfinding Logic**
```dart
// lib/main.dart:289-301
List<String>? computePath(String startId, String goalId) {
  if (!nodes.containsKey(startId) || !nodes.containsKey(goalId)) return null;
  final open = <String>{startId};
  final cameFrom = <String, String>{};
  
  // Initialize scores with infinity
  final gScore = <String, double>{
    for (var k in nodes.keys) k: double.infinity
  };
  final fScore = <String, double>{
    for (var k in nodes.keys) k: double.infinity
  };

  gScore[startId] = 0;
  fScore[startId] = _heuristic(startId, goalId);
  // ... (A* algorithm continues)
}
```
*Explanation:* This function implements the A* (A-Star) algorithm. It initializes "scores" for every node to infinity, except the start node. It then explores the graph to find the shortest path to the `goalId`.

### `assets/nodes.json`
**Purpose:** Defines the locations on the map.
**Contains:** A list of objects, each representing a point of interest (classroom, door, stairs) with coordinates.

**Code Excerpt:**
```json
// assets/nodes.json:2-3
{"id": "A104_Door", "name": "A104 Class Room IT", "floor": 0, "x": 650.09125, "y": 357.49323},
{"id": "Cross-A-Ground", "name": "Crosspath Ground Foor Block A", "floor": 0, "x": 1025.8007, "y": 356.35471},
```
*Explanation:* Each node has a unique `id`, a human-readable `name`, a `floor` number, and `x`/`y` coordinates that correspond to positions on the SVG map.

### `assets/edges.json`
**Purpose:** Defines the connections (paths) between nodes.
**Contains:** A list of connections showing which nodes are reachable from each other and the "cost" (distance) to travel between them.

**Code Excerpt:**
```json
// assets/edges.json:2-3
{"from": "A105_Door", "to": "A104_Door", "cost": 36.432},
{"from": "A104_Door", "to": "A105_Door", "cost": 36.432},
```
*Explanation:* This defines a path between `A105_Door` and `A104_Door`. The `cost` is usually the physical distance. Note that paths are often defined in both directions (A to B, and B to A).
