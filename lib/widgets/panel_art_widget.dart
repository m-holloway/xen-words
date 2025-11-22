import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class PanelArtWidget extends StatelessWidget {
  final String imagePath;
  final double? width;
  final double? height;
  final bool animateEntry;
  final bool showFrame;
  final bool showShadow;
  final bool useHero;
  final String? heroTag;

  const PanelArtWidget({
    Key? key,
    required this.imagePath,
    this.width,
    this.height,
    this.animateEntry = false,
    this.showFrame = true,
    this.showShadow = true,
    this.useHero = false,
    this.heroTag,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Standard panel art styling
    // We use padding+color for the frame instead of border to ensure correct child sizing/clipping
    // and avoid background bleeding.
    final double borderRadius = 30.0;
    final double borderWidth = 8.0;
    final double innerRadius = borderRadius - borderWidth; // 22.0

    Widget content = Container(
      width: width,
      height: height,
      padding: showFrame ? EdgeInsets.all(borderWidth) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: showFrame ? Colors.white : Colors.transparent, // The frame color
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(showFrame ? innerRadius : borderRadius),
        child: Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
        ),
      ),
    );

    if (useHero && heroTag != null) {
      content = Hero(
        tag: heroTag!,
        child: content,
      );
    }

    if (animateEntry) {
      content = content
          .animate()
          .fadeIn(duration: 600.ms)
          .blurXY(
            begin: 12,
            end: 0,
            duration: 800.ms,
            curve: Curves.easeOut,
          )
          .scale(
            begin: const Offset(0.8, 0.8),
            end: const Offset(1.0, 1.0),
            duration: 1000.ms,
            curve: Curves.elasticOut,
          )
          .shimmer(
            delay: 600.ms,
            duration: 1800.ms,
            color: Colors.white.withOpacity(0.4),
            angle: -0.5,
            size: 1.5,
            curve: Curves.easeInOut,
          );
    }

    return content;
  }
}

