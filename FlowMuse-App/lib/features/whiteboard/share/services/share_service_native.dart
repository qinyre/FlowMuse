import 'package:share_plus/share_plus.dart' as share_plus;

import '../models/share_payload.dart';
import '../models/share_result.dart';
import 'share_service.dart';

class NativeShareService implements ShareService {
  const NativeShareService();

  @override
  Future<ShareResult> share(SharePayload payload) async {
    try {
      final result = switch (payload) {
        ShareTextPayload() => await share_plus.SharePlus.instance.share(
          share_plus.ShareParams(text: payload.text, title: payload.title),
        ),
        ShareFilePayload() => await share_plus.SharePlus.instance.share(
          share_plus.ShareParams(
            files: [
              if (payload.filePath != null)
                share_plus.XFile(
                  payload.filePath!,
                  mimeType: payload.mimeType,
                  name: payload.fileName,
                )
              else
                share_plus.XFile.fromData(
                  payload.bytes!,
                  mimeType: payload.mimeType,
                  name: payload.fileName,
                ),
            ],
            title: payload.title,
            fileNameOverrides: [payload.fileName],
          ),
        ),
      };
      return mapNativeShareResult(result);
    } catch (_) {
      return ShareResult.failed;
    }
  }
}

ShareResult mapNativeShareResult(share_plus.ShareResult result) {
  return switch (result.status) {
    share_plus.ShareResultStatus.success => ShareResult.completed,
    share_plus.ShareResultStatus.dismissed => ShareResult.dismissed,
    share_plus.ShareResultStatus.unavailable => ShareResult.unavailable,
  };
}
