import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:image_picker/image_picker.dart';

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
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        maxAssets: 1,
        requestType: RequestType.image,
        themeColor: Color(0xFFFFC700),
      ),
    );

    if (assets == null || assets.isEmpty) return null;
    
    final asset = assets.first;
    final file = await asset.file;
    if (file == null) return null;

    return AppImagePickerResult(
      file: file,
      creationDate: asset.createDateTime,
    );
  }

  /// 갤러리에서 다건 이미지를 선택합니다.
  static Future<List<AppImagePickerResult>> pickMultipleGalleryImages(
    BuildContext context, {
    int maxAssets = 30,
  }) async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: maxAssets,
        requestType: RequestType.image,
        themeColor: const Color(0xFFFFC700),
      ),
    );

    if (assets == null || assets.isEmpty) return [];

    final results = <AppImagePickerResult>[];
    for (final asset in assets) {
      final file = await asset.file;
      if (file != null) {
        results.add(AppImagePickerResult(
          file: file,
          creationDate: asset.createDateTime,
        ));
      }
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
}
