import 'package:flutter/widgets.dart';
import '../models/invitation_models.dart';
import '../models/social_models.dart';

/// The app owns whiteboard navigation; social widgets only pass public IDs.
class InvitationActions extends InheritedWidget {
  const InvitationActions({
    super.key,
    required super.child,
    required this.open,
    required this.send,
  });
  final Future<void> Function(String id) open;
  final Future<void> Function(SocialPerson peer, SocialInvitation? supplement)
  send;
  static InvitationActions? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InvitationActions>();
  @override
  bool updateShouldNotify(InvitationActions oldWidget) =>
      open != oldWidget.open || send != oldWidget.send;
}
