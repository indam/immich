import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/response_extensions.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:logging/logging.dart';

import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';

final imageViewerServiceProvider =
    Provider((ref) => ImageViewerService(ref.watch(apiServiceProvider)));

class ImageViewerService {
  final ApiService _apiService;
  final Logger _log = Logger("ImageViewerService");

  ImageViewerService(this._apiService);

  Future<bool> downloadAsset(Asset asset) async {
    File? imageFile;
    File? videoFile;
    try {
      // Download LivePhotos image and motion part
      if (asset.isImage && asset.livePhotoVideoId != null && Platform.isIOS) {
        var imageResponse =
            await _apiService.assetsApi.downloadAssetWithHttpInfo(
          asset.remoteId!,
        );

        var motionResponse =
            await _apiService.assetsApi.downloadAssetWithHttpInfo(
          asset.livePhotoVideoId!,
        );

        if (imageResponse.statusCode != 200 ||
            motionResponse.statusCode != 200) {
          final failedResponse =
              imageResponse.statusCode != 200 ? imageResponse : motionResponse;
          _log.severe(
            "Motion asset download failed",
            failedResponse.toLoggerString(),
          );
          return false;
        }

        AssetEntity? entity;

        final tempDir = await getTemporaryDirectory();
        videoFile = await File('${tempDir.path}/livephoto.mov').create();
        imageFile = await File('${tempDir.path}/livephoto.heic').create();
        videoFile.writeAsBytesSync(motionResponse.bodyBytes);
        imageFile.writeAsBytesSync(imageResponse.bodyBytes);

        entity = await PhotoManager.editor.darwin.saveLivePhoto(
          imageFile: imageFile,
          videoFile: videoFile,
          title: asset.fileName,
        );

        if (entity == null) {
          _log.warning(
            "Asset cannot be saved as a live photo. This is most likely a motion photo. Saving only the image file",
          );

          entity = await PhotoManager.editor.saveImage(
            imageResponse.bodyBytes,
            title: asset.fileName,
          );
        }

        return entity != null;
      } else {
        var res = await _apiService.assetsApi
            .downloadAssetWithHttpInfo(asset.remoteId!);

        if (res.statusCode != 200) {
          _log.severe("Asset download failed", res.toLoggerString());
          return false;
        }

        final AssetEntity? entity;
        final relativePath = Platform.isAndroid ? 'DCIM/Immich' : null;

        if (asset.isImage) {
          entity = await PhotoManager.editor.saveImage(
            res.bodyBytes,
            title: asset.fileName,
            relativePath: relativePath,
          );
        } else {
          final tempDir = await getTemporaryDirectory();
          videoFile = await File('${tempDir.path}/${asset.fileName}').create();
          videoFile.writeAsBytesSync(res.bodyBytes);
          entity = await PhotoManager.editor.saveVideo(
            videoFile,
            title: asset.fileName,
            relativePath: relativePath,
          );
        }
        return entity != null;
      }
    } catch (error, stack) {
      _log.severe("Error saving downloaded asset", error, stack);
      return false;
    } finally {
      // Clear temp files
      imageFile?.delete();
      videoFile?.delete();
    }
  }
}
