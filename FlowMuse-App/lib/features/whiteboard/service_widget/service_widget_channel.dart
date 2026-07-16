// dart.library.io is true on all non-Web native platforms (Android, iOS,
// macOS, Windows, Linux, OHOS). Non-OHOS platforms will import the OHOS
// implementation, but calls silently degrade via MissingPluginException
// because the channel is only registered in EntryAbility on OHOS.
export 'service_widget_channel_stub.dart'
    if (dart.library.io) 'service_widget_channel_ohos.dart';
