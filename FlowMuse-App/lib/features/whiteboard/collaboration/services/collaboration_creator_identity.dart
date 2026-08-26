import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flow_muse/features/account/models/collaboration_identity.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';

/// 登录用户 creatorKey：跨房间稳定（不含 roomId），与既有房主 ownerKeyHash
/// 通过固定域前缀隔离。哈希只是避免把 userId 明文写进元素，不构成匿名化。
String creatorKeyForUserId(String userId) {
  final digest = sha256.convert(utf8.encode('flowmuse-creator-v1|$userId'));
  return 'user:${digest.toString()}';
}

/// 游客 creatorKey：绑定房间 + 会话 UUID。Socket 重连期间复用；
/// 完整退出房间后由宿主清除 sessionUuid，再次加入形成新逻辑组。
String creatorKeyForGuest(String roomId, String sessionUuid) =>
    'guest:$roomId:$sessionUuid';

/// 由当前协作身份派生创建者快照。guestSessionId 仅在 identity.isGuest
/// 时使用。
CollaborationCreator creatorForIdentity({
  required CollaborationIdentity identity,
  required String roomId,
  required String guestSessionId,
}) {
  if (identity.isGuest) {
    return CollaborationCreator(
      creatorKey: creatorKeyForGuest(roomId, guestSessionId),
      displayName: identity.username,
      isGuest: true,
    );
  }
  final userId = identity.userId;
  assert(userId != null, '登录身份必须携带 userId');
  return CollaborationCreator(
    creatorKey: creatorKeyForUserId(userId!),
    displayName: identity.username,
    isGuest: false,
  );
}
