import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';


class Recognition {
  final int id;
  final String label;
  final double score;
  final Rect location;
  Recognition(this.id, this.label, this.score, this.location);
  @override String toString() => 'Recognition(id: $id, label: $label, score: $score, location: $location)';
}


class TFLiteService {
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isModelLoaded = false;

  late List<int> _inputShape;
  late TensorType _inputType;
  late TensorType _outputType;


  bool get isModelLoaded => _isModelLoaded;

  Future<void> loadModel({
    String modelAsset = "assets/yolov8n_float16.tflite",
    String labelsAsset = "assets/labels.txt",
    int numThreads = 1,
  }) async {
    if (_isModelLoaded) return;
    try {
      print("Loading TFLite model and labels...");
      final labelsData = await rootBundle.loadString(labelsAsset);
      _labels = labelsData.split('\n').map((label) => label.trim()).where((label) => label.isNotEmpty).toList();
      print("Labels loaded: ${_labels?.length ?? 0}");

      final options = InterpreterOptions()..threads = numThreads;
      _interpreter = await Interpreter.fromAsset(modelAsset, options: options);
      _interpreter!.allocateTensors();

      final inputTensor = _interpreter!.getInputTensor(0);
      _inputShape = List<int>.from(inputTensor.shape);
      _inputType = inputTensor.type;

      final outputTensor = _interpreter!.getOutputTensor(0);
      _outputType = outputTensor.type;

      print("Model loaded successfully. Input shape: $_inputShape, Input Type: $_inputType, Output Type: $_outputType");
      _isModelLoaded = true;
    } catch (e) {
      print("Error loading TFLite model: $e");
      _isModelLoaded = false;
      _interpreter = null;
      _labels = null;
      rethrow;
    }
  }

  Future<List<Recognition>?> runObjectDetection(CameraImage cameraImage) async {
    if (!_isModelLoaded || _interpreter == null) {
      print("Model not loaded, cannot run inference.");
      return null;
    }

    final interpreter = _interpreter!;
    final labels = _labels ?? [];

    // --- TODO: Preprocessing CameraImage (Placeholder) ---
    // Placeholder Input Buffer (MUST BE REPLACED with actual preprocessing)
    if (_inputType != TensorType.uint8 && _inputType != TensorType.float32) {
      print("ERROR: This placeholder only supports uint8 or float32 input type!");
      return null;
    }

    ByteBuffer inputBuffer;
    if (_inputType == TensorType.uint8) {
      final inputBytes = _inputShape.reduce((a,b) => a * b);
      inputBuffer = Uint8List(inputBytes).buffer;
      print("Warning: Using dummy UINT8 input buffer.");
    } else { // Assume Float32
      final inputFloats = _inputShape.reduce((a,b) => a * b);
      inputBuffer = Float32List(inputFloats).buffer;
      print("Warning: Using dummy Float32 input buffer.");
    }

    if (_outputType != TensorType.float32) {
      print("Error: Expected Float32 output type from model info, got $_outputType");
      return null;
    }
    final outputTensor = interpreter.getOutputTensor(0);
    final outputShape = List<int>.from(outputTensor.shape);
    final outputBuffer = List.filled(outputShape.reduce((a, b) => a * b), 0.0)
        .reshape(outputShape);
    Map<int, Object> outputs = {0: outputBuffer};
    List<Object> inputs = [inputBuffer];

    try {
      interpreter.runForMultipleInputs(inputs, outputs);
    } catch (e) {
      print("Error running model inference: $e");
      return null;
    }

    // --- TODO: Postprocessing Output Buffer ---
    print("WARNING: Output post-processing (YOLO decoding, NMS) not implemented.");
    List<Recognition> recognitions = [];


    return recognitions;
  }


  void closeModel() {
    if (_interpreter != null) {
      _interpreter!.close();
      _interpreter = null;
      _labels = null;
      _isModelLoaded = false;
      print("TFLite model closed.");
    }
  }
}