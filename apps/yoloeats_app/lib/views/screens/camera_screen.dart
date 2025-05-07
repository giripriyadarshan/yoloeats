import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ml_providers.dart';
import '../../providers/camera_providers.dart';

import '../painters/detection_painter.dart';
import 'product_detail_screen.dart';
import 'multi_scan_results_screen.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  PermissionStatus? _cameraPermissionStatus;
  List<CameraDescription>? _cameras;
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCameraPermissionGranted = false;
  CameraException? _cameraInitializationError;

  final MobileScannerController _barcodeController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: [BarcodeFormat.ean13, BarcodeFormat.code128, BarcodeFormat.qrCode, BarcodeFormat.upcA, BarcodeFormat.upcE],
    returnImage: false,
  );

  bool _isProcessingSingleBarcode = false;
  bool _isDetectingObjects = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initModel();
      _checkPermissionAndInitializeCamera();
    });
  }

  @override
  Future<void> dispose() async {
    print("Disposing CameraScreen State");
    if (_cameraController != null) {
      try {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
          print("Camera stream stopped.");
        }
      } catch (e) { print("Error stopping stream during dispose: $e");}
      _cameraController!.dispose();
      print("CameraController disposed.");
    }
    _barcodeController.dispose();
    print("MobileScannerController disposed.");
    super.dispose();
  }


  Future<void> _initModel() async {
    try {
      print("Initializing TFLite model...");
      await ref.read(tfliteServiceProvider).loadModel();
      print("TFLite model initialized.");
    } catch(e) { print("Error initializing model: $e"); }
  }


  Future<void> _checkPermissionAndInitializeCamera() async {
    print("Checking camera permission...");
    final status = await Permission.camera.request();
    print("Camera permission status: $status");
    if (mounted) {
      setState(() {
        _cameraPermissionStatus = status;
        _isCameraPermissionGranted = status.isGranted || status.isLimited;
      });
      if (_isCameraPermissionGranted) {
        print("Camera permission granted. Initializing camera...");
        await _initializeCamera();
      } else {
        print("Camera permission denied.");
        setState(() {
          _isCameraInitialized = false; _cameraController = null; _isProcessingSingleBarcode = false; _isDetectingObjects = false;
          ref.read(yoloDetectionsProvider.notifier).state = [];
          ref.read(detectedBarcodeProvider.notifier).state = null;
          ref.read(multiScanBarcodesProvider.notifier).state = [];
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (_cameraController != null || !_isCameraPermissionGranted) return;
    print("Finding available cameras...");
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) throw CameraException("NO_CAMERAS", "No cameras found.");
      print("Cameras found: ${_cameras!.length}");
      CameraDescription selectedCamera = _cameras!.firstWhere( (cam) => cam.lensDirection == CameraLensDirection.back, orElse: () => _cameras!.first);
      print("Selected camera: ${selectedCamera.name}");
      _cameraController = CameraController(selectedCamera, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      print("Initializing CameraController...");
      await _cameraController!.initialize();
      print("CameraController initialized.");

      if (mounted) {
        print("Starting camera image stream...");
        await _cameraController!.startImageStream(_processCameraImage);
        print("Camera stream started.");
        setState(() { _isCameraInitialized = true; _cameraInitializationError = null; });
      }
    } on CameraException catch (e) {
      print("CameraException during initialization: ${e.code} - ${e.description}");
      if (mounted) setState(() => _cameraInitializationError = e);
    } catch (e) {
      print("Generic error during camera initialization: $e");
      if (mounted) setState(() => _cameraInitializationError = CameraException("INIT_ERROR", e.toString()));
    } finally {
      if (mounted && _cameraInitializationError != null) setState(() => _isCameraInitialized = false);
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!_isCameraInitialized || _isDetectingObjects || _isProcessingSingleBarcode || ref.read(multiScanModeProvider)) {
      return;
    }

    final tfliteService = ref.read(tfliteServiceProvider);
    if (!tfliteService.isModelLoaded) return;

    setState(() { _isDetectingObjects = true; });

    try {
      final recognitions = await tfliteService.runObjectDetection(image);
      if (mounted) {
        ref.read(yoloDetectionsProvider.notifier).state = recognitions ?? [];
      }
    } catch (e) {
      print("Error running TFLite detection: $e");
      if (mounted) {
        ref.read(yoloDetectionsProvider.notifier).state = [];
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() { _isDetectingObjects = false; });
      }
    }
  }

  void _handleBarcodeDetection(BarcodeCapture capture) {
    final isMultiScanMode = ref.read(multiScanModeProvider);

    if (_isProcessingSingleBarcode || capture.barcodes.isEmpty) return;

    final String? barcodeValue = capture.barcodes.first.rawValue;
    if (barcodeValue == null || barcodeValue.isEmpty) return;

    if (isMultiScanMode) {
      final currentBarcodes = ref.read(multiScanBarcodesProvider);
      if (!currentBarcodes.contains(barcodeValue)) {
        print("Multi-Scan: Adding barcode $barcodeValue");
        HapticFeedback.mediumImpact();
        ref.read(multiScanBarcodesProvider.notifier).update((state) => [...state, barcodeValue]);
      } else {
        print("Multi-Scan: Barcode $barcodeValue already scanned.");
      }
    }
    else {
      if (!_isProcessingSingleBarcode) {
        print('Single scan detected: $barcodeValue');
        setState(() { _isProcessingSingleBarcode = true; });
        ref.read(detectedBarcodeProvider.notifier).state = barcodeValue;
        ref.read(yoloDetectionsProvider.notifier).state = [];

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(productIdentifier: barcodeValue),
          ),
        ).then((_) {
          print("Returned from ProductDetailScreen, resetting single scan flag.");
          if(mounted) {
            setState(() { _isProcessingSingleBarcode = false; });
            ref.read(detectedBarcodeProvider.notifier).state = null;
          }
        });
      }
    }
  }

  void _viewMultiScanResults() {
    final barcodes = ref.read(multiScanBarcodesProvider);
    if (barcodes.isEmpty) return;

    print("Navigating to multi-scan results with ${barcodes.length} items.");
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultiScanResultsScreen(barcodes: barcodes),
      ),
    ).then((_) {
      print("Returned from MultiScanResultsScreen, clearing scanned barcodes.");
      if (mounted) {
        ref.read(multiScanBarcodesProvider.notifier).state = [];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMultiScan = ref.watch(multiScanModeProvider);
    final scannedBarcodes = ref.watch(multiScanBarcodesProvider);
    final scannedCount = scannedBarcodes.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Product'),
        actions: [
          IconButton(
            icon: Icon(isMultiScan ? Icons.filter_center_focus : Icons.checklist_rtl_outlined),
            tooltip: isMultiScan ? "Switch to Single Scan" : "Switch to Multi-Scan",
            color: isMultiScan ? Theme.of(context).primaryColor : null,
            onPressed: () {
              final newValue = !isMultiScan;
              print("Toggling multi-scan mode to: $newValue");
              ref.read(multiScanModeProvider.notifier).state = newValue;
              if (!newValue) {
                print("Clearing multi-scan list as mode is switched off.");
                ref.read(multiScanBarcodesProvider.notifier).state = [];
              }
              ref.read(detectedBarcodeProvider.notifier).state = null;
              setState(() { _isProcessingSingleBarcode = false; });
            },
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          _buildCameraBody(),

          if (isMultiScan) ...[
            Positioned(
              top: 10,
              right: 10,
              child: Chip(
                avatar: CircleAvatar(child: Text('$scannedCount')),
                label: const Text('Items'),
                backgroundColor: Colors.black54,
                labelStyle: const TextStyle(color: Colors.white),
              ),
            ),
            if (scannedCount > 0)
              Positioned(
                bottom: 90,
                left: 20,
                right: 20,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.playlist_add_check),
                  label: Text('View $scannedCount Scanned Item(s)'),
                  onPressed: _viewMultiScanResults,
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraBody() {
    if (_cameraPermissionStatus == null) {
      print("Building Camera Body: Permission loading...");
      return const Center(child: CircularProgressIndicator());
    }
    if (!_isCameraPermissionGranted) {
      print("Building Camera Body: Permission denied UI.");
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Camera permission denied.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Allow camera access to scan products.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: openAppSettings,
                child: const Text('Open App Settings'),
              ),
            ],
          ),
        ),
      );
    }
    if (_cameraInitializationError != null) {
      print("Building Camera Body: Camera init error UI.");
      return Center(child: Text('Failed to initialize camera:\n${_cameraInitializationError!.description}', textAlign: TextAlign.center));
    }
    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      print("Building Camera Body: Camera initializing...");
      return const Center(child: CircularProgressIndicator());
    }

    print("Building Camera Body: Showing camera preview.");
    final previewSize = _cameraController!.value.previewSize ?? Size.zero;

    final detections = ref.watch(yoloDetectionsProvider);
    final barcode = ref.watch(detectedBarcodeProvider);
    final isMultiScan = ref.watch(multiScanModeProvider);


    return Stack(
      alignment: Alignment.center,
      children: [
        if (previewSize != Size.zero)
          AspectRatio(
            aspectRatio: _cameraController!.value.aspectRatio,
            child: CameraPreview(_cameraController!),
          ),

        MobileScanner(
          controller: _barcodeController,
          onDetect: _handleBarcodeDetection,
        ),

        if (previewSize != Size.zero && !isMultiScan)
          CustomPaint(
            painter: DetectionPainter(detections, previewSize),
            size: previewSize,
          ),

        if (barcode != null && !isMultiScan)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(5)),
              child: Text(
                'Detected: $barcode',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

}