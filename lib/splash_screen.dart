import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:campus_map/main.dart'; // Import main to access MapScreen/MyApp logic if needed

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.asset('assets/splashscreen.mp4')
        ..initialize().then((_) {
          print("Video initialized successfully");
          setState(() {
            _initialized = true;
          });
          _controller.play();
          _controller.setVolume(1.0);
        }).catchError((error) {
          print("Video initialization failed: $error");
          _navigateToHome(); // Skip to home on error
        });
    } catch (e) {
      print("Error loading video: $e");
      _navigateToHome();
    }

    // Listen for video end
    _controller.addListener(() {
      if (_controller.value.position >= _controller.value.duration) {
        _navigateToHome();
      }
    });
  }
  
  void _navigateToHome() {
    // Navigate to the main app using a route replacement so back button doesn't return to splash
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MapScreen()), // Assuming MapScreen is your home
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, 
      body: Center(
        child: _initialized 
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            // Show simple white background (or minimal spinner) while video prepares
            // User requested "loading screen should be after", so we keep this minimal.
            : const CircularProgressIndicator(color: Color(0xFF6B73FF)), 
      ),
    );
  }
}
