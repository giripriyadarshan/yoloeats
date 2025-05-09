import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:yoloeats_app/providers/ocr_providers.dart';
import 'package:yoloeats_app/providers/user_profile_providers.dart';

class IngredientScannerScreen extends ConsumerStatefulWidget {
  const IngredientScannerScreen({super.key});

  @override
  ConsumerState<IngredientScannerScreen> createState() => _IngredientScannerScreenState();
}

class _IngredientScannerScreenState extends ConsumerState<IngredientScannerScreen> {
  PermissionStatus? _cameraPermissionStatus;
  List<CameraDescription>? _cameras;
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCameraPermissionGranted = false;
  CameraException? _cameraInitializationError;

  bool _isCapturingAndProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndInitializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionAndInitializeCamera() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _cameraPermissionStatus = status;
        _isCameraPermissionGranted = status.isGranted || status.isLimited;
      });
      if (_isCameraPermissionGranted) {
        await _initializeCamera();
      } else {
        setState(() { _isCameraInitialized = false; _cameraController = null; });
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (_cameraController != null || !_isCameraPermissionGranted) return;
    try {
      _cameras = await availableCameras();
      if (_cameras?.isEmpty ?? true) throw CameraException("NO_CAMERAS", "No cameras found.");
      CameraDescription selectedCamera = _cameras!.firstWhere((cam) => cam.lensDirection == CameraLensDirection.back, orElse: () => _cameras!.first);
      _cameraController = CameraController(selectedCamera, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      if (mounted) setState(() { _isCameraInitialized = true; _cameraInitializationError = null; });
    } on CameraException catch (e) { if (mounted) setState(() => _cameraInitializationError = e);
    } catch (e) { if (mounted) setState(() => _cameraInitializationError = CameraException("INIT_ERROR", e.toString()));
    } finally { if (mounted && _cameraInitializationError != null) setState(() => _isCameraInitialized = false); }
  }


  Future<void> _captureAndProcessImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _cameraController!.value.isTakingPicture || _isCapturingAndProcessing) {
      return;
    }

    setState(() { _isCapturingAndProcessing = true; });

    String? extractedTextResult;
    List<String> foundAllergensResult = [];
    String? errorResult;

    try {
      print("Capturing picture...");
      final XFile imageFile = await _cameraController!.takePicture();
      print('Picture saved to ${imageFile.path}');

      print("Processing captured image: ${imageFile.path}");
      try {
        final ocrService = ref.read(ocrServiceProvider);
        extractedTextResult = await ocrService.extractTextFromImagePath(imageFile.path);
        print("OCR Result length: ${extractedTextResult?.length ?? 0}");

        foundAllergensResult = _compareTextWithAllergens(extractedTextResult);

      } catch (e) {
        print("Error during OCR processing: $e");
        errorResult = "Could not extract text from image: $e";
      }

      if (mounted) {
        _showResultsBottomSheet(extractedTextResult, foundAllergensResult, errorMsg: errorResult);
      }

    } on CameraException catch (e) {
      print("Error taking picture: ${e.code} - ${e.description}");
      if (mounted) {
        _showResultsBottomSheet(null, [], errorMsg: 'Error capturing image: ${e.description}');
      }
    } catch (e) {
      print("Unexpected error taking picture: $e");
      if (mounted) {
        _showResultsBottomSheet(null, [], errorMsg: 'Could not capture image: $e');
      }
    } finally {
      if (mounted) {
        setState(() { _isCapturingAndProcessing = false; });
      }
    }
  }

  List<String> _compareTextWithAllergens(String? text) {
    final List<String> found = [];
    if (text == null || text.isEmpty) {
      print("Comparison skipped: No text extracted.");
      return found;
    }

    final userProfile = ref.read(userProfileProvider).valueOrNull;

    if (userProfile == null) {
      print("Comparison skipped: UserProfile not loaded.");
      return found;
    }

    final userAllergens = userProfile.allergens;
    if (userAllergens.isEmpty) {
      print("Comparison skipped: User has no listed allergens.");
      return found;
    }

    print("Comparing extracted text against allergens: ${userAllergens.join(', ')}");
    final processedText = text.toLowerCase();

    for (final allergen in userAllergens) {
      if (allergen.trim().isEmpty) continue;
      if (processedText.contains(allergen.toLowerCase())) {
        print("MATCH FOUND: $allergen");
        found.add(allergen);
      }
    }
    print("Found conflicting allergens in text: ${found.join(', ')}");
    return found;
  }

  void _showResultsBottomSheet(String? extractedText, List<String> foundAllergens, {String? errorMsg}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext bc) {
        return FractionallySizedBox(
          heightFactor: 0.6,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Scan Results",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Divider(),
                if (errorMsg != null)
                  Text("Error: $errorMsg", style: const TextStyle(color: Colors.red)),

                if (extractedText != null) ...[
                  Text("Extracted Text:", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.grey[100],
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(4)
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(extractedText.isNotEmpty ? extractedText : "(No text detected)"),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else if (errorMsg == null) ... [
                  const Expanded(child: Center(child: Text("No text detected in the image."))),
                  const SizedBox(height: 16),
                ],

                if (extractedText != null) ...[
                  Text("Potential Allergens Found:", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  if (foundAllergens.isEmpty)
                    const Text("None of your listed allergens found.")
                  else
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: foundAllergens.map((allergen) => Chip(
                        label: Text(allergen),
                        backgroundColor: Colors.red[100],
                        labelStyle: const TextStyle(color: Colors.red),
                        side: BorderSide(color: Colors.red[200]!),
                      )).toList(),
                    ),
                ],

                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close"),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_cameraPermissionStatus == null) {
      return const Center(child: CircularProgressIndicator(key: ValueKey("perm_loading")));
    }

    if (!_isCameraPermissionGranted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _cameraPermissionStatus == PermissionStatus.permanentlyDenied || _cameraPermissionStatus == PermissionStatus.restricted
                    ? 'Camera permission permanently denied or restricted.'
                    : 'Camera access denied.',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Camera permission is needed to scan ingredients.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: (_cameraPermissionStatus == PermissionStatus.permanentlyDenied || _cameraPermissionStatus == PermissionStatus.restricted)
                    ? openAppSettings
                    : _checkPermissionAndInitializeCamera,
                child: Text((_cameraPermissionStatus == PermissionStatus.permanentlyDenied || _cameraPermissionStatus == PermissionStatus.restricted)
                    ? 'Open App Settings'
                    : 'Try Granting Permission'),
              ),
            ],
          ),
        ),
      );
    }

    if (_cameraInitializationError != null) {
      return Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Failed to initialize camera:\n${_cameraInitializationError!.description}',
              textAlign: TextAlign.center,
            ),
          ));
    }

    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(key: ValueKey("cam_loading")));
    }

    final previewSize = _cameraController?.value.previewSize ?? Size.zero;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (previewSize != Size.zero)
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: _cameraController!.value.aspectRatio,
              child: CameraPreview(_cameraController!),
            ),
          )
        else
          const Center(child: Text("Waiting for camera preview size...")),

        if (_isCapturingAndProcessing)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),

      ],
    );
  } // End of _buildBody

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar( title: const Text('Scan Ingredients') ),
      body: _buildBody(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.large(
        // --- FIX: Use combined loading flag ---
        onPressed: _isCameraInitialized && !_isCapturingAndProcessing ? _captureAndProcessImage : null,
        tooltip: 'Scan Ingredients',
        child: _isCapturingAndProcessing
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.camera_alt),
      ),
    );
  }
}