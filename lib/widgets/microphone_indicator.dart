import 'package:flutter/material.dart';

/// Visual indicator for microphone activity
class MicrophoneIndicator extends StatelessWidget {
  final bool isEnabled;
  final double rms;

  const MicrophoneIndicator({
    Key? key,
    required this.isEnabled,
    this.rms = 0.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = isEnabled ? Colors.green : Colors.grey;
    final size = 40.0 + (rms * 20.0).clamp(0.0, 20.0);

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
          child: Icon(
            isEnabled ? Icons.mic : Icons.mic_off,
            color: Colors.white,
            size: size * 0.6,
          ),
        ),
      ),
    );
  }
}

