import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/image_service.dart';
import 'services/inference_service.dart';
import 'screens/result_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: NolifaGrowApp(),
    ),
  );
}

class NolifaGrowApp extends StatelessWidget {
  const NolifaGrowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nolifa Grow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImageService _imageService = ImageService();
  final InferenceService _inferenceService = InferenceService();
  File? _selectedImage;
  bool _isLoading = false;
  bool _modelLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    await _inferenceService.loadModel();
    setState(() {
      _modelLoaded = true;
    });
  }

  Future<void> _diagnoseImage(File imageFile) async {
    setState(() {
      _isLoading = true;
    });

    final result = await _inferenceService.diagnose(imageFile);

    setState(() {
      _isLoading = false;
    });

    if (result != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            image: imageFile,
            label: result['label'] ?? 'Unknown',
            confidence: result['confidence'] ?? '0',
          ),
        ),
      );
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt,
                color: Color(0xFF2D6A4F),
              ),
              title: const Text('Take a Photo'),
              onTap: () async {
                Navigator.pop(context);
                final image = await _imageService.pickFromCamera();
                if (image != null) {
                  setState(() {
                    _selectedImage = image;
                  });
                  await _diagnoseImage(image);
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFF2D6A4F),
              ),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final image = await _imageService.pickFromGallery();
                if (image != null) {
                  setState(() {
                    _selectedImage = image;
                  });
                  await _diagnoseImage(image);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inferenceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D6A4F),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  const Icon(
                    Icons.eco,
                    size: 100,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Nolifa Grow',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Point your camera at a plant',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 60),
                  if (_selectedImage != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        _selectedImage!,
                        width: 280,
                        height: 280,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_isLoading) ...[
                    const CircularProgressIndicator(
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Analysing your plant...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  ElevatedButton.icon(
                    onPressed: _modelLoaded && !_isLoading
                        ? _showImageOptions
                        : null,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Scan Your Plant'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2D6A4F),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}