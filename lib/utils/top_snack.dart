import 'package:flutter/material.dart';

/// Shows a top-of-screen notification that slides in from the top,
/// stays for [duration], then fades out.
void showTopSnack(
  BuildContext context, {
  required String message,
  required Color backgroundColor,
  IconData? icon,
  Duration duration = const Duration(seconds: 2),
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (ctx) => _TopSnackEntry(
      message: message,
      backgroundColor: backgroundColor,
      icon: icon,
      duration: duration,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );

  overlay.insert(entry);
}

class _TopSnackEntry extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismissed;

  const _TopSnackEntry({
    required this.message,
    required this.backgroundColor,
    required this.icon,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_TopSnackEntry> createState() => _TopSnackEntryState();
}

class _TopSnackEntryState extends State<_TopSnackEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 12;
    return Positioned(
      top: topPadding,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _opacity,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: widget.backgroundColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
