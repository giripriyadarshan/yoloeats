import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img_lib;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math' as math;

class Recognition {
  final int id;
  final String label;
  final double score;
  final Rect location;
  Recognition(this.id, this.label, this.score, this.location);
  @override String toString() => 'Recognition(id: $id, label: $label, score: ${score.toStringAsFixed(3)}, location: $location)';
}

class CandidateDetection {
  final List<double> rawBbox;
  final int classId;
  final double score;
  CandidateDetection({required this.rawBbox, required this.classId, required this.score});
  List<double> getAbsoluteBbox(double modelInputWidth, double modelInputHeight) {
    final double xC = rawBbox[0] * modelInputWidth; final double yC = rawBbox[1] * modelInputHeight;
    final double w = rawBbox[2] * modelInputWidth; final double h = rawBbox[3] * modelInputHeight;
    final double xMin = (xC - w / 2); final double yMin = (yC - h / 2);
    final double xMax = (xC + w / 2); final double yMax = (yC + h / 2);
    return [
      xMin.clamp(0.0, modelInputWidth -1), yMin.clamp(0.0, modelInputHeight -1),
      xMax.clamp(0.0, modelInputWidth -1), yMax.clamp(0.0, modelInputHeight-1)
    ];
  }
  @override String toString() => 'CandidateDetection(classId: $classId, score: ${score.toStringAsFixed(3)}, rawBbox: [${rawBbox.map((e) => e.toStringAsFixed(3)).join(", ")}])';
}

class TFLiteService {
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isModelLoaded = false;
  List<int>? _inputShape;
  TensorType? _inputType;

  static const double objectnessThreshold = 0.9;
  static const double classConfidenceThreshold = 0.9;
  static const double iouThreshold = 0.05;

  bool get isModelLoaded => _isModelLoaded;

  Future<String?> loadModel({
    String modelAsset = "assets/yoloeats_v1.tflite",
    String labelsAsset = "assets/labels.txt",
    int numThreads = 1,
    bool useGpuDelegate = false,
  }) async {
    if (_isModelLoaded && _interpreter != null) return null;
    _isModelLoaded = false;
    try {
      final labelsData = await rootBundle.loadString(labelsAsset);
      _labels = labelsData.split('\n').map((label) => label.trim()).where((label) => label.isNotEmpty).toList();
      if (_labels == null || _labels!.isEmpty) return "TFLiteService: Failed to load or parse labels from $labelsAsset.";

      final options = InterpreterOptions()..threads = numThreads;
      _interpreter = await Interpreter.fromAsset(modelAsset, options: options);
      _interpreter!.allocateTensors();
      final inputTensor = _interpreter!.getInputTensor(0);
      _inputShape = List<int>.from(inputTensor.shape);
      _inputType = inputTensor.type;
      final outputTensor = _interpreter!.getOutputTensor(0);
      print("TFLiteService: Model loaded. Input: $_inputShape $_inputType, Output: ${outputTensor.shape} ${outputTensor.type}, Labels loaded: ${_labels!.length}");
      _isModelLoaded = true;
      return null;
    } catch (e, s) {
      print("TFLiteService: EXCEPTION during loadModel: $e\n$s");
      _isModelLoaded = false; _interpreter?.close(); _interpreter = null; _labels = null;
      return "TFLiteService: EXCEPTION - $e";
    }
  }

