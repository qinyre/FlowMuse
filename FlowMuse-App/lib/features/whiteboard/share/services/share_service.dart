import '../models/share_payload.dart';
import '../models/share_result.dart';

abstract interface class ShareService {
  Future<ShareResult> share(SharePayload payload);
}
