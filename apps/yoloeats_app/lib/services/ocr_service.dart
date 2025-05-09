import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';

abstract class OcrService {
  /// Extracts text from an image file located at the given path.
  Future<String> extractTextFromImagePath(String imagePath);
}

class MlKitOcrService implements OcrService {
  @override
  Future<String> extractTextFromImagePath(String imagePath) async {
    if (!await File(imagePath).exists()) {
      print("OCR Service Error: Image file not found at $imagePath");
      throw Exception("Image file not found for OCR");
    }

    print("OCR Service: Processing image $imagePath");
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    String extractedText = "";

    try {
      final inputImage = InputImage.fromFilePath(imagePath);

      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      extractedText = recognizedText.text;
      print("OCR Service: Text extracted successfully (${extractedText.length} chars).");

    } catch (e) {
      print("OCR Service Error: Failed to process image with ML Kit: $e");
      rethrow;
    } finally {
      try {
        await textRecognizer.close();
        print("OCR Service: TextRecognizer closed.");
      } catch(e) {
        print("OCR Service Error: Failed to close TextRecognizer: $e");
      }
    }

    return extractedText;
  }
}