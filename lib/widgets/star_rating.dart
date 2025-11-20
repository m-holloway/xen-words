import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    this.onRatingChanged,
    this.size = 24,
    this.activeColor = Colors.amber,
    this.inactiveColor,
    this.spacing = 4,
    this.allowClear = true,
  });

  final int rating;
  final ValueChanged<int>? onRatingChanged;
  final double size;
  final Color activeColor;
  final Color? inactiveColor;
  final double spacing;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    final clampedRating = rating.clamp(0, 5);
    final Color resolvedInactiveColor = (inactiveColor ?? Theme.of(context).colorScheme.outlineVariant)
        .withValues(alpha: 0.4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        final isFilled = starIndex <= clampedRating;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRatingChanged == null
              ? null
              : () {
                  if (allowClear && clampedRating == starIndex) {
                    onRatingChanged!(0);
                  } else {
                    onRatingChanged!(starIndex);
                  }
                },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing / 2),
            child: Icon(
              isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
              color: isFilled ? activeColor : resolvedInactiveColor,
              size: size,
            ),
          ),
        );
      }),
    );
  }
}

