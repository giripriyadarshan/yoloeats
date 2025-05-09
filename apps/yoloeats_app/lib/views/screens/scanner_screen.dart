import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../providers/camera_providers.dart';
import '../../providers/ml_providers.dart';
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
  bool _isCameraControllerInitialized = false;
  ScanMode _currentActiveScanMode = ScanMode.none;

  final MobileScannerController _mobileScannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  String? _tfliteModelLoadError;
  bool _isCameraInitializing = false;
  CameraException? _cameraInitializationError;
  bool _isPermissionGranted = false;

  bool _processingInQueue = false;
  bool _isProcessingOcr = false;

  ProviderSubscription<ScanMode>? _scanModeListenerSubscription;

  @override
  void initState() {
    super.initState();
    print("ScannerScreen: initState");

    _currentActiveScanMode = ref.read(scanModeProvider);
    print("ScannerScreen: Initial _currentActiveScanMode read as: $_currentActiveScanMode");

    _scanModeListenerSubscription = ref.listenManual<ScanMode>(
      scanModeProvider,
      _onScanModeChanged,
      fireImmediately: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestCameraPermissionIfNeeded();
    });
  }

  Future<void> _checkAndRequestCameraPermissionIfNeeded() async {
    if (!_isPermissionGranted && !_isCameraInitializing) {
      await _checkAndRequestCameraPermission();
    }
  }

  void _onScanModeChanged(ScanMode? previousMode, ScanMode newMode) {
    print("ScannerScreen: Listener triggered. Mode changed from $previousMode to $newMode");
    _currentActiveScanMode = newMode;
    _handleModeChange(previousMode ?? ScanMode.none, newMode);
  }

  Future<void> _disposeCameraController() async {
    if (_cameraController != null) {
      print("ScannerScreen: Disposing CameraController...");
      if (mounted && _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
        print("ScannerScreen: Image stream stopped.");
      }
      await _cameraController!.dispose();
      print("ScannerScreen: CameraController disposed.");
    }
    _cameraController = null;
    _isCameraControllerInitialized = false;
    _processingInQueue = false;
    if (mounted) {
      ref.read(yoloDetectionsProvider.notifier).state = [];
    }
  }

  Future<void> _initializeCameraControllerAndStream(ScanMode activeMode) async {
    if (_cameraController != null && _isCameraControllerInitialized) {
      print("ScannerScreen: CameraController already exists for $activeMode. Disposing existing one first.");
      await _disposeCameraController();
    }

    if (!_isPermissionGranted) {
      print("ScannerScreen: Camera permission not granted. Requesting for $activeMode...");
      await _checkAndRequestCameraPermission();
      if (!_isPermissionGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Camera permission is required for $activeMode.")));
        _cameraInitializationError = CameraException("PERMISSION_DENIED_INIT", "Permission denied for $activeMode");
        if (mounted) setState(() {});
        return;
      }
    }

    print("ScannerScreen: Initializing CameraController for mode: $activeMode");
    setStateIfMounted(() { _isCameraInitializing = true; _cameraInitializationError = null; });

    List<CameraDescription> cameras = [];
    try {
      cameras = await availableCameras();
    } catch (e) {
      print("ScannerScreen: Error fetching available cameras: $e");
      _cameraInitializationError = CameraException("CAMERAS_UNAVAILABLE", e.toString());
      if (mounted) setStateIfMounted(() { _isCameraInitializing = false; });
      return;
    }

    if (cameras.isEmpty) {
      print("ScannerScreen: No cameras available!");
      _cameraInitializationError = CameraException("NO_CAMERAS_FOUND", "No cameras available on device.");
      if (mounted) setStateIfMounted(() { _isCameraInitializing = false; });
      return;
    }
    final firstCamera = cameras.firstWhere(
            (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first);

    _cameraController = CameraController(
      firstCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();
      _isCameraControllerInitialized = true;
      print("ScannerScreen: CameraController initialized.");

      if (activeMode == ScanMode.objectDetection && _cameraController!.value.isInitialized && mounted) {
        await _initModel();
        final tfliteService = ref.read(tfliteServiceProvider);
        if (tfliteService.isModelLoaded) {
          print("ScannerScreen: Starting image stream for Object Detection.");
          if (!_cameraController!.value.isStreamingImages) {
            await _cameraController!.startImageStream(_processCameraImageForTFLite);
          }
        } else {
          print("ScannerScreen: TFLite model not loaded. Cannot start stream for Object Detection.");
        }
      } else if (activeMode == ScanMode.ocr) {
        print("ScannerScreen: CameraController ready for OCR (take picture).");
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
          _processingInQueue = false;
        }
      }
    } catch (e) {
      print("ScannerScreen: Error initializing CameraController: $e");
      _cameraInitializationError = CameraException("INIT_FAILED", e.toString());
      await _disposeCameraController();
    } finally {
      if (mounted) setStateIfMounted(() { _isCameraInitializing = false; });
    }
  }

  Future<void> _handleModeChange(ScanMode? oldMode, ScanMode newMode) async {
    print("ScannerScreen: _handleModeChange from $oldMode to $newMode.");

    if (oldMode != null && oldMode != newMode) {
      print("ScannerScreen: Cleaning up resources for oldMode: $oldMode");
      if (oldMode == ScanMode.objectDetection || oldMode == ScanMode.ocr) {
        await _disposeCameraController();
      } else if (oldMode == ScanMode.barcodeScanning) {
        print("ScannerScreen: Stopping MobileScannerController for oldMode: $oldMode");
        try {
          await _mobileScannerController.stop();
        } catch (e) {
          print("ScannerScreen: Error stopping MobileScannerController for oldMode $oldMode: $e");
        }
      }
    }

    print("ScannerScreen: Setting up resources for newMode: $newMode");
    switch (newMode) {
      case ScanMode.objectDetection:
      case ScanMode.ocr:
        if (oldMode == ScanMode.barcodeScanning || newMode != ScanMode.barcodeScanning) {
          try {
            await _mobileScannerController.stop();
            print("ScannerScreen: MobileScannerController stopped (if active) before switching to OD/OCR.");
          } catch (e) {
            print("ScannerScreen: Non-critical error stopping mobile scanner: $e");
          }
        }
        await _initializeCameraControllerAndStream(newMode);
        break;
      case ScanMode.barcodeScanning:
        if (_cameraController != null) {
          await _disposeCameraController();
        }
        if (!_isPermissionGranted) {
          await _checkAndRequestCameraPermission();
        }
        if (_isPermissionGranted && mounted) {
          print("ScannerScreen: Attempting to start MobileScannerController for BarcodeScanning.");
          try {
            await _mobileScannerController.start();
          } catch (e) {
            print("ScannerScreen: Error starting MobileScannerController: $e");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error starting barcode scanner: ${e.toString()}")));
            }
          }
        }
        break;
      case ScanMode.none:
        print("ScannerScreen: Mode is ScanMode.none. Disposing/stopping all camera resources.");
        await _disposeCameraController();
        try {
          await _mobileScannerController.stop();
          print("ScannerScreen: MobileScannerController stopped for ScanMode.none.");
        } catch (e) {
          print("ScannerScreen: Error stopping MobileScannerController for ScanMode.none: $e");
        }
        break;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkAndRequestCameraPermission() async {
    print("ScannerScreen: Checking and requesting camera permission...");
    if (_isCameraInitializing) return;
    setStateIfMounted(() { _isCameraInitializing = true; _cameraInitializationError = null; });

    final status = await Permission.camera.request();

    if (mounted) {
      setStateIfMounted(() {
        _isPermissionGranted = status.isGranted || status.isLimited;
        if (!_isPermissionGranted) {
          _cameraInitializationError = CameraException("PERMISSION_DENIED", "Camera permission not granted by user.");
          _isCameraControllerInitialized = false;
        } else {
          _cameraInitializationError = null;
        }
        _isCameraInitializing = false;
      });
    } else {
      _isCameraInitializing = false;
    }
  }

  Future<void> _initModel() async {
    final tfliteService = ref.read(tfliteServiceProvider);
    if (tfliteService.isModelLoaded) {
      if (mounted) setState(() => _tfliteModelLoadError = null);
      return;
    }
    String? loadResult = await tfliteService.loadModel(
        modelAsset: "assets/yoloeats_v1.tflite", labelsAsset: "assets/labels.txt");
    if (mounted) {
      setState(() => _tfliteModelLoadError = loadResult);
      if (loadResult != null) {
        print("ScannerScreen: ERROR - TFLite model loading FAILED: $loadResult");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Failed to load detection model: $loadResult"),
            backgroundColor: Colors.red));
      } else {
        print("ScannerScreen: SUCCESS - TFLite model loaded.");
      }
    }
  }

  void _changeScannerMode(ScanMode newMode) {
    print("ScannerScreen: UI action to change mode to $newMode");
    final currentModeFromProvider = ref.read(scanModeProvider);
    if (newMode != currentModeFromProvider) {
      if (_processingInQueue || _isProcessingOcr || _isCameraInitializing) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Scanner busy, please wait."),
            duration: Duration(seconds: 1)));
        return;
      }
      ref.read(scanModeProvider.notifier).state = newMode;
    } else {
      print("ScannerScreen: Mode $newMode already selected. Re-triggering setup via _handleModeChange.");
      _handleModeChange(newMode, newMode);
    }
  }

  Future<void> _processCameraImageForTFLite(CameraImage image) async {
    if (!mounted ||
        ref.read(scanModeProvider) != ScanMode.objectDetection ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_cameraController!.value.isStreamingImages) {
      return;
    }
    if (_isProcessingOcr || _processingInQueue) return;

    final tfliteService = ref.read(tfliteServiceProvider);
    if (!tfliteService.isModelLoaded) {
      await _initModel();
      if (!tfliteService.isModelLoaded && mounted) return;
    }

    _processingInQueue = true;
    try {
      final recognitions = await tfliteService.runObjectDetection(image);
      if (mounted) {
        ref.read(yoloDetectionsProvider.notifier).state = recognitions ?? [];
      }
    } catch (e, s) {
      print("ScannerScreen: Error TFLite object detection: $e\n$s");
      if (mounted) ref.read(yoloDetectionsProvider.notifier).state = [];
    } finally {
      if (mounted) {
        _processingInQueue = false;
      }
    }
  }

  Future<void> _captureAndProcessOcr() async {
    if (ref.read(scanModeProvider) != ScanMode.ocr ||
        !_isCameraControllerInitialized ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isProcessingOcr ||
        !mounted) {
      print("ScannerScreen: OCR capture preconditions not met. Mode: ${ref.read(scanModeProvider)}, CamInit: $_isCameraControllerInitialized, OCRBusy: $_isProcessingOcr");
      return;
    }

    setStateIfMounted(() { _isProcessingOcr = true; });

    if (_cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
      _processingInQueue = false;
    }

    await Future.delayed(const Duration(milliseconds: 50));
    String? extractedTextResult;
    List<String> foundAllergensResult = [];
    String? errorResult;

    try {
      if (!_cameraController!.value.isTakingPicture) {
        final XFile imageFile = await _cameraController!.takePicture();
        print("ScannerScreen: Picture for OCR taken: ${imageFile.path}");

        // Use actual OCR service
        final ocrService = ref.read(ocrServiceProvider);
        extractedTextResult = await ocrService.extractTextFromImagePath(imageFile.path);
        print("ScannerScreen: OCR Extracted Text (first 100 chars): ${extractedTextResult?.substring(0, (extractedTextResult.length > 100) ? 100 : extractedTextResult.length)}...");

        // Get user profile for allergens
        final userProfile = ref.read(userProfileProvider).valueOrNull;

        if (userProfile != null && userProfile.allergens.isNotEmpty && extractedTextResult != null && extractedTextResult.isNotEmpty) {
          print("ScannerScreen: Comparing extracted text with user allergens: ${userProfile.allergens}");
          foundAllergensResult = _compareTextWithUserAllergens(extractedTextResult, userProfile.allergens);
        } else {
          if (userProfile == null) print("ScannerScreen: User profile not available for allergen comparison.");
          if (userProfile != null && userProfile.allergens.isEmpty) print("ScannerScreen: User has no listed allergens for comparison.");
          if (extractedTextResult == null || extractedTextResult.isEmpty) print("ScannerScreen: No text extracted for allergen comparison.");
        }
      } else {
        errorResult = "Camera busy (already taking picture).";
        print("ScannerScreen: OCR capture failed - camera busy.");
      }
    } on CameraException catch (e) {
      errorResult = 'Error capturing image for OCR: ${e.description}';
      print("ScannerScreen: CameraException during OCR capture: ${e.code} - ${e.description}");
    } catch (e) {
      errorResult = 'Error processing OCR: ${e.toString()}';
      print("ScannerScreen: Generic error during OCR processing or allergen comparison: $e");
    } finally {
      if (mounted) {
        setState(() { _isProcessingOcr = false; });
        _showOcrResultsBottomSheet(extractedTextResult, foundAllergensResult, errorMsg: errorResult);
      }
    }
  }

  // Updated allergen comparison logic
  List<String> _compareTextWithUserAllergens(String text, List<String> userAllergens) {
    final List<String> found = [];
    if (text.isEmpty || userAllergens.isEmpty) {
      print("ScannerScreen: Allergen comparison skipped - empty text or no user allergens.");
      return found;
    }

    final processedText = text.toLowerCase();

    final userAllergensLowerToOriginal = {
      for (var allergen in userAllergens) allergen.toLowerCase().trim(): allergen
    };

    for (final lowerCaseAllergenKey in userAllergensLowerToOriginal.keys) {
      if (lowerCaseAllergenKey.isEmpty) continue;
      if (processedText.contains(lowerCaseAllergenKey)) {
        found.add(userAllergensLowerToOriginal[lowerCaseAllergenKey]!);
      }
    }
    print("ScannerScreen: Found allergens in text: $found");
    return found;
  }


  void _showOcrResultsBottomSheet(String? extractedText, List<String> foundAllergens, {String? errorMsg}) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (BuildContext bc) {
        return FractionallySizedBox(
          heightFactor: 0.7,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Ingredient Scan Results", style: Theme.of(context).textTheme.headlineSmall),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())
                  ],
                ),
                const Divider(),
                if (errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text("Error: $errorMsg", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
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
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(extractedText.isNotEmpty ? extractedText : "(No text detected)"),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text("Potential User Allergens Found:", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: foundAllergens.isEmpty
                            ? [const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text("None of your listed allergens detected."))]
                            : foundAllergens.map((allergen) => Chip(
                          label: Text(allergen),
                          backgroundColor: Colors.red[100],
                          labelStyle: const TextStyle(color: Colors.redAccent),
                          side: BorderSide(color: Colors.red[200]!),
                        ))
                            .toList(),
                      ),
                    ),
                  ),
                ] else if (errorMsg == null) ...[
                  const Expanded(child: Center(child: Text("No text detected in the image."))),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleBarcodeDetection(BarcodeCapture capture) {
    if (!mounted || ref.read(scanModeProvider) != ScanMode.barcodeScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? detectedCode = barcodes.first.rawValue;
      if (detectedCode != null && detectedCode.isNotEmpty) {
        _mobileScannerController.stop();
        print("ScannerScreen: Barcode detected: $detectedCode");
        ref.read(detectedBarcodeProvider.notifier).state = detectedCode;
        final isMultiScanActive = ref.watch(multiScanModeProvider);
        if (isMultiScanActive) {
          final multiScanNotifier = ref.read(multiScanBarcodesProvider.notifier);
          if (!multiScanNotifier.state.contains(detectedCode)) {
            multiScanNotifier.state = [...multiScanNotifier.state, detectedCode];
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Barcode added: $detectedCode. Total: ${multiScanNotifier.state.length}"),
              duration: const Duration(milliseconds: 1500),
            ),
          );
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && ref.read(scanModeProvider) == ScanMode.barcodeScanning) {
              _mobileScannerController.start().catchError((e) => print("Error restarting mobile scanner: $e"));
            }
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ProductDetailScreen(productIdentifier: detectedCode)),
          ).then((_) {
            if (mounted && ref.read(scanModeProvider) == ScanMode.barcodeScanning) {
              _mobileScannerController.start().catchError((e) => print("Error restarting mobile scanner: $e"));
            }
          });
        }
      }
    }
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void dispose() {
    print("ScannerScreen disposing. Current mode: $_currentActiveScanMode");
    _scanModeListenerSubscription?.close();

    if (_currentActiveScanMode == ScanMode.objectDetection || _currentActiveScanMode == ScanMode.ocr) {
      Future.microtask(() async => await _disposeCameraController());
    }

    _mobileScannerController.dispose();
    print("MobileScannerController disposed in ScannerScreen dispose.");

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ScanMode currentMode = ref.watch(scanModeProvider);
    final isMultiScanActive = ref.watch(multiScanModeProvider);

    bool showOcrFab = currentMode == ScanMode.ocr &&
        _isCameraControllerInitialized &&
        _cameraController != null && _cameraController!.value.isInitialized &&
        !_isProcessingOcr;

    Widget cameraDisplayWidget;
    if (!_isPermissionGranted) {
      cameraDisplayWidget = Container(
          color: Colors.black,
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.no_photography, size: 60, color: Colors.white70),
                        const SizedBox(height: 16),
                        const Text('Camera Permission Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 10),
                        const Text('This app needs camera access. Please grant permission in settings.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(icon: const Icon(Icons.settings), label: const Text('Open App Settings'), onPressed: openAppSettings),
                        TextButton(onPressed: _checkAndRequestCameraPermissionIfNeeded, child: const Text("Retry Permission"))
                      ]))));
    } else if ((currentMode == ScanMode.objectDetection || currentMode == ScanMode.ocr)) {
      if (_isCameraInitializing && !_isCameraControllerInitialized) {
        cameraDisplayWidget = const Center(child: CircularProgressIndicator());
      } else if (_cameraInitializationError != null) {
        cameraDisplayWidget = Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Camera Error:\n${_cameraInitializationError!.code} - ${_cameraInitializationError!.description}', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 16))));
      } else if (_isCameraControllerInitialized && _cameraController != null && _cameraController!.value.isInitialized) {
        cameraDisplayWidget = Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: CameraPreview(_cameraController!)),
            if (currentMode == ScanMode.objectDetection && _tfliteModelLoadError == null)
              _buildObjectDetectionOverlay(),
            if (currentMode == ScanMode.objectDetection && _tfliteModelLoadError != null)
              Center(child: Container(padding: const EdgeInsets.all(8), color: Colors.black54, child: Text("Error loading detection model:\n$_tfliteModelLoadError", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)))),
          ],
        );
      } else {
        cameraDisplayWidget = const Center(child: CircularProgressIndicator());
      }
    } else if (currentMode == ScanMode.barcodeScanning) {
      cameraDisplayWidget = MobileScanner(
        controller: _mobileScannerController,
        onDetect: (BarcodeCapture capture) {
          _handleBarcodeDetection(capture);
        },
      );
    } else {
      String message = "Select a scan mode below.";
      if (_isCameraInitializing && currentMode != ScanMode.none) message = "Initializing camera...";
      cameraDisplayWidget = Container(
        color: Colors.black54,
        child: Center(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center,)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Scan: ${currentMode.name}${isMultiScanActive && currentMode == ScanMode.barcodeScanning ? ' (Multi)' : ''}"),
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        actions: [
          if (currentMode == ScanMode.barcodeScanning)
            TextButton.icon(
              icon: Icon(isMultiScanActive ? Icons.done_all : Icons.library_add_check_outlined , color: Colors.white),
              label: Text(isMultiScanActive ? "Finish (${ref.watch(multiScanBarcodesProvider).length})" : "Multi-Scan", style: const TextStyle(color: Colors.white)),
              onPressed: () {
                final multiScanNotifier = ref.read(multiScanModeProvider.notifier);
                final multiScanBarcodesNotifier = ref.read(multiScanBarcodesProvider.notifier);
                if (isMultiScanActive) {
                  final barcodes = multiScanBarcodesNotifier.state;
                  if (barcodes.isNotEmpty) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => MultiScanResultsScreen(barcodes: barcodes)))
                        .then((_) => multiScanBarcodesNotifier.state = []);
                  }
                  multiScanNotifier.state = false;
                  _mobileScannerController.stop();
                } else {
                  multiScanNotifier.state = true;
                  multiScanBarcodesNotifier.state = [];
                  if (mounted && ref.read(scanModeProvider) == ScanMode.barcodeScanning) {
                    _mobileScannerController.start().catchError((e)=>print("Error starting mobile scanner for multi-scan: $e"));
                  }
                }
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
        Positioned.fill(child: cameraDisplayWidget),
        Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.black.withOpacity(0.7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<ScanMode>(
                segments: const <ButtonSegment<ScanMode>>[
                  ButtonSegment<ScanMode>(value: ScanMode.objectDetection, label: Text('Product'), icon: Icon(Icons.camera_alt_outlined)),
                  ButtonSegment<ScanMode>(value: ScanMode.barcodeScanning, label: Text('Barcode'), icon: Icon(Icons.qr_code_scanner)),
                  ButtonSegment<ScanMode>(value: ScanMode.ocr, label: Text('Ingredients'), icon: Icon(Icons.document_scanner_outlined)),
                ],
                selected: <ScanMode>{currentMode},
                onSelectionChanged: (Set<ScanMode> newSelection) => _changeScannerMode(newSelection.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: Colors.grey[850]?.withOpacity(0.9),
                  foregroundColor: Colors.white70,
                  selectedBackgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  selectedForegroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  textStyle: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ]),
          ),
        )),
      ]),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: showOcrFab
          ? FloatingActionButton.large(
        heroTag: 'ocr_capture_button',
        onPressed: _captureAndProcessOcr,
        tooltip: 'Scan Ingredients Text',
        child: _isProcessingOcr ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.camera_enhance_sharp),
      )
          : null,
    );
  }

  Widget _buildObjectDetectionOverlay() {
    final currentMode = ref.watch(scanModeProvider);
    if (currentMode != ScanMode.objectDetection ||
        !_isCameraControllerInitialized ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    if (_tfliteModelLoadError != null) return const SizedBox.shrink();

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