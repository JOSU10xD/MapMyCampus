Last Updated: 2025-11-28

# Campus Map Project Documentation

## Table of Contents
1.  [Summary](#summary)
2.  [Architecture](#architecture)
3.  [File Walkthrough](#file-walkthrough)
4.  [Key Functions](#key-functions)
5.  [Dependencies](#dependencies)
6.  [Setup & Run](#setup--run)
7.  [Teaching Tutorial](#teaching-tutorial)
8.  [Demo Script](#demo-script)
9.  [FAQ & Troubleshooting](#faq--troubleshooting)
10. [Security & Privacy](#security--privacy)
11. [Improvements & Roadmap](#improvements--roadmap)
12. [Contributing Guide](#contributing-guide)
13. [Code Map (JSON)](#code-map-json)

---

## Summary

### Overview
**Campus Map** is an interactive mobile application built with Flutter that helps users navigate a university campus. It provides a visual map where users can find the shortest path between two locations (like classrooms and labs) and even virtually explore the campus using an on-screen joystick.

### Elevator Pitch
"Google Maps for your campus"—a smart, offline-capable navigation tool that guides students and visitors to their destination with precision.

### Key Value Points
*   **Smart Navigation:** Automatically calculates the shortest walking path between any two points on campus using the A* algorithm.
*   **Interactive Exploration:** Users can virtually walk around the map using a joystick to learn the layout.
*   **Offline Ready:** All map data and navigation logic are stored locally, so it works without an internet connection.

---

## Architecture

### Tech Stack
*   **Language:** Dart (>=3.0.0 <4.0.0)
*   **Framework:** Flutter
*   **Key Libraries:**
    *   `flutter_svg`: For rendering the Scalable Vector Graphics (SVG) map.
    *   `vector_math`: For 2D geometry calculations (distance, projection, rotation).
*   **Data Format:** JSON (for storing nodes and edges).

### System Block Diagram

```
+-------------------------------------------------------+
|                   Flutter Application                 |
|                                                       |
|  +-------------------+      +----------------------+  |
|  |   UI Layer        |      |   Logic Layer        |  |
|  |                   |      |                      |  |
|  |  [MapScreen]      |<---->|  [Pathfinding (A*)]  |  |
|  |  - SVG Map        |      |  [Geometry Utils]    |  |
|  |  - Joystick       |      |  [State Management]  |  |
|  |  - Sidebar        |      +----------+-----------+  |
|  +---------+---------+                 ^              |
|            ^                           |              |
|            | (User Input)              | (Load Data)  |
|            v                           v              |
+-------------------------------------------------------+
             |                           |
      +------+------+             +------+------+
      | User Touch  |             | Local Assets|
      | & Gestures  |             | (JSON/SVG)  |
      +-------------+             +-------------+
```

### Data Flow: Pathfinding
1.  **App Start:** `loadAssets()` reads `assets/nodes.json` and `assets/edges.json`.
2.  **Parsing:** JSON data is converted into `Node` and `Edge` objects.
3.  **User Action:** User selects a "Start" and "Destination" (or moves marker).
4.  **Computation:** `computePath()` runs the A* algorithm to find the sequence of nodes with the lowest cost.
5.  **Rendering:** The app draws a polyline connecting these nodes on top of the SVG map.
6.  **Navigation:** As the user moves (via joystick), the app checks if they are on the path and updates the camera.

### Deployment
*   **Target Platforms:** Android, iOS (primary), Windows, macOS, Linux, Web.
*   **Distribution:**
    *   **Mobile:** Google Play Store (APK/AAB), Apple App Store (IPA).
    *   **Desktop:** Executable installers.
    *   **Web:** Static HTML/JS files.

---

## File Walkthrough

### Top-Level Directories
*   `android/`: Native Android configuration and build files.
*   `ios/`: Native iOS configuration and build files.
*   `lib/`: Contains all the Dart source code for the application.
*   `assets/`: Stores static resources like the map image (SVG) and graph data (JSON).
*   `test/`: Contains unit and widget tests.
*   `web/`: Configuration for deploying the app to the web.
*   `windows/`, `linux/`, `macos/`: Desktop-specific configuration files.

### Key Files

#### `lib/main.dart`
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
  // ... (A* algorithm continues)
}
```
*Explanation:* This function implements the A* (A-Star) algorithm. It initializes "scores" for every node to infinity, except the start node. It then explores the graph to find the shortest path to the `goalId`.

#### `assets/nodes.json`
**Purpose:** Defines the locations on the map.
**Contains:** A list of objects, each representing a point of interest (classroom, door, stairs) with coordinates.

**Code Excerpt:**
```json
// assets/nodes.json:2-3
{"id": "A104_Door", "name": "A104 Class Room IT", "floor": 0, "x": 650.09125, "y": 357.49323},
{"id": "Cross-A-Ground", "name": "Crosspath Ground Foor Block A", "floor": 0, "x": 1025.8007, "y": 356.35471},
```
*Explanation:* Each node has a unique `id`, a human-readable `name`, a `floor` number, and `x`/`y` coordinates that correspond to positions on the SVG map.

#### `assets/edges.json`
**Purpose:** Defines the connections (paths) between nodes.
**Contains:** A list of connections showing which nodes are reachable from each other and the "cost" (distance) to travel between them.

**Code Excerpt:**
```json
// assets/edges.json:2-3
{"from": "A105_Door", "to": "A104_Door", "cost": 36.432},
{"from": "A104_Door", "to": "A105_Door", "cost": 36.432},
```
*Explanation:* This defines a path between `A105_Door` and `A104_Door`. The `cost` is usually the physical distance.

---

## Key Functions

### 1. `loadAssets`
*   **File:** `lib/main.dart` (Lines 159-202)
*   **Purpose:** Loads and parses the JSON data files (`nodes.json`, `edges.json`) and initializes the graph structure.
*   **Inputs:** None (reads from assets).
*   **Outputs:** Populates `nodes` map and `edges` list.
*   **Complexity:** O(N + E) where N is nodes and E is edges.
*   **Why Important:** Without this, the app has no data to display or navigate.

### 2. `computePath`
*   **File:** `lib/main.dart` (Lines 289-341)
*   **Purpose:** Calculates the shortest path between two nodes using the A* algorithm.
*   **Inputs:** `startId` (String), `goalId` (String).
*   **Outputs:** `List<String>?` (ordered list of node IDs representing the path, or null if no path).
*   **Complexity:** O(E log N) typically.
*   **Why Important:** This is the core intelligence of the application.

### 3. `_heuristic`
*   **File:** `lib/main.dart` (Lines 343-347)
*   **Purpose:** Estimates the cost from a node to the goal (Euclidean distance). Used by A* to prioritize exploration.
*   **Inputs:** `aId` (String), `bId` (String).
*   **Outputs:** `double` (distance).
*   **Why Important:** Makes the pathfinding algorithm efficient (A* vs Dijkstra).

### 4. `projectPointToSegment`
*   **File:** `lib/main.dart` (Lines 208-216)
*   **Purpose:** Finds the closest point on a line segment to a given point.
*   **Inputs:** `p` (Point), `a` (Segment Start), `b` (Segment End).
*   **Outputs:** `Offset` (The projected point on the segment).
*   **Why Important:** Used to snap the user's location to the nearest path so they don't drift through walls.

### 5. `findNearestSegmentWithin`
*   **File:** `lib/main.dart` (Lines 219-242)
*   **Purpose:** Iterates through all map segments to find the one closest to the user.
*   **Inputs:** `p` (User Position), `maxRadius` (double).
*   **Outputs:** `Map<String, dynamic>?` (Details of the nearest segment).
*   **Why Important:** Essential for the "snap-to-path" functionality during free movement.

### 6. `_followRoute`
*   **File:** `lib/main.dart` (Lines 681-730)
*   **Purpose:** Automatically moves the marker along the calculated path.
*   **Inputs:** None (uses state).
*   **Side Effects:** Updates `markerMapPos`, `markerAngle`, and triggers UI rebuilds.
*   **Why Important:** Handles the "navigation" mode where the app guides the user.

### 7. `_moveFreely`
*   **File:** `lib/main.dart` (Lines 732-782)
*   **Purpose:** Handles manual movement via joystick when not following a specific route.
*   **Inputs:** None (uses joystick state).
*   **Why Important:** Allows users to explore the map interactively.

### 8. `_handleOffRoute`
*   **File:** `lib/main.dart` (Lines 356-379)
*   **Purpose:** Detects if the user has strayed from the path and triggers a recalculation.
*   **Inputs:** `projectedPoint` (Offset).
*   **Why Important:** Ensures the navigation adapts to the user's actual movement.

---

## Dependencies

### Production Dependencies
*   **flutter**: The core framework.
    *   *Purpose:* UI rendering and app structure.
*   **flutter_svg**: `^2.0.7`
    *   *Purpose:* Rendering the campus map which is an SVG file.
*   **vector_math**: `^2.1.2`
    *   *Purpose:* Performing 2D vector calculations (dot products, distance) for geometry logic.
*   **cupertino_icons**: `^1.0.8`
    *   *Purpose:* iOS-style icons (default in Flutter).

### Dev Dependencies
*   **flutter_test**:
    *   *Purpose:* Running unit and widget tests.
*   **flutter_lints**: `^4.0.0`
    *   *Purpose:* Enforcing code style and best practices.

---

## Setup & Run

### Prerequisites
*   **Flutter SDK:** Version 3.0.0 or higher.
*   **Dart SDK:** Included with Flutter.
*   **IDE:** VS Code (recommended) or Android Studio.

### Installation
1.  **Clone the repository:**
    ```bash
    git clone <repo_url>
    cd campus_map
    ```
2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

### Running the App
*   **Run on connected device/emulator:**
    ```bash
    flutter run
    ```
*   **Run specifically on Windows/macOS (Desktop):**
    ```bash
    flutter run -d windows
    # or
    flutter run -d macos
    ```

### Running Tests
To run the test suite (if available):
```bash
flutter test
```

---

## Teaching Tutorial

### Lesson 1: Understanding the Graph
*   **Objective:** Learn how the map is represented as nodes and edges.
*   **Time:** 15 mins.
*   **Task:** Open `assets/nodes.json`. Add a new node called "Secret_Lab" with coordinates `x: 500, y: 500`.
*   **Checkpoint:** Run the app. Does it crash? (No, but you can't see it yet).

### Lesson 2: Connecting the Dots
*   **Objective:** Learn how edges create paths.
*   **Time:** 20 mins.
*   **Task:** Open `assets/edges.json`. Create a connection between an existing node and your "Secret_Lab".
*   **Checkpoint:** Use `computePath` in a test or print statement to see if a path can be found to "Secret_Lab".

### Lesson 3: The A* Algorithm
*   **Objective:** Understand how the app finds the shortest path.
*   **Time:** 30 mins.
*   **Task:** Locate `computePath` in `main.dart`. Add `print` statements to log the `current` node being processed.
*   **Checkpoint:** Run a route. Watch the console to see the algorithm "searching" node by node.

### Lesson 4: Visualizing the Map
*   **Objective:** Understand SVG rendering.
*   **Time:** 20 mins.
*   **Task:** Change the `seedColor` in `MyApp` (line 28) to `Colors.red`.
*   **Checkpoint:** Hot restart. The app theme should change to red.

### Lesson 5: Joystick Control
*   **Objective:** Learn how user input moves the marker.
*   **Time:** 25 mins.
*   **Task:** In `_moveFreely`, change `speed = 2.0` to `speed = 10.0`.
*   **Checkpoint:** Run the app. The marker should move extremely fast!

### Quiz
1.  What file format is used for the map data? (A) XML (B) JSON (C) YAML
2.  Which algorithm is used for pathfinding? (A) Dijkstra (B) DFS (C) A*
3.  What folder contains the map images? (A) lib (B) assets (C) android

*Answers: 1:B, 2:C, 3:B*

---

## Demo Script

**Time:** 5 Minutes

1.  **Intro (0:00-0:30):** "Hi, this is Campus Map. It's an offline navigation tool for our university."
2.  **Show Map (0:30-1:00):** Open the app. Pinch to zoom in/out. Show the detail of the SVG map.
3.  **Pathfinding (1:00-2:30):**
    *   Tap the "Search" or "Route" button (if available) or hardcode a route for demo.
    *   "I need to get from the Entrance to Lab 3."
    *   Show the red line appearing instantly.
4.  **Navigation (2:30-4:00):**
    *   Use the on-screen joystick.
    *   "As I walk, the marker moves."
    *   Demonstrate "snapping" to the path.
5.  **Conclusion (4:00-5:00):** "It works completely offline, making it reliable even in basements with no signal."

---

## FAQ & Troubleshooting

### 1. "No route available" error
*   **Cause:** The start and destination nodes are not connected in `edges.json`.
*   **Fix:** Check `assets/edges.json` and ensure there is a continuous chain of edges between the two points.

### 2. Map is blank/white
*   **Cause:** `assets/A_Block_Ground.svg` might be missing or corrupt.
*   **Fix:** Verify the file exists in `assets/` and is a valid SVG.

### 3. App crashes on startup
*   **Cause:** JSON syntax error in `nodes.json` or `edges.json`.
*   **Fix:** Use a JSON validator (like jsonlint.com) to check your asset files.

### 4. Marker moves through walls
*   **Cause:** `snapRadius` might be too large, or walls aren't defined as obstacles (only paths are defined).
*   **Fix:** This is expected behavior in "Free Move" mode if you aren't near a path.

---

## Security & Privacy

### Sensitive Areas
*   **Authentication:** The app has a "Login" feature (`_handleLogin`), but it currently accepts *any* input. It does not verify passwords.
*   **Data Storage:** No personal data is stored persistently.

### Recommendations
*   **Validate Inputs:** Ensure `nodes.json` is not tampered with if loaded remotely in the future.
*   **Secure Auth:** If connecting to a real backend, replace the mock login with a secure OAuth or token-based system.
*   **HTTPS:** Ensure all future network requests use HTTPS.

---

## Improvements & Roadmap

### Quick Wins (Low Effort)
1.  **Extract Classes:** Move `Node`, `Edge`, and `MapScreen` into separate files in `lib/`.
2.  **Error Handling:** Add try-catch blocks around `jsonDecode` in `loadAssets`.
3.  **Constants:** Move magic numbers (speed `2.0`, snapRadius `80.0`) to a `AppConstants` class.

### Medium Term
4.  **Search UI:** Add a search bar to let users type destination names instead of just tapping.
5.  **Floor Switching:** Implement logic to switch SVG maps when the path goes up/down stairs (using `node.floor`).
6.  **Unit Tests:** Add tests for `computePath` to ensure routing always works.

### Long Term
7.  **Backend Integration:** Fetch map updates from a server so the app doesn't need an update for every map change.
8.  **GPS Integration:** Use real device GPS to position the marker outdoors.

---

## Contributing Guide

### How to Contribute
1.  **Fork** the repo.
2.  **Create a branch** for your feature (`git checkout -b feature/amazing-feature`).
3.  **Commit** your changes.
4.  **Push** to the branch.
5.  **Open a Pull Request**.

### Code Style
*   Follow standard Dart conventions.
*   Run `flutter analyze` before committing.
*   Format code using `dart format .`.

---

## Code Map (JSON)

```json
{
  "core": {
    "entry_point": ["lib/main.dart"],
    "app_config": ["pubspec.yaml"]
  },
  "logic": {
    "pathfinding": ["lib/main.dart:computePath"],
    "geometry": ["lib/main.dart:projectPointToSegment", "lib/main.dart:_distance"],
    "state_management": ["lib/main.dart:_MapScreenState"]
  },
  "data": {
    "models": ["lib/main.dart:Node", "lib/main.dart:Edge"],
    "assets": ["assets/nodes.json", "assets/edges.json", "assets/A_Block_Ground.svg"]
  },
  "ui": {
    "screens": ["lib/main.dart:MapScreen"],
    "widgets": ["lib/main.dart:_buildSidebar", "lib/main.dart:_buildJoystick"]
  }
}
```
