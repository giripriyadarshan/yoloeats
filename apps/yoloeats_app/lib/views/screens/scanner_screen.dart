import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ml_providers.dart';
import '../../providers/camera_providers.dart';
import '../../providers/ocr_providers.dart';
import '../../providers/user_profile_providers.dart';
import '../painters/detection_painter.dart';
import 'product_detail_screen.dart';
import 'multi_scan_results_screen.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  CameraController? _cameraController;
  MobileScannerController? _barcodeController;
  bool _isCameraInitialized = false;
  bool _isCameraInitializing = false;
  bool _isPermissionGranted = false;
  CameraException? _cameraInitializationError;

  bool _isProcessingSingleBarcode = false;
  bool _isDetectingObjects = false;
  bool _isProcessingOcr = false;
  bool _isBarcodeScannerRunning = false;

  @override
  void initState() {
    super.initState();
    print("ScannerScreen: initState");
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initScreen();
    });
  }

  Future<void> _initScreen() async {
    print("ScannerScreen: _initScreen started");
    await _checkPermissionAndInitializeCamera();
    _initModel();

    if (_isPermissionGranted && mounted) {
      final currentMode = ref.read(currentScannerModeProvider);
      if (currentMode == ScannerMode.Barcode) {
        _initializeBarcodeScanner();
      }
      await _updateStreamingState(currentMode);
    }
    print("ScannerScreen: _initScreen finished");
  }


  Future<void> _initModel() async {
    try {
      print("ScannerScreen: Initializing TFLite model...");
      await ref.read(tfliteServiceProvider).loadModel();
      print("ScannerScreen: TFLite model initialized.");
    } catch (e) {
      print("ScannerScreen: Error initializing model: $e");
    }
  }

  void _initializeBarcodeScanner() {
    print("ScannerScreen: Initializing Barcode Scanner Controller...");
    if (_barcodeController == null) {
      _barcodeController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        formats: [BarcodeFormat.ean13, BarcodeFormat.code128, BarcodeFormat.qrCode, BarcodeFormat.upcA, BarcodeFormat.upcE],
        returnImage: false,
      );
      _isBarcodeScannerRunning = false;
      print("ScannerScreen: Barcode Scanner Controller initialized.");
    } else {
      print("ScannerScreen: Barcode Scanner Controller already exists.");
    }
  }


  @override
  Future<void> dispose() async {
    print("ScannerScreen: dispose");
    try {
      if (_barcodeController != null) {
        _barcodeController!.stop();
        _barcodeController!.dispose();
        _barcodeController = null;
        _isBarcodeScannerRunning = false;
        print("ScannerScreen: Barcode Scanner Controller stopped and disposed.");
      }
    } catch (e) {
      print("ScannerScreen: Error stopping/disposing barcode scanner: $e");
    }

    if (_cameraController != null) {
      print("ScannerScreen: Disposing CameraController...");
      try {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
          print("ScannerScreen: Camera stream stopped.");
        }
      } catch (e) {
        print("ScannerScreen: Error stopping camera stream during dispose: $e");
      }
      await _cameraController!.dispose();
      print("ScannerScreen: CameraController disposed.");
      _cameraController = null;
      _isCameraInitialized = false;
    }
    super.dispose();
  }

  Future<void> _checkPermissionAndInitializeCamera() async {
    print("ScannerScreen: Checking camera permission...");
    if (_isCameraInitializing) return;
    setState(() { _isCameraInitializing = true; });

    final status = await Permission.camera.request();
    print("ScannerScreen: Camera permission status: $status");
    if (mounted) {
      final bool granted = status.isGranted || status.isLimited;
      setStateIfMounted(() {
        _isPermissionGranted = granted;
        _cameraInitializationError = null;
      });

      if (granted) {
        print("ScannerScreen: Camera permission granted. Initializing camera...");
        await _initializeCamera();
        _initializeBarcodeScanner();
        await _updateStreamingState(ref.read(currentScannerModeProvider));

      } else {
        print("ScannerScreen: Camera permission denied.");
        setStateIfMounted(() {
          _isCameraInitialized = false;
          _cameraController = null;
          _resetScanStates();
        });
      }
      setStateIfMounted(() { _isCameraInitializing = false; });
    } else {
      _isCameraInitializing = false;
    }
  }

  Future<void> _initializeCamera() async {
    if (_cameraController != null || !_isPermissionGranted) {
      print("ScannerScreen: Skipping camera initialization (already init or no permission).");
      return;
    }
    print("ScannerScreen: Finding available cameras...");
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException("NO_CAMERAS", "No cameras found.");
      print("ScannerScreen: Cameras found: ${cameras.length}");

      CameraDescription selectedCamera = cameras.firstWhere(
            (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      print("ScannerScreen: Selected camera: ${selectedCamera.name}");

      if (_cameraController != null) {
        await _cameraController!.dispose();
        _cameraController = null;
      }


      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      print("ScannerScreen: Initializing CameraController...");
      await _cameraController!.initialize();
      print("ScannerScreen: CameraController initialized.");

      setStateIfMounted(() {
        _isCameraInitialized = true;
        _cameraInitializationError = null;
      });

    } on CameraException catch (e) {
      print("ScannerScreen: CameraException during initialization: ${e.code} - ${e.description}");
      setStateIfMounted(() { _cameraInitializationError = e; _isCameraInitialized = false; });
    } catch (e) {
      print("ScannerScreen: Generic error during camera initialization: $e");
      setStateIfMounted(() => _cameraInitializationError = CameraException("INIT_ERROR", e.toString()));
    } finally {
      if (mounted && _cameraInitializationError != null) {
        setState(() => _isCameraInitialized = false);
      }
    }
  }

  void _changeScannerMode(ScannerMode newMode) {
    print("ScannerScreen: Changing mode to $newMode");
    final currentMode = ref.read(currentScannerModeProvider);
    if (newMode == currentMode) return;

    // Explicitly stop barcode scanner if it was running, before resetting states
    if (currentMode == ScannerMode.Barcode && _isBarcodeScannerRunning && _barcodeController != null) { // ADDED CHECK
      print("ScannerScreen: Explicitly stopping barcode scanner due to mode change from Barcode.");
      try {
        _barcodeController!.stop();
        _isBarcodeScannerRunning = false; // Update state immediately
      } catch (e) {
        print("ScannerScreen: Error explicitly stopping barcode scanner: $e");
      }
    }

    ref.read(currentScannerModeProvider.notifier).state = newMode;
    _resetScanStates(); // This resets flags, but controller might still be an issue
    _updateStreamingState(newMode);
  }

  void _resetScanStates() {
    print("ScannerScreen: Resetting scan states");
    ref.read(yoloDetectionsProvider.notifier).state = [];
    ref.read(detectedBarcodeProvider.notifier).state = null;
    setStateIfMounted(() {
      _isProcessingSingleBarcode = false;
      _isDetectingObjects = false;
      _isProcessingOcr = false;
    });
  }

  Future<void> _updateStreamingState(ScannerMode mode) async {
    print("ScannerScreen: Updating streaming state for mode $mode");

    // First stop all camera operations
    if (_isBarcodeScannerRunning && _barcodeController != null) {
      _barcodeController!.stop();
      _isBarcodeScannerRunning = false;
    }

    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
    }

    // Then start only what's needed for the current mode
    if (mode == ScannerMode.Barcode && _barcodeController != null) {
      _barcodeController!.start();
      _isBarcodeScannerRunning = true;
    } else if (mode == ScannerMode.ObjectDetection && _cameraController != null) {
      await _cameraController!.startImageStream((image) {
        _processCameraImage(image);
      });
    }
  }

  // A flag to track if processing is already in progress
  bool _processingInQueue = false;

  Future<void> _processCameraImage(CameraImage image) async {
    // First quick check to avoid unnecessary processing
    if (ref.read(currentScannerModeProvider) != ScannerMode.ObjectDetection ||
        !mounted || _isProcessingOcr || _isProcessingSingleBarcode) {
      return;
    }

    // If we're already detecting or have a frame in the queue, skip this frame
    if (_isDetectingObjects || _processingInQueue) {
      return;
    }

    // Mark that we've queued up processing
    _processingInQueue = true;

    // Use compute or isolate for heavy processing
    // This moves processing off the main thread
    await Future.microtask(() async {
      if (!mounted) {
        _processingInQueue = false;
        return;
      }

      final tfliteService = ref.read(tfliteServiceProvider);
      if (!tfliteService.isModelLoaded) {
        _processingInQueue = false;
        return;
      }

      setStateIfMounted(() { _isDetectingObjects = true; });

      try {
        final recognitions = await tfliteService.runObjectDetection(image);
        if (mounted) {
          ref.read(yoloDetectionsProvider.notifier).state = recognitions ?? [];
        }
      } catch (e) {
        print("ScannerScreen: Error running TFLite detection: $e");
        if (mounted) {
          ref.read(yoloDetectionsProvider.notifier).state = [];
        }
      } finally {
        // Remove the artificial delay - let the natural processing time create spacing
        setStateIfMounted(() { _isDetectingObjects = false; });
        _processingInQueue = false;
      }
    });
  }

  void _handleBarcodeDetection(BarcodeCapture capture) {
    if (ref.read(currentScannerModeProvider) != ScannerMode.Barcode ||
        capture.barcodes.isEmpty || _isProcessingOcr || !mounted) {
      return;
    }

    final isMultiScanMode = ref.read(multiScanModeProvider);
    final String? barcodeValue = capture.barcodes.first.rawValue;

    if (barcodeValue == null || barcodeValue.isEmpty) return;

    if (isMultiScanMode) {
      final currentBarcodes = ref.read(multiScanBarcodesProvider);
      if (!currentBarcodes.contains(barcodeValue)) {
        print("ScannerScreen: Multi-Scan adding barcode $barcodeValue");
        HapticFeedback.mediumImpact();
        ref.read(multiScanBarcodesProvider.notifier).update((state) => [...state, barcodeValue]);
      }
    }
    else {
      if (!_isProcessingSingleBarcode) {
        print('ScannerScreen: Single scan detected: $barcodeValue');
        setStateIfMounted(() { _isProcessingSingleBarcode = true; });
        ref.read(detectedBarcodeProvider.notifier).state = barcodeValue;
        ref.read(yoloDetectionsProvider.notifier).state = [];

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(productIdentifier: barcodeValue),
          ),
        ).then((_) {
          print("ScannerScreen: Returned from ProductDetailScreen (or replacement), resetting single scan flag.");
          setStateIfMounted(() { _isProcessingSingleBarcode = false; });
          ref.read(detectedBarcodeProvider.notifier).state = null;
          if(mounted) _updateStreamingState(ref.read(currentScannerModeProvider));
        });
      }
    }
  }

  Future<void> _captureAndProcessOcr() async {
    if (ref.read(currentScannerModeProvider) != ScannerMode.Ocr ||
        _isProcessingOcr || _cameraController == null ||
        !_cameraController!.value.isInitialized || !mounted) {
      print("ScannerScreen: OCR skipped (wrong mode, busy, or camera not ready)");
      return;
    }

    print("ScannerScreen: Starting OCR process...");
    setStateIfMounted(() { _isProcessingOcr = true; });

    // Properly release camera resources before taking a picture
    bool wasStreamingImages = false;
    bool wasBarcodeRunning = false;

    // Stop barcode scanner if running
    if (_isBarcodeScannerRunning && _barcodeController != null) {
      print("ScannerScreen: Stopping barcode scanner for OCR");
      _barcodeController!.stop();
      wasBarcodeRunning = true;
      _isBarcodeScannerRunning = false;
    }

    // Stop image stream if running
    if (_cameraController!.value.isStreamingImages) {
      print("ScannerScreen: Stopping camera stream for OCR");
      await _cameraController!.stopImageStream();
      wasStreamingImages = true;
    }

    // Give a moment for resources to be released
    await Future.delayed(const Duration(milliseconds: 100));

    String? extractedTextResult;
    List<String> foundAllergensResult = [];
    String? errorResult;

    try {
      print("ScannerScreen: Capturing picture for OCR...");
      final XFile imageFile = await _cameraController!.takePicture();
      print('ScannerScreen: Picture saved to ${imageFile.path}');

      // Process OCR as before...
      final ocrService = ref.read(ocrServiceProvider);
      extractedTextResult = await ocrService.extractTextFromImagePath(imageFile.path);

      final userProfile = ref.read(userProfileProvider).valueOrNull;
      if (userProfile != null && extractedTextResult != null) {
        foundAllergensResult = _compareTextWithAllergens(extractedTextResult, userProfile.allergens);
      }

    } catch (e) {
      print("ScannerScreen: Error during OCR capture/processing: $e");
      errorResult = 'Error processing image: $e';
    } finally {
      // Restore previous camera state
      if (mounted) {
        setState(() { _isProcessingOcr = false; });

        // Restart streams based on what was active before
        if (wasStreamingImages && ref.read(currentScannerModeProvider) == ScannerMode.ObjectDetection) {
          await _cameraController!.startImageStream((image) {
            // Your image processing logic
          });
        }

        if (wasBarcodeRunning && ref.read(currentScannerModeProvider) == ScannerMode.Barcode &&
            _barcodeController != null) {
          _barcodeController!.start();
          _isBarcodeScannerRunning = true;
        }

        if (mounted) {
          _showOcrResultsBottomSheet(extractedTextResult, foundAllergensResult, errorMsg: errorResult);
        }
      }
    }
  }

  List<String> _compareTextWithAllergens(String text, List<String> userAllergens) {
    final List<String> found = [];
    if (text.isEmpty || userAllergens.isEmpty) return found;
    final processedText = text.toLowerCase();
    final userAllergensLower = userAllergens.map((a) => a.toLowerCase()).toSet();
    for (final allergen in userAllergensLower) {
      if (allergen.trim().isEmpty) continue;
      if (processedText.contains(allergen)) {
        found.add(userAllergens.firstWhere((ua) => ua.toLowerCase() == allergen, orElse: () => allergen));
      }
    }
    return found;
  }


  void _showOcrResultsBottomSheet(String? extractedText, List<String> foundAllergens, {String? errorMsg}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext bc) {
        return FractionallySizedBox(
          heightFactor: 0.7,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Ingredient Scan Results", style: Theme.of(context).textTheme.headlineSmall),
                const Divider(),
                if (errorMsg != null)
                  Text("Error: $errorMsg", style: const TextStyle(color: Colors.red)),

                if (extractedText != null) ...[
                  Text("Extracted Text:", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.grey[100],
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(4)),
                      child: SingleChildScrollView(
                          child: SelectableText(extractedText.isNotEmpty ? extractedText : "(No text detected)")),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text("Potential User Allergens Found:", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8.0, runSpacing: 4.0,
                        children: foundAllergens.isEmpty
                            ? [const Text("None of your listed allergens detected.")]
                            : foundAllergens.map((allergen) => Chip(
                          label: Text(allergen),
                          backgroundColor: Colors.red[100],
                          labelStyle: const TextStyle(color: Colors.red),
                          side: BorderSide(color: Colors.red[200]!),
                        )).toList(),
                      ),
                    ),
                  ),
                ] else if (errorMsg == null) ...[
                  const Expanded(child: Center(child: Text("No text detected in the image."))),
                ],

                const SizedBox(height: 16),
                Center(child: ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Close")))
              ],
            ),
          ),
        );
      },
    );
  }

  void _viewMultiScanResults() {
    final barcodes = ref.read(multiScanBarcodesProvider);
    if (barcodes.isEmpty || !mounted) return;
    print("ScannerScreen: Navigating to multi-scan results with ${barcodes.length} items.");

    final notifier = ref.read(multiScanBarcodesProvider.notifier);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MultiScanResultsScreen(barcodes: barcodes)),
    ).then((_) {
      print("ScannerScreen: Returned from MultiScanResultsScreen, clearing scanned barcodes.");
      notifier.state = [];
    });
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    } else {
      print("ScannerScreen: setStateIfMounted called but widget is not mounted.");
    }
  }


  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(currentScannerModeProvider);
    final isMultiScan = ref.watch(multiScanModeProvider);
    final scannedBarcodes = ref.watch(multiScanBarcodesProvider);
    final scannedCount = scannedBarcodes.length;

    return Scaffold(
      appBar: AppBar(
        title: Text("Scan: ${currentMode.name}"),
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
        actions: [
          if (currentMode == ScannerMode.Barcode)
            Tooltip(
              message: isMultiScan ? "Switch to Single Scan" : "Switch to Multi-Scan",
              child: IconButton(
                icon: Icon(isMultiScan ? Icons.filter_center_focus : Icons.checklist_rtl_outlined),
                color: isMultiScan ? Theme.of(context).colorScheme.primary : Colors.white,
                onPressed: () {
                  final newValue = !isMultiScan;
                  ref.read(multiScanModeProvider.notifier).state = newValue;
                  if (!newValue) ref.read(multiScanBarcodesProvider.notifier).state = [];
                  ref.read(detectedBarcodeProvider.notifier).state = null;
                  setStateIfMounted(() { _isProcessingSingleBarcode = false; });
                },
              ),
            )
          else const SizedBox(width: 48),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),

          if (currentMode == ScannerMode.ObjectDetection) _buildObjectDetectionOverlay(),

          if (currentMode == ScannerMode.Ocr) _buildOcrCaptureOverlay(),

          if (currentMode == ScannerMode.Barcode && isMultiScan) _buildMultiScanCounter(scannedCount),

          if (currentMode == ScannerMode.Barcode && !isMultiScan) _buildSingleBarcodeOverlay(),


          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Colors.black.withOpacity(0.6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<ScannerMode>(
                      segments: const <ButtonSegment<ScannerMode>>[
                        ButtonSegment<ScannerMode>(value: ScannerMode.Barcode, label: Text('Barcode'), icon: Icon(Icons.qr_code_scanner)),
                        ButtonSegment<ScannerMode>(value: ScannerMode.ObjectDetection, label: Text('Product'), icon: Icon(Icons.visibility)),
                        ButtonSegment<ScannerMode>(value: ScannerMode.Ocr, label: Text('Text'), icon: Icon(Icons.document_scanner_outlined)),
                      ],
                      selected: <ScannerMode>{currentMode},
                      onSelectionChanged: (Set<ScannerMode> newSelection) {
                        _changeScannerMode(newSelection.first);
                      },
                      style: SegmentedButton.styleFrom(
                        backgroundColor: Colors.grey[800]?.withOpacity(0.8),
                        foregroundColor: Colors.white,
                        selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                        selectedForegroundColor: Colors.black,
                      ),
                    ),

                    if (currentMode == ScannerMode.Barcode && isMultiScan && scannedCount > 0) ...[
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.playlist_add_check),
                        label: Text('View $scannedCount Scanned Item(s)'),
                        onPressed: _viewMultiScanResults,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 45),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildCameraPreview() {
    if (_isCameraInitializing) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 10), Text("Initializing Camera...")],));
    }
    if (!_isPermissionGranted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Camera permission required.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Please grant camera access in settings to use scanning features.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: openAppSettings, child: const Text('Open App Settings')),
            ],
          ),
        ),
      );
    }
    if (_cameraInitializationError != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text('Camera Initialization Error:\n${_cameraInitializationError!.description}', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ));
    }
    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: Text("Waiting for camera..."));
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.width * _cameraController!.value.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(_cameraController!),
              if(_barcodeController != null)
                MobileScanner(
                  controller: _barcodeController!,
                  onDetect: _handleBarcodeDetection,
                )
              else Container(color: Colors.black.withOpacity(0.5), child: const Center(child: Text("Barcode Scanner Initializing...", style: TextStyle(color: Colors.white)))),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObjectDetectionOverlay() {
    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) return const SizedBox.shrink();

    final detections = ref.watch(yoloDetectionsProvider);
    final previewSize = _cameraController!.value.previewSize;

    if (previewSize != null && previewSize != Size.zero) {
      return LayoutBuilder(
          builder: (context, constraints) {
            final scaleX = constraints.maxWidth / previewSize.width;
            final scaleY = constraints.maxHeight / previewSize.height;
            final scale = scaleX < scaleY ? scaleX : scaleY;

            final offsetX = (constraints.maxWidth - previewSize.width * scale) / 2;
            final offsetY = (constraints.maxHeight - previewSize.height * scale) / 2;


            return CustomPaint(
              painter: DetectionPainter(
                  detections,
                  previewSize,
                  scale,
                  offsetX,
                  offsetY
              ),
              size: constraints.biggest,
            );
          }
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildOcrCaptureOverlay() {
    return Positioned(
      bottom: 100,
      child: FloatingActionButton.large(
        heroTag: 'ocr_capture_button',
        onPressed: _isProcessingOcr ? null : _captureAndProcessOcr,
        tooltip: 'Scan Ingredients Text',
        child: _isProcessingOcr
            ? const CircularProgressIndicator(color: Colors.white,)
            : const Icon(Icons.camera_enhance_sharp),
      ),
    );
  }

  Widget _buildMultiScanCounter(int count) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      right: 10,
      child: Chip(
        avatar: CircleAvatar(child: Text('$count')),
        label: const Text('Items'),
        backgroundColor: Colors.black.withOpacity(0.7),
        labelStyle: const TextStyle(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  Widget _buildSingleBarcodeOverlay() {
    final barcode = ref.watch(detectedBarcodeProvider);
    if (barcode == null || _isProcessingSingleBarcode) return const SizedBox.shrink();

    return Positioned(
      bottom: 100,
      left: 20, right: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(20)),
          child: Text(
            'Detected: $barcode',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

}