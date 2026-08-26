import 'package:flutter/material.dart';

class PulseAnimationWrapper extends StatefulWidget {
  final Widget child;
  final bool isActive;
  final Color pulseColor;
  final double maxScale;

  const PulseAnimationWrapper({
    Key? key,
    required this.child,
    this.isActive = false,
    this.pulseColor = Colors.redAccent,
    this.maxScale = 1.6,
  }) : super(key: key);

  @override
  State<PulseAnimationWrapper> createState() => _PulseAnimationWrapperState();
}

class _PulseAnimationWrapperState extends State<PulseAnimationWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.maxScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(PulseAnimationWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat();
      } else {
        _controller.reset();
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.isActive)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.pulseColor.withOpacity(0.5),
                    ),
                    width: 48,
                    height: 48,
                  ),
                ),
              );
            },
          ),
        widget.child,
      ],
    );
  }
}
