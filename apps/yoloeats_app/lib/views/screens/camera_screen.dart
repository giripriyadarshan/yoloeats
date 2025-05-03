import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yoloeats_app/providers/ml_providers.dart';
import 'package:yoloeats_app/providers/barcode_processor_provider.dart';
import 'package:yoloeats_app/providers/camera_providers.dart';
import '../painters/detection_painter.dart';


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
    formats: [BarcodeFormat.ean13, BarcodeFormat.code128, BarcodeFormat.qrCode],
    returnImage: false,
  );

  bool _isProcessingBarcode = false;
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initModel();
      _checkPermissionAndInitializeCamera();
    });
  }

  Future<void> _initModel() async {
    try {
      await ref.read(tfliteServiceProvider).loadModel();
    } catch(e) { print("Error initializing model: $e"); }
  }


  @override
  Future<void> dispose() async {
    if (_cameraController != null) {
      try { await _cameraController!.stopImageStream(); } catch (e) { print("Error stopping stream: $e");}
    }
    _cameraController?.dispose();
    _barcodeController.dispose();
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
        setState(() { /* reset flags */
          _isCameraInitialized = false; _cameraController = null; _isProcessingBarcode = false; _isDetecting = false;
          ref.read(yoloDetectionsProvider.notifier).state = [];
          ref.read(detectedBarcodeProvider.notifier).state = null;
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (_cameraController != null || !_isCameraPermissionGranted) return;
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) throw CameraException("NO_CAMERAS", "No cameras found.");
      CameraDescription selectedCamera = _cameras!.firstWhere( (cam) => cam.lensDirection == CameraLensDirection.back, orElse: () => _cameras!.first);
      _cameraController = CameraController(selectedCamera, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await _cameraController!.initialize();

      if (mounted) {
        await _cameraController!.startImageStream(_processCameraImage);
        setState(() { _isCameraInitialized = true; _cameraInitializationError = null; });
      }
    } on CameraException catch (e) {
      if (mounted) setState(() => _cameraInitializationError = e);
    } catch (e) {
      if (mounted) setState(() => _cameraInitializationError = CameraException("INIT_ERROR", e.toString()));
    } finally {
      if (mounted && _cameraInitializationError != null) setState(() => _isCameraInitialized = false);
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!_isCameraInitialized || _isDetecting || _isProcessingBarcode) return;

    final tfliteService = ref.read(tfliteServiceProvider);
    if (!tfliteService.isModelLoaded) return;

    setState(() { _isDetecting = true; });

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
        setState(() { _isDetecting = false; });
      }
    }
  }

  void _handleBarcodeDetection(BarcodeCapture capture) {
    if (_isProcessingBarcode) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? barcodeValue = barcodes.first.rawValue;

      if (barcodeValue != null) {
        setState(() { _isProcessingBarcode = true; });

        ref.read(detectedBarcodeProvider.notifier).state = barcodeValue;
        ref.read(yoloDetectionsProvider.notifier).state = [];

        print('Barcode detected: $barcodeValue');
        // _cameraController?.stopImageStream(); // Optional pause

        ref.read(barcodeProcessorProvider).process(barcodeValue);
        print("Triggered processing for barcode: $barcodeValue");

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            print("Resuming detection after barcode...");
            setState(() { _isProcessingBarcode = false; });
            ref.read(detectedBarcodeProvider.notifier).state = null;

          }
        });
      }
    }
  }

  Widget _buildBody() {
    if (_cameraPermissionStatus == null) return const Center(child: CircularProgressIndicator());
    if (!_isCameraPermissionGranted) { }
    if (_cameraInitializationError != null) return Center(child: Text('Failed camera init: ${_cameraInitializationError!.description}'));
    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final previewSize = _cameraController?.value.previewSize ?? Size.zero;
    final screenSize = MediaQuery.of(context).size;

    // TODO: Determine correct rotation for painter coordinate scaling
    // This often involves combining device orientation and camera sensor orientation.
    // For simplicity, we pass 0 rotation to the painter for now.
    // final imageRotation = InputImageRotation.rotation0deg; // Placeholder

    final detections = ref.watch(yoloDetectionsProvider);
    final barcode = ref.watch(detectedBarcodeProvider);


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

        if (previewSize != Size.zero)
          CustomPaint(
            painter: DetectionPainter(detections, previewSize),
            size: previewSize,
          ),

        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(5)),
            child: Text(
              'Barcode: ${barcode ?? "None"}',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar( ),
      body: _buildBody(),
    );
  }
}