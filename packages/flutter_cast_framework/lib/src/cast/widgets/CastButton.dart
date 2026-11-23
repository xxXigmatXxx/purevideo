import 'package:flutter/widgets.dart';

import '../../flutter_cast_framework.dart';
import 'CastIcon.dart';

class CastButton extends StatelessWidget {
  final Color color;
  final Color activeColor;
  final Color disabledColor;
  final EdgeInsets padding;
  final FlutterCastFramework castFramework;

  CastButton({
    required this.castFramework,
    this.color = const Color(0xFFFFFFFF), // white
    this.activeColor = const Color(0xFF0000FF), // blue
    this.disabledColor = const Color(0xFFC9C9C9), // gray
    this.padding = const EdgeInsets.all(8.0),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        child: Padding(
          padding: padding,
          child: CastIcon(
            castFramework: castFramework,
            color: color,
            activeColor: activeColor,
            disabledColor: disabledColor,
          ),
        ),
        onTap: () => castFramework.castContext.showCastChooserDialog());
  }
}
