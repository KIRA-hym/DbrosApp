import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';

class AppImagePickerResult {
  final File file;
  final DateTime creationDate;

  AppImagePickerResult({required this.file, required this.creationDate});
}

class AppImagePicker {
  AppImagePicker._();

  static final ImagePicker _picker = ImagePicker();

  /// 갤러리에서 단건 이미지를 선택합니다.
  static Future<AppImagePickerResult?> pickSingleGalleryImage(BuildContext context) async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    
    final ioFile = File(file.path);
    final creationDate = await _getCreationDate(ioFile);
    
    return AppImagePickerResult(
      file: ioFile,
      creationDate: creationDate,
    );
  }

  /// 갤러리에서 다건 이미지를 선택합니다.
  static Future<List<AppImagePickerResult>> pickMultipleGalleryImages(
    BuildContext context, {
    int maxAssets = 30, // image_picker에서는 maxAssets 제한을 지원하지 않으므로, 선택 후 자릅니다.
  }) async {
    final List<XFile> files = await _picker.pickMultiImage();
    if (files.isEmpty) return [];
    
    final selectedFiles = files.take(maxAssets).toList();
    final results = <AppImagePickerResult>[];
    
    for (final file in selectedFiles) {
      final ioFile = File(file.path);
      final creationDate = await _getCreationDate(ioFile);
      results.add(AppImagePickerResult(
        file: ioFile,
        creationDate: creationDate,
      ));
    }
    
    return results;
  }

  /// 카메라로 단건 이미지를 촬영합니다. (현재 시간 기준)
  static Future<AppImagePickerResult?> pickCameraImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return null;

    final file = File(image.path);
    return AppImagePickerResult(
      file: file,
      creationDate: DateTime.now(),
    );
  }

  /// EXIF 데이터를 읽어 사진 생성 시간을 추출합니다.
  static Future<DateTime> _getCreationDate(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final Map<String, IfdTag> data = await readExifFromBytes(bytes);
      
      // EXIF의 DateTimeOriginal이나 DateTime 정보를 확인합니다.
      final tag = data['Image DateTime'] ?? data['EXIF DateTimeOriginal'];
      if (tag != null) {
        final dateString = tag.toString().trim();
        // EXIF 날짜 포맷: "YYYY:MM:DD HH:MM:SS" -> "YYYY-MM-DD HH:MM:SS"
        final formattedString = dateString.replaceFirst(':', '-').replaceFirst(':', '-');
        return DateTime.parse(formattedString);
      }
    } catch (e) {
      debugPrint('Failed to read EXIF creation date: $e');
    }
    
    // EXIF가 없거나 읽기 실패하면, 기본적으로 파일 수정 시간(또는 현재 시간)을 반환합니다.
    try {
      return file.lastModifiedSync();
    } catch (_) {
      return DateTime.now();
    }
  }
}
