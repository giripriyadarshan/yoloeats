import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ml_providers.dart';
import '../../providers/camera_providers.dart';
import '../../providers/ocr_providers.dart';
import '../../providers/user_profile_providers.dart';
import '../painters/detection_painter.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  CameraController? _cameraController;
  String? _tfliteModelLoadError;
  bool _isCameraInitialized = false;
  bool _isCameraInitializing = false;
  CameraException? _cameraInitializationError;

  bool _isPermissionGranted = false;

  bool _processingInQueue = false;
  bool _isProcessingOcr = false;

  @override
  void initState() {
    super.initState();
    print("ScannerScreen: initState (Camera-Only for TFLite Test)");
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initScreen();
    });
  }

  Future<void> _initScreen() async {
    print("ScannerScreen: _initScreen started (Camera-Only for TFLite Test)");
    await _checkPermissionAndInitializeMainCamera();
    if (_isPermissionGranted && mounted) {
      final initialMode = ref.read(currentScannerModeProvider);
      ScannerMode targetInitialMode = (initialMode == ScannerMode.Barcode) ? ScannerMode.ObjectDetection : initialMode;
      if (initialMode == ScannerMode.Barcode) {
        print("ScannerScreen: Initial mode was Barcode, defaulting to ObjectDetection.");
        ref.read(currentScannerModeProvider.notifier).state = targetInitialMode;
      }
      await _setActiveModeResources(targetInitialMode, isInitializing: true);
    }
    print("ScannerScreen: _initScreen finished. Camera Initialized: $_isCameraInitialized");
  }

  Future<void> _checkPermissionAndInitializeMainCamera() async {
    print("ScannerScreen: Checking camera permission...");
    if (_isCameraInitializing) return;
    setStateIfMounted(() { _isCameraInitializing = true; });
    final status = await Permission.camera.request();
    final bool granted = status.isGranted || status.isLimited;
    if (mounted) {
      setStateIfMounted(() { _isPermissionGranted = granted; _cameraInitializationError = null; });
      if (granted) await _initializeMainCameraController();
      else setStateIfMounted(() { _isCameraInitialized = false; _cameraController = null; _resetScanStates();});
      setStateIfMounted(() { _isCameraInitializing = false; });
    } else _isCameraInitializing = false;
  }

  Future<void> _initializeMainCameraController() async {
    if (_cameraController != null && _isCameraInitialized) return;
    if (!_isPermissionGranted) {
      if (mounted) setStateIfMounted(() => _isCameraInitialized = false);
      return;
    }
    print("ScannerScreen: Finding available cameras for main _cameraController...");
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException("NO_CAMERAS_AVAILABLE", "No cameras found.");
      CameraDescription selectedCamera = cameras.firstWhere((cam) => cam.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      if (_cameraController != null) {
        if (_cameraController!.value.isStreamingImages) await _cameraController!.stopImageStream();
        await _cameraController!.dispose();
        _cameraController = null; _isCameraInitialized = false;
      }
      _cameraController = CameraController(selectedCamera, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await _cameraController!.initialize();
      if (mounted) setStateIfMounted(() { _isCameraInitialized = true; _cameraInitializationError = null; });
    } on CameraException catch (e) {
      if (mounted) setStateIfMounted(() { _cameraInitializationError = e; _isCameraInitialized = false; _cameraController = null; });
    } catch (e) {
      if (mounted) setStateIfMounted(() { _cameraInitializationError = CameraException("INIT_ERROR_MAIN_CAM", e.toString()); _isCameraInitialized = false; _cameraController = null;});
    }
  }

  Future<void> _initModel() async {
    final tfliteService = ref.read(tfliteServiceProvider);
    if (tfliteService.isModelLoaded) {
      print("ScannerScreen: _initModel - TFLite model already loaded.");
      if (mounted) setState(() => _tfliteModelLoadError = null);
      return;
    }

    print("ScannerScreen: _initModel - Attempting to load TFLite model...");
    String? loadResult = await tfliteService.loadModel(
        modelAsset: "assets/yoloeats_v1.tflite",
        labelsAsset: "assets/labels.txt"
    );

    if (mounted) {
      if (loadResult != null) {
        print("ScannerScreen: ERROR - TFLite model loading FAILED: $loadResult");
        setState(() {
          _tfliteModelLoadError = loadResult;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to load detection model: $loadResult"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        print("ScannerScreen: SUCCESS - TFLite model loaded successfully.");
        setState(() {
          _tfliteModelLoadError = null;
        });
      }
    }
  }

  Future<void> _setActiveModeResources(ScannerMode mode, {bool isInitializing = false}) async {
    print("ScannerScreen: Setting active resources for mode: $mode");
    if (!mounted) return;

    if (mode != ScannerMode.ObjectDetection && (_cameraController?.value.isStreamingImages ?? false)) {
      await _cameraController?.stopImageStream();
      _processingInQueue = false;
    }

    try {
      if (mode == ScannerMode.ObjectDetection) {
        if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
          await _initializeMainCameraController();
        }
        if (_isCameraInitialized && _cameraController != null && _cameraController!.value.isInitialized) {
          await _initModel(); // Ensure model is loaded
          final tfliteService = ref.read(tfliteServiceProvider); // Read after attempting to load
          if (tfliteService.isModelLoaded && !(_cameraController!.value.isStreamingImages)) {
            await _cameraController!.startImageStream(_processCameraImage);
            print("ScannerScreen: ObjectDetection stream started.");
          } else if (!tfliteService.isModelLoaded) {
            print("ScannerScreen: TFLite model NOT loaded. Cannot start ObjectDetection stream.");
          } else {
            print("ScannerScreen: ObjectDetection stream already running or other issue.");
          }
        }
      } else if (mode == ScannerMode.Ocr) {
        if (_cameraController?.value.isStreamingImages ?? false) {
          await _cameraController!.stopImageStream();
          _processingInQueue = false;
        }
        if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
          await _initializeMainCameraController();
        }
      }
      if (mounted) setState(() {});
    } catch (e, s) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error switching to $mode: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _changeScannerMode(ScannerMode newMode) async {
    ScannerMode targetMode = (newMode == ScannerMode.Barcode) ? ScannerMode.ObjectDetection : newMode;
    final currentMode = ref.read(currentScannerModeProvider);
    if (targetMode == currentMode && _isCameraInitialized) {
      await _setActiveModeResources(targetMode); return;
    }
    ref.read(currentScannerModeProvider.notifier).state = targetMode;
    _resetScanStates();
    await _setActiveModeResources(targetMode);
  }

  void _resetScanStates() {
    ref.read(yoloDetectionsProvider.notifier).state = [];
    if (mounted) {
      setState(() { _processingInQueue = false; _isProcessingOcr = false; });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final currentMode = ref.read(currentScannerModeProvider);
    if (currentMode != ScannerMode.ObjectDetection || !mounted || _isProcessingOcr || _processingInQueue) {
      return;
    }
    final tfliteService = ref.read(tfliteServiceProvider);
    if (!tfliteService.isModelLoaded) {
      print("ScannerScreen: _processCameraImage - TFLite model not loaded. Attempting to load now...");
      await _initModel();
      if (!tfliteService.isModelLoaded && mounted) {
        print("ScannerScreen: _processCameraImage - TFLite model still not loaded after attempt. Skipping frame.");
        return;
      }
    }

    _processingInQueue = true;
    try {
      final recognitions = await tfliteService.runObjectDetection(image);
      if (mounted) {
        ref.read(yoloDetectionsProvider.notifier).state = recognitions ?? [];
      }
    } catch (e, s) {
      print("ScannerScreen: Error running TFLite object detection: $e\n$s");
      if (mounted) ref.read(yoloDetectionsProvider.notifier).state = [];
    } finally {
      _processingInQueue = false;
    }
  }

  Future<void> _captureAndProcessOcr() async {
    final currentMode = ref.read(currentScannerModeProvider);
    if (currentMode != ScannerMode.Ocr || _isProcessingOcr || _processingInQueue || _cameraController == null || !_cameraController!.value.isInitialized || !mounted) return;
    setStateIfMounted(() { _isProcessingOcr = true; });
    if (_cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream(); _processingInQueue = false;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    String? extractedTextResult; List<String> foundAllergensResult = []; String? errorResult;
    try {
      if (!_cameraController!.value.isTakingPicture) {
        final XFile imageFile = await _cameraController!.takePicture();
        final ocrService = ref.read(ocrServiceProvider);
        extractedTextResult = await ocrService.extractTextFromImagePath(imageFile.path);
        final userProfile = ref.read(userProfileProvider).valueOrNull;
        if (userProfile != null && extractedTextResult != null) {
          foundAllergensResult = _compareTextWithAllergens(extractedTextResult, userProfile.allergens);
        }
      } else { errorResult = "Camera busy."; }
    } catch (e) { errorResult = 'Error processing OCR: ${e.toString()}';
    } finally {
      if (mounted) {
        setState(() { _isProcessingOcr = false; });
        _showOcrResultsBottomSheet(extractedTextResult, foundAllergensResult, errorMsg: errorResult);
      }
    }
  }

  List<String> _compareTextWithAllergens(String text, List<String> userAllergens) {
    final List<String> found = []; if (text.isEmpty || userAllergens.isEmpty) return found;
    final processedText = text.toLowerCase();
    final Map<String, String> userAllergensMap = { for (var allergen in userAllergens) allergen.toLowerCase() : allergen };
    for (final lowerCaseAllergen in userAllergensMap.keys) {
      if (lowerCaseAllergen.trim().isEmpty) continue;
      if (processedText.contains(lowerCaseAllergen)) found.add(userAllergensMap[lowerCaseAllergen]!);
    }
    return found;
  }

  void _showOcrResultsBottomSheet(String? extractedText, List<String> foundAllergens, {String? errorMsg}) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (BuildContext bc) => FractionallySizedBox(
        heightFactor: 0.7,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text("Ingredient Scan Results", style: Theme.of(context).textTheme.headlineSmall),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())
              ]),
              const Divider(),
              if (errorMsg != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text("Error: $errorMsg", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
              if (extractedText != null) ...[
                Text("Extracted Text:", style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 4),
                Expanded(flex: 3, child: Container(
                  padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey[100], border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(4)),
                  child: SingleChildScrollView(child: SelectableText(extractedText.isNotEmpty ? extractedText : "(No text detected)")),
                )), const SizedBox(height: 16),
                Text("Potential User Allergens Found:", style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 4),
                Expanded(flex: 2, child: SingleChildScrollView(
                  child: Wrap(spacing: 8.0, runSpacing: 4.0, children: foundAllergens.isEmpty
                      ? [const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text("None of your listed allergens detected."))]
                      : foundAllergens.map((allergen) => Chip(
                    label: Text(allergen), backgroundColor: Colors.red[100], labelStyle: const TextStyle(color: Colors.redAccent), side: BorderSide(color: Colors.red[200]!),
                  )).toList(),
                  ),
                )),
              ] else if (errorMsg == null) ...[const Expanded(child: Center(child: Text("No text detected in the image.")))],
            ],
          ),
        ),
      ),
    );
  }

  void setStateIfMounted(VoidCallback fn) { if (mounted) setState(fn); }

  @override
  Future<void> dispose() async {
    print("ScannerScreen: dispose CALLED (Camera-Only Test)");
    if (_cameraController != null) {
      try {
        if (_cameraController!.value.isStreamingImages) await _cameraController!.stopImageStream();
        await _cameraController!.dispose();
      } catch (e) { print("ScannerScreen: Error disposing main CameraController: $e");
      } finally { _cameraController = null; _isCameraInitialized = false; }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(currentScannerModeProvider);
    bool showOcrFab = currentMode == ScannerMode.Ocr && _isCameraInitialized && !_isProcessingOcr && (_cameraController?.value.isInitialized ?? false) ;

    return Scaffold(
      appBar: AppBar(
        title: Text("Scan: ${currentMode.name} (TFLite Test)"),
        backgroundColor: Colors.black.withOpacity(0.3), elevation: 0, systemOverlayStyle: SystemUiOverlayStyle.light,
        actions: const [SizedBox(width: 48)],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand, alignment: Alignment.center,
        children: [
          _buildCameraPreview(),
          if (currentMode == ScannerMode.ObjectDetection) _buildObjectDetectionOverlay(),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), color: Colors.black.withOpacity(0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<ScannerMode>(
                    segments: const <ButtonSegment<ScannerMode>>[
                      ButtonSegment<ScannerMode>(value: ScannerMode.ObjectDetection, label: Text('Product'), icon: Icon(Icons.camera_alt_outlined)),
                      ButtonSegment<ScannerMode>(value: ScannerMode.Ocr, label: Text('Ingredients'), icon: Icon(Icons.document_scanner_outlined)),
                    ],
                    selected: <ScannerMode>{currentMode == ScannerMode.Barcode ? ScannerMode.ObjectDetection : currentMode},
                    onSelectionChanged: (Set<ScannerMode> newSelection) {
                      if (_processingInQueue || _isProcessingOcr) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Scan busy."), duration: Duration(seconds: 1)));
                        return;
                      }
                      _changeScannerMode(newSelection.first);
                    },
                    style: SegmentedButton.styleFrom(
                      backgroundColor: Colors.grey[850]?.withOpacity(0.9), foregroundColor: Colors.white70,
                      selectedBackgroundColor: Theme.of(context).colorScheme.primaryContainer, selectedForegroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                      textStyle: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            )),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: showOcrFab
          ? FloatingActionButton.large(
        heroTag: 'ocr_capture_button', onPressed: _captureAndProcessOcr, tooltip: 'Scan Ingredients Text',
        child: const Icon(Icons.camera_enhance_sharp),
      )
          : null,
    );
  }

  Widget _buildCameraPreview() {
    final currentMode = ref.watch(currentScannerModeProvider);
    if (_isCameraInitializing) return Container(color: Colors.black, child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Initializing Camera...", style: TextStyle(color: Colors.white, fontSize: 16))])));
    if (!_isPermissionGranted) {
      return Container(color: Colors.black, child: Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.no_photography, size: 60, color: Colors.white70), const SizedBox(height: 16),
      const Text('Camera Permission Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 10),
      const Text('Please grant camera access in settings.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 16)), const SizedBox(height: 24),
      ElevatedButton.icon(icon: const Icon(Icons.settings), label: const Text('Open App Settings'), onPressed: openAppSettings),
    ]))));
    }
    if (_cameraInitializationError != null) return Container(color: Colors.black, child: Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Camera Error:\n${_cameraInitializationError!.description}', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 16)))));

    if (_tfliteModelLoadError != null && currentMode == ScannerMode.ObjectDetection) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            "Error loading product detection model:\n$_tfliteModelLoadError",
            style: TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_cameraController != null && _cameraController!.value.isInitialized) {
      print("ScannerScreen: _buildCameraPreview - Rendering CameraPreview for mode: $currentMode (TFLite Test).");
      return CameraPreview(_cameraController!);
    }
    else {
      print("ScannerScreen: _buildCameraPreview - _cameraController not ready for mode $currentMode (TFLite Test).");
      return Container(color: Colors.black, child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 8), Text("Camera Starting...", style: TextStyle(color: Colors.white))])));
    }
  }

  Widget _buildObjectDetectionOverlay() {
    final currentMode = ref.watch(currentScannerModeProvider);
    if (currentMode != ScannerMode.ObjectDetection || !_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final detections = ref.watch(yoloDetectionsProvider);
    final previewSize = _cameraController!.value.previewSize;
    if (previewSize != null && previewSize.height > 0 && previewSize.width > 0 && detections.isNotEmpty) {
      return LayoutBuilder(builder: (context, constraints) {
        return CustomPaint(
          painter: DetectionPainter(detections, previewSize, 1.0, 0.0, 0.0),
          size: constraints.biggest,
        );
      });
    }
    return const SizedBox.shrink();
  }
}