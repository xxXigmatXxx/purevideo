import 'package:flutter/material.dart';

class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocusChange;
  final BorderRadius borderRadius;
  final bool autofocus;
  final FocusNode? focusNode;
  final Color focusBorderColor;
  final double focusBorderWidth;
  final double focusScale;
  final EdgeInsetsGeometry? padding;
  final bool ensureVisibleOnFocus;
  final double ensureVisibleAlignment;

  const TvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onFocusChange,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.autofocus = false,
    this.focusNode,
    this.focusBorderColor = Colors.white,
    this.focusBorderWidth = 2.5,
    this.focusScale = 1.03,
    this.padding,
    this.ensureVisibleOnFocus = true,
    this.ensureVisibleAlignment = 0.38,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: widget.padding,
      foregroundDecoration: _isFocused
          ? BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: widget.focusBorderColor,
                width: widget.focusBorderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.focusBorderColor.withAlpha(80),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      child: widget.child,
    );

    if (widget.focusScale != 1.0) {
      content = AnimatedScale(
        scale: _isFocused ? widget.focusScale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: content,
      );
    }

    return Material(
      color: Colors.transparent,
      borderRadius: widget.borderRadius,
      child: InkWell(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        borderRadius: widget.borderRadius,
        focusColor: Colors.white.withAlpha(20),
        hoverColor: Colors.white.withAlpha(14),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onFocusChange: (focused) {
          if (mounted) {
            setState(() => _isFocused = focused);
          }
          widget.onFocusChange?.call(focused);
          if (focused && widget.ensureVisibleOnFocus) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Scrollable.ensureVisible(
                  context,
                  alignment: widget.ensureVisibleAlignment,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                );
              }
            });
          }
        },
        child: content,
      ),
    );
  }
}
