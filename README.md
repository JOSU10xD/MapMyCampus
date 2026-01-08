# Campus Map Navigation App

A Flutter-based indoor navigation application tailored for university campuses. This app provides offline, interactive, and intelligent pathfinding across multiple floors, helping students and visitors navigate easily.

## 🌟 Features

*   **Smart Pathfinding**: Uses the **A* Algorithm** to calculate the shortest walking path between classrooms, labs, and other points of interest.
*   **Multi-Floor Navigation**: Seamlessly handles navigation across Ground, First, and Second floors, including stairs connections.
*   **Offline Capable**: All map data and logic are stored locally, requiring no internet connection.
*   **Interactive Controls**:
    *   **Joystick Mode**: Explore the campus manually with an on-screen joystick.
    *   **Auto Navigation**: "Walk" along the calculated path automatically.
*   **Dynamic SVG Maps**: High-quality vector maps that scale beautifully on any device.
*   **Stay-on-Path**: Intelligent snapping logic keeps your position locked to valid paths while navigating.

## 🚀 Getting Started

### Prerequisites
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.0.0 or higher)
*   VS Code or Android Studio

### Installation

1.  **Clone the repository**:
    ```bash
    git clone <repository-url>
    cd MapMyCampus
    ```

2.  **Install dependencies**:
    ```bash
    flutter pub get
    ```

3.  **Run the app**:
    ```bash
    flutter run
    ```

## 📂 Project Structure

The project follows a standard Flutter layout with a focus on simplicity.

```
MapMyCampus/
├── android/            # Native Android files
├── assets/             # Map data and images
│   ├── *.svg           # Vector maps for each floor
│   ├── nodes.json      # Graph nodes (locations)
│   └── edges.json      # Graph edges (connections)
├── ios/                # Native iOS files
├── lib/
│   └── main.dart       # Main application entry point & logic
├── pubspec.yaml        # Dependencies and assets configuration
└── README.md           # This file
```

### Key Files

*   **`lib/main.dart`**: The core of the application. It handles everything from UI rendering to the complex math required for navigation.
    *   `Node` & `Edge` classes: Define the graph structure.
    *   `computePath()`: Implements the A* algorithm.
    *   `MapScreen`: The main widget that renders the SVG map and handles user input.
    *   `loadAssets()`: Loads the JSON data files for all floors and builds the navigation graph.

*   **`assets/*.json`**: These files define the physical layout of the campus.
    *   `nodes.json`: Contains coordinates (x, y) and metadata for every point on the map.
    *   `edges.json`: Defines which nodes are connected and the distance between them.

## 🛠️ How It Works

1.  **Graph Construction**: On startup, the app reads the JSON files from `assets/` and builds a graph network in memory. It connects floors via special "vertical edges" (stairs).
2.  **Route Calculation**: When a user selects a destination, the app runs the A* algorithm to find the sequence of nodes with the lowest total "cost" (distance).
3.  **Rendering**: The map is drawn using `flutter_svg`. The calculated route is overlaid as a path.
4.  **Navigation**: The app tracks the user's "virtual" position. As you move (or as the auto-navigator runs), it projects your position onto the nearest valid path segment to ensure accurate tracking.

## 🔧 Customization

To adapt this app for a different campus or building:
1.  Replace the `.svg` files in `assets/` with your own floor plans.
2.  Update `nodes.json` and `edges.json` with coordinates that match your new maps.
3.  Adjust the `_getSvgForFloor` method in `lib/main.dart` to load your new assets.

## 📄 License
This project is open source and available for educational and personal use.
