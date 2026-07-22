import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvFocusButton extends StatefulWidget {
  const TvFocusButton({
    required this.focusNode,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.onNextFocus,
    this.onPreviousFocus,
    this.autofocus = false,
    this.enabled = true,
    super.key,
  });

  final FocusNode focusNode;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final VoidCallback? onNextFocus;
  final VoidCallback? onPreviousFocus;
  final bool autofocus;
  final bool enabled;

  @override
  State<TvFocusButton> createState() => _TvFocusButtonState();
}

class _TvFocusButtonState extends State<TvFocusButton> {
  bool _focused = false;
  bool _pressed = false;
  Timer? _pressTimer;

  @override
  void initState() {
    super.initState();
    _syncFocusAvailability();
    _scheduleAutofocus();
  }

  @override
  void didUpdateWidget(TvFocusButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode
        ..canRequestFocus = true
        ..skipTraversal = false;
    }
    _syncFocusAvailability();
    _scheduleAutofocus();
  }

  @override
  void dispose() {
    _pressTimer?.cancel();
    widget.focusNode
      ..canRequestFocus = true
      ..skipTraversal = false;
    super.dispose();
  }

  void _syncFocusAvailability() {
    widget.focusNode
      ..canRequestFocus = widget.enabled
      ..skipTraversal = !widget.enabled;
  }

  void _scheduleAutofocus() {
    if (!widget.autofocus || !widget.enabled) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.enabled ||
          !widget.focusNode.canRequestFocus ||
          widget.focusNode.hasFocus) {
        return;
      }
      final focusedChild = FocusScope.of(context).focusedChild;
      if (focusedChild != null && focusedChild != widget.focusNode) {
        return;
      }
      FocusScope.of(context).requestFocus(widget.focusNode);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _activate() {
    if (!widget.enabled) {
      return;
    }
    _showPressFeedback();
    widget.onPressed();
  }

  void _showPressFeedback() {
    _pressTimer?.cancel();
    if (mounted) {
      setState(() {
        _pressed = true;
      });
    }
    _pressTimer = Timer(const Duration(milliseconds: 110), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _pressed = false;
      });
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.numpadEnter) {
      _activate();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      final next = widget.onNextFocus;
      if (next != null) {
        next();
      } else {
        node.nextFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      final previous = widget.onPreviousFocus;
      if (previous != null) {
        previous();
      } else {
        node.previousFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = _textColor(colorScheme);
    final iconColor = _iconColor(colorScheme);
    final scale = _pressed ? 0.98 : (_focused ? 1.03 : 1.0);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      focused: _focused,
      label: widget.label,
      onTap: widget.enabled ? _activate : null,
      child: ExcludeFocus(
        excluding: !widget.enabled,
        child: Focus(
          focusNode: widget.focusNode,
          autofocus: false,
          canRequestFocus: widget.enabled,
          skipTraversal: !widget.enabled,
          onKeyEvent: _handleKeyEvent,
          onFocusChange: (value) {
            if (_focused == value) {
              return;
            }
            setState(() {
              _focused = value;
            });
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? _activate : null,
            child: AnimatedScale(
              duration: Duration(milliseconds: _pressed ? 110 : 150),
              curve: Curves.easeOutCubic,
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _backgroundColor(colorScheme),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _borderColor(colorScheme),
                    width: _focused ? 3 : 1.5,
                  ),
                  boxShadow: _focused
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF20E0D0,
                            ).withValues(alpha: 0.28),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: iconColor),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: textColor,
                          fontWeight: _focused
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _backgroundColor(ColorScheme colorScheme) {
    if (!widget.enabled) {
      return colorScheme.surfaceContainerLowest;
    }
    if (_pressed) {
      return colorScheme.primaryContainer;
    }
    if (_focused) {
      return colorScheme.surfaceContainerHighest;
    }
    return colorScheme.surfaceContainerHigh;
  }

  Color _borderColor(ColorScheme colorScheme) {
    if (!widget.enabled) {
      return colorScheme.outlineVariant.withValues(alpha: 0.72);
    }
    if (_focused) {
      return const Color(0xFF20E0D0);
    }
    return colorScheme.outlineVariant;
  }

  Color _textColor(ColorScheme colorScheme) {
    if (!widget.enabled) {
      return colorScheme.onSurface.withValues(alpha: 0.64);
    }
    if (_focused || _pressed) {
      return Colors.white;
    }
    return colorScheme.onSurface;
  }

  Color _iconColor(ColorScheme colorScheme) {
    if (!widget.enabled) {
      return colorScheme.onSurface.withValues(alpha: 0.58);
    }
    if (_focused || _pressed) {
      return const Color(0xFFE6FFFF);
    }
    return colorScheme.onSurfaceVariant;
  }
}