  static Future<img_lib.Image?> convertCameraImageToRgb(CameraImage cameraImage) async {
    if (cameraImage.format.group != ImageFormatGroup.yuv420) return null;
    final int width = cameraImage.width; final int height = cameraImage.height;
    final Plane yPlane = cameraImage.planes[0]; final Plane uPlane = cameraImage.planes[1]; final Plane vPlane = cameraImage.planes[2];
    final Uint8List yBytes = yPlane.bytes; final Uint8List uBytes = uPlane.bytes; final Uint8List vBytes = vPlane.bytes;
    final int yRowStride = yPlane.bytesPerRow; final int uvRowStride = uPlane.bytesPerRow;
    final int? uBytesPerPixel = uPlane.bytesPerPixel; final int? vBytesPerPixel = vPlane.bytesPerPixel;
    final image = img_lib.Image(width: width, height: height);
    int yp = 0;
    for (int yi = 0; yi < height; yi++) {
      int uvx = 0; final int uvy = yi ~/ 2;
      for (int xi = 0; xi < width; xi++) {
        final yValue = yBytes[yp + xi];
        if (xi % 2 == 0) uvx = xi ~/2;
        final int uIndex = uvy * uvRowStride + uvx * (uBytesPerPixel ?? 1);
        final int vIndex = uvy * vPlane.bytesPerRow + uvx * (vBytesPerPixel ?? 1);
        if (uIndex >= uBytes.length || vIndex >= vBytes.length) { image.setPixelRgb(xi, yi, 128, 128, 128); continue; }
        final uValueOriginal = uBytes[uIndex]; final vValueOriginal = vBytes[vIndex];
        final int uVal = uValueOriginal - 128; final int vVal = vValueOriginal - 128;
        int r = (yValue + 1.402 * vVal).round();
        int g = (yValue - 0.344136 * uVal - 0.714136 * vVal).round();
        int b = (yValue + 1.772 * uVal).round();
        image.setPixelRgb(xi, yi, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
      }
      yp += yRowStride;
    }
    return image;
  }

  double _calculateIoU(List<double> boxA, List<double> boxB) { /* ... same ... */
    final double xA_min = boxA[0]; final double yA_min = boxA[1]; final double xA_max = boxA[2]; final double yA_max = boxA[3];
    final double xB_min = boxB[0]; final double yB_min = boxB[1]; final double xB_max = boxB[2]; final double yB_max = boxB[3];
    final double xOverlap = math.max(0, math.min(xA_max, xB_max) - math.max(xA_min, xB_min));
    final double yOverlap = math.max(0, math.min(yA_max, yB_max) - math.max(yA_min, yB_min));
    final double intersectionArea = xOverlap * yOverlap;
    if (intersectionArea <= 0) return 0.0;
    final double areaA = (xA_max - xA_min) * (yA_max - yA_min);
    final double areaB = (xB_max - xB_min) * (yB_max - yB_min);
    if (areaA <= 0 || areaB <= 0) return 0.0;
    final double unionArea = areaA + areaB - intersectionArea;
    if (unionArea <= 0) return 0.0;
    return intersectionArea / unionArea;
  }

  Future<List<Recognition>?> runObjectDetection(CameraImage cameraImage) async {
    if (!_isModelLoaded || _interpreter == null || _inputShape == null || _inputType == null || _labels == null) {
      return null;
    }

    final int modelHeight = _inputShape![1];
    final int modelWidth = _inputShape![2];

    final img_lib.Image? rgbImage = await convertCameraImageToRgb(cameraImage);
    if (rgbImage == null) return null;

    final img_lib.Image resizedImage = img_lib.copyResize(
      rgbImage, width: modelWidth, height: modelHeight, interpolation: img_lib.Interpolation.linear,
    );

    ByteBuffer inputBuffer;
    if (_inputType == TensorType.float32) {
      final imageAsFloat32List = Float32List(1 * modelHeight * modelWidth * 3);
      int bufferIndex = 0;
      for (int y = 0; y < modelHeight; y++) {
        for (int x = 0; x < modelWidth; x++) {
          final pixel = resizedImage.getPixel(x, y);
          imageAsFloat32List[bufferIndex++] = pixel.rNormalized.toDouble();
          imageAsFloat32List[bufferIndex++] = pixel.gNormalized.toDouble();
          imageAsFloat32List[bufferIndex++] = pixel.bNormalized.toDouble();
        }
      }
      inputBuffer = imageAsFloat32List.buffer;
    } else { return []; }

    final outputTensorInfo = _interpreter!.getOutputTensor(0);
    final outputShape = List<int>.from(outputTensorInfo.shape);
    final int outputSize = outputShape.reduce((a, b) => a * b);
    final outputFloatTensor = Float32List(outputSize);
    final Map<int, Object> outputs = {0: outputFloatTensor.buffer};

    try { _interpreter!.runForMultipleInputs([inputBuffer], outputs); }
    catch (e, s) { print("TFLiteService: EXCEPTION during inference: $e\n$s"); return null; }

    final Float32List results = Float32List.view(outputs[0] as ByteBuffer);

    final int numPredictions = outputShape[2]; // 8400
    final int numFeaturesPerPrediction = outputShape[1]; // 21

    print("TFLiteService: Loaded labels count: ${_labels!.length}"); // Should be 17
    final int numClassScoresOutputByModel = numFeaturesPerPrediction - 5; // Explicitly 16
    print("TFLiteService: Expecting $numClassScoresOutputByModel class scores from model output.");

    List<CandidateDetection> candidateDetections = [];

    for (int i = 0; i < numPredictions; i++) {
      final int predictionStartOffset = i * numFeaturesPerPrediction;
      if (predictionStartOffset + numFeaturesPerPrediction > results.length) break;

      final double xCenter = results[predictionStartOffset + 0];
      final double yCenter = results[predictionStartOffset + 1];
      final double widthBbox = results[predictionStartOffset + 2];
      final double heightBbox = results[predictionStartOffset + 3];
      final double objectnessScore = results[predictionStartOffset + 4];

      if (objectnessScore > objectnessThreshold) {
        final int numClassesToIterateForScores = numClassScoresOutputByModel;
        List<double> classScores = [];
        for (int j = 0; j < numClassesToIterateForScores; j++) {
          classScores.add(results[predictionStartOffset + 5 + j]);
        }

        double maxClassScore = 0.0;
        int bestClassId = -1;
        if (classScores.isNotEmpty) {
          for(int k=0; k < classScores.length; k++) {
            if (classScores[k] > maxClassScore) {
              maxClassScore = classScores[k];
              bestClassId = k;
            }
          }
        }

        if (maxClassScore > classConfidenceThreshold) {
          final List<double> rawBbox = [xCenter, yCenter, widthBbox, heightBbox];
          final double combinedScore = objectnessScore * maxClassScore;
          candidateDetections.add(CandidateDetection(
            rawBbox: rawBbox, classId: bestClassId, score: combinedScore,
          ));

          if (i < 5 || (objectnessScore > 0.5 && candidateDetections.length <= 10)) {
            print("TFLiteService: Filtered Candidate (Pre-NMS) #$i:");
            print("  Raw BBox (norm): [${xCenter.toStringAsFixed(3)}, ${yCenter.toStringAsFixed(3)}, ${widthBbox.toStringAsFixed(3)}, ${heightBbox.toStringAsFixed(3)}]");
            print("  Objectness: ${objectnessScore.toStringAsFixed(3)}");
            // Your updated log for class ID and score
            print("TFLiteService: Prediction #$i: Raw Best Class ID (0-${numClassScoresOutputByModel-1}): $bestClassId, Max Class Score: ${maxClassScore.toStringAsFixed(3)}");
            if (bestClassId != -1 && bestClassId < _labels!.length) {
              print("  Class Label: ${_labels![bestClassId]}");
            } else if (bestClassId != -1) {
              print("  Warning: bestClassId $bestClassId is out of bounds for _labels (length ${_labels!.length})");
            }
          }
        }
      }
    }


    List<CandidateDetection> finalDetectionsAfterNMS = [];
    Map<int, List<CandidateDetection>> detectionsByClass = {};
    for (final candidate in candidateDetections) {
      detectionsByClass.putIfAbsent(candidate.classId, () => []).add(candidate);
    }

    detectionsByClass.forEach((classId, classCandidates) {
      classCandidates.sort((a, b) => b.score.compareTo(a.score));
      List<bool> isSuppressed = List.filled(classCandidates.length, false);
      for (int i = 0; i < classCandidates.length; i++) {
        if (isSuppressed[i]) continue;
        finalDetectionsAfterNMS.add(classCandidates[i]);
        for (int j = i + 1; j < classCandidates.length; j++) {
          if (isSuppressed[j]) continue;
          final List<double> boxI = classCandidates[i].getAbsoluteBbox(modelWidth.toDouble(), modelHeight.toDouble());
          final List<double> boxJ = classCandidates[j].getAbsoluteBbox(modelWidth.toDouble(), modelHeight.toDouble());
          final double iou = _calculateIoU(boxI, boxJ);
          if (iou > iouThreshold) {
            isSuppressed[j] = true;
          }
        }
      }
    });

    print("TFLiteService: Total detections after NMS (IoU: $iouThreshold): ${finalDetectionsAfterNMS.length}");

    List<Recognition> recognitions = [];
    double originalImageWidth = cameraImage.width.toDouble();
    double originalImageHeight = cameraImage.height.toDouble();

    for (var det in finalDetectionsAfterNMS) {
      if (det.classId >= 0 && det.classId < _labels!.length) {
        final List<double> modelScaleBox = det.getAbsoluteBbox(modelWidth.toDouble(), modelHeight.toDouble());
        final double scaleXToOriginal = originalImageWidth / modelWidth.toDouble();
        final double scaleYToOriginal = originalImageHeight / modelHeight.toDouble();
        double screenLeft = modelScaleBox[0] * scaleXToOriginal;
        double screenTop = modelScaleBox[1] * scaleYToOriginal;
        double screenRight = modelScaleBox[2] * scaleXToOriginal;
        double screenBottom = modelScaleBox[3] * scaleYToOriginal;
        screenLeft = screenLeft.clamp(0.0, originalImageWidth -1);
        screenTop = screenTop.clamp(0.0, originalImageHeight -1);
        screenRight = screenRight.clamp(0.0, originalImageWidth -1);
        screenBottom = screenBottom.clamp(0.0, originalImageHeight-1);
        if (screenRight > screenLeft && screenBottom > screenTop) {
          recognitions.add(Recognition(
              det.classId, _labels![det.classId], det.score,
              Rect.fromLTRB(screenLeft, screenTop, screenRight, screenBottom)
          ));
        }
      } else {
        print("TFLiteService: Warning - Post-NMS classId ${det.classId} is out of bounds for labels list (length ${_labels!.length}). Skipping this detection.");
      }
    }

    if (recognitions.isNotEmpty) {
      print("TFLiteService: Returning ${recognitions.length} final recognitions.");
    }
    return recognitions;
  }

  void closeModel() {
    if (_interpreter != null) {
      _interpreter!.close(); _interpreter = null; _isModelLoaded = false;
      print("TFLiteService: TFLite model closed.");
    }
  }
}