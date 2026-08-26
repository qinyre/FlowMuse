import 'brush_type.dart' show flowMuseCustomDataKey;
import 'element.dart';

/// 协作元素创建者快照。仅用于显示层分组，不是账号 ID，不是权限凭据，
/// 客户端可伪造；禁止用于任何锁定/鉴权判断。
class CollaborationCreator {
  const CollaborationCreator({
    required this.creatorKey,
    required this.displayName,
    required this.isGuest,
  });

  static const int schemaVersion = 1;

  /// 客户端稳定、伪匿名的逻辑分组键，如 `user:<sha256>` 或 `guest:<roomId>:<uuid>`。
  final String creatorKey;

  /// 创建时的显示名快照；创建者离线时作为回退显示。
  final String displayName;

  /// 创建时的身份快照（游客/登录）。
  final bool isGuest;

  Map<String, Object?> toOwnerJson() => <String, Object?>{
    'version': schemaVersion,
    'creatorKey': creatorKey,
    'displayName': displayName,
    'isGuest': isGuest,
  };

  /// 宽松解析：只接受类型完全合法的公共字段；未知高 version 也能读取
  /// （前向兼容）；任何畸形输入返回 null，绝不抛异常。
  static CollaborationCreator? fromOwnerJson(Object? raw) {
    if (raw is! Map) return null;
    final creatorKey = raw['creatorKey'];
    final displayName = raw['displayName'];
    final isGuest = raw['isGuest'];
    final version = raw['version'];
    if (creatorKey is! String || creatorKey.isEmpty) return null;
    if (displayName is! String) return null;
    if (isGuest is! bool) return null;
    if (version is! int || version < 1) return null;
    return CollaborationCreator(
      creatorKey: creatorKey,
      displayName: displayName,
      isGuest: isGuest,
    );
  }
}

/// `customData.flowMuse.collaborationOwner` 的键名（测试与文档引用）。
const String kCollaborationOwnerCustomDataKey = 'collaborationOwner';

CollaborationCreator? readCreator(Element element) {
  final customData = element.customData;
  if (customData == null) return null;
  final flowMuse = customData[flowMuseCustomDataKey];
  if (flowMuse is! Map) return null;
  return CollaborationCreator.fromOwnerJson(
    flowMuse[kCollaborationOwnerCustomDataKey],
  );
}

/// 深合并写入 owner：重建 customData 与 flowMuse 两级 Map，只覆盖
/// collaborationOwner 一个键，其余键原样保留。输入元素不被修改。
Element withCreator(Element element, CollaborationCreator creator) {
  final customData = element.customData ?? const <String, Object?>{};
  final merged = _withOwnerInCustomData(customData, creator.toOwnerJson());
  return element.copyWith(customData: merged);
}

/// 只删除 collaborationOwner；flowMuse 中的其他键保留。无 owner 时
/// 返回同一实例（copy-on-write 短路）。
Element withoutCreator(Element element) {
  final customData = element.customData;
  if (customData == null) return element;
  final flowMuseRaw = customData[flowMuseCustomDataKey];
  if (flowMuseRaw is! Map ||
      !flowMuseRaw.containsKey(kCollaborationOwnerCustomDataKey)) {
    return element;
  }
  final merged = Map<String, Object?>.from(customData);
  final flowMuse = Map<String, Object?>.from(flowMuseRaw);
  flowMuse.remove(kCollaborationOwnerCustomDataKey);
  if (flowMuse.isEmpty) {
    merged.remove(flowMuseCustomDataKey);
  } else {
    merged[flowMuseCustomDataKey] = flowMuse;
  }
  return element.copyWith(customData: merged);
}

CollaborationCreator? readCreatorFromJson(Map<String, Object?> element) {
  final customData = element['customData'];
  if (customData is! Map) return null;
  final flowMuse = customData[flowMuseCustomDataKey];
  if (flowMuse is! Map) return null;
  return CollaborationCreator.fromOwnerJson(
    flowMuse[kCollaborationOwnerCustomDataKey],
  );
}

/// raw 元素 JSON（协作 reconciler 使用）版本。返回新 Map；已持有相同
/// creatorKey 时返回同一实例（短路，便于 reconciler 不产生无谓新对象）。
Map<String, Object?> withCreatorInJson(
  Map<String, Object?> element,
  CollaborationCreator creator,
) {
  final current = readCreatorFromJson(element);
  if (current != null &&
      current.creatorKey == creator.creatorKey &&
      current.displayName == creator.displayName &&
      current.isGuest == creator.isGuest) {
    return element;
  }
  final customData = element['customData'];
  final base = customData is Map
      ? Map<String, Object?>.from(customData)
      : <String, Object?>{};
  final flowMuseRaw = base[flowMuseCustomDataKey];
  final flowMuse = flowMuseRaw is Map
      ? Map<String, Object?>.from(flowMuseRaw)
      : <String, Object?>{};
  flowMuse[kCollaborationOwnerCustomDataKey] = creator.toOwnerJson();
  base[flowMuseCustomDataKey] = flowMuse;
  return <String, Object?>{...element, 'customData': base};
}

Map<String, Object?> withoutCreatorInJson(Map<String, Object?> element) {
  final customData = element['customData'];
  if (customData is! Map) return element;
  final flowMuseRaw = customData[flowMuseCustomDataKey];
  if (flowMuseRaw is! Map ||
      !flowMuseRaw.containsKey(kCollaborationOwnerCustomDataKey)) {
    return element;
  }
  final mergedCustomData = Map<String, Object?>.from(customData);
  final flowMuse = Map<String, Object?>.from(flowMuseRaw);
  flowMuse.remove(kCollaborationOwnerCustomDataKey);
  if (flowMuse.isEmpty) {
    mergedCustomData.remove(flowMuseCustomDataKey);
  } else {
    mergedCustomData[flowMuseCustomDataKey] = flowMuse;
  }
  // 剥离后 customData 为空时整个键移除（无残留空 map）
  final output = <String, Object?>{...element};
  if (mergedCustomData.isEmpty) {
    output.remove('customData');
  } else {
    output['customData'] = mergedCustomData;
  }
  return output;
}

Map<String, Object?> _withOwnerInCustomData(
  Map<String, Object?> customData,
  Map<String, Object?> ownerJson,
) {
  final merged = Map<String, Object?>.from(customData);
  final flowMuseRaw = merged[flowMuseCustomDataKey];
  final flowMuse = flowMuseRaw is Map
      ? Map<String, Object?>.from(flowMuseRaw)
      : <String, Object?>{};
  flowMuse[kCollaborationOwnerCustomDataKey] = ownerJson;
  merged[flowMuseCustomDataKey] = flowMuse;
  return merged;
}
