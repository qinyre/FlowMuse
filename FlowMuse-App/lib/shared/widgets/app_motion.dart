import 'package:flutter/widgets.dart';

/// 界面动画节奏；书写和协作墨迹不使用这些过渡。
class AppMotion {
  const AppMotion._();

  static const quick = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 200);
  static const exit = Duration(milliseconds: 150);
  static const page = Duration(milliseconds: 260);

  static Duration resolve(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
