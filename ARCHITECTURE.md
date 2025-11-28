Last Updated: 2025-11-28

# Architecture

## Tech Stack
*   **Language:** Dart (>=3.0.0 <4.0.0)
*   **Framework:** Flutter
*   **Key Libraries:**
    *   `flutter_svg`: For rendering the Scalable Vector Graphics (SVG) map.
    *   `vector_math`: For 2D geometry calculations (distance, projection, rotation).
*   **Data Format:** JSON (for storing nodes and edges).

## System Block Diagram

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

## Data Flow: Pathfinding
1.  **App Start:** `loadAssets()` reads `assets/nodes.json` and `assets/edges.json`.
2.  **Parsing:** JSON data is converted into `Node` and `Edge` objects.
3.  **User Action:** User selects a "Start" and "Destination" (or moves marker).
4.  **Computation:** `computePath()` runs the A* algorithm to find the sequence of nodes with the lowest cost.
5.  **Rendering:** The app draws a polyline connecting these nodes on top of the SVG map.
6.  **Navigation:** As the user moves (via joystick), the app checks if they are on the path and updates the camera.

## Deployment
*   **Target Platforms:** Android, iOS (primary), Windows, macOS, Linux, Web (supported by Flutter).
*   **Distribution:**
    *   **Mobile:** Google Play Store (APK/AAB), Apple App Store (IPA).
    *   **Desktop:** Executable installers.
    *   **Web:** Static HTML/JS files hosted on any web server.
