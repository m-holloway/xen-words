import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/director_tuner.dart';
import '../models/tunable_parameter.dart';

/// Full-screen touch slider for relative parameter adjustment
/// Supports coarse (X-axis) and fine (Y-axis) modes with hysteresis
/// For boolean parameters, shows a toggle UI instead
class RelativeTouchSlider extends StatefulWidget {
  final String director;
  final String paramName;
  final TunableParameter parameter;
  final VoidCallback onValueChanged;
  
  const RelativeTouchSlider({
    Key? key,
    required this.director,
    required this.paramName,
    required this.parameter,
    required this.onValueChanged,
  }) : super(key: key);
  
  @override
  State<RelativeTouchSlider> createState() => _RelativeTouchSliderState();
}

class _RelativeTouchSliderState extends State<RelativeTouchSlider> {
  double? _startX;
  double? _startY;
  double? _startValue;
  double? _displayMin;
  double? _displayMax;
  bool _isDragging = false;
  String _mode = 'idle'; // 'idle', 'coarse', 'fine'
  
  static const double _hysteresis = 30.0; // pixels
  
  Widget _buildBooleanToggle() {
    final currentValue = DirectorTuner.instance.getValue(
      widget.director,
      widget.paramName,
      widget.parameter.defaultValue,
    ) as bool;
    
    return Positioned(
      top: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.paramName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 120,
                height: 60,
                decoration: BoxDecoration(
                  color: currentValue ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: currentValue ? Colors.green : Colors.red,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    currentValue ? 'TRUE' : 'FALSE',
                    style: TextStyle(
                      color: currentValue ? Colors.green : Colors.red,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Press +/- to toggle',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    // For boolean parameters, show a simple toggle UI
    if (widget.parameter.type == ParameterType.bool) {
      return Stack(
        children: [
          _buildBooleanToggle(),
        ],
      );
    }
    
    final currentValue = _getCurrentValue();
    final displayValue = _isDragging && _startValue != null 
        ? _startValue! + _getDeltaValue()
        : currentValue;
    
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Container(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Visual feedback based on mode
            if (_mode == 'coarse')
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: _buildCoarseFeedback(displayValue),
              )
            else if (_mode == 'fine')
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: _buildFineFeedback(displayValue),
              ),
            
            // Live value display
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.paramName}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatValue(displayValue),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.parameter.unit != null)
                        Text(
                          widget.parameter.unit!,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Default: ${_formatDefaultValue()}',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Mode indicator
            if (_mode != 'idle')
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _mode == 'coarse' ? Colors.orange : Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _mode == 'coarse' ? 'COARSE MODE' : 'FINE MODE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCoarseFeedback(double value) {
    final range = _displayMax! - _displayMin!;
    final normalized = (value - _displayMin!) / range;
    final progress = normalized.clamp(0.0, 1.0);
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.orange.withOpacity(0.15), // Reduced from 0.3
            Colors.orange.withOpacity(0.05), // Reduced from 0.1
            Colors.orange.withOpacity(0.15), // Reduced from 0.3
          ],
          stops: [0.0, progress, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _HorizontalProgressPainter(progress),
      ),
    );
  }
  
  Widget _buildFineFeedback(double value) {
    final range = _displayMax! - _displayMin!;
    final normalized = (value - _displayMin!) / range;
    final progress = normalized.clamp(0.0, 1.0);
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blue.withOpacity(0.15), // Reduced from 0.3
            Colors.blue.withOpacity(0.05), // Reduced from 0.1
            Colors.blue.withOpacity(0.15), // Reduced from 0.3
          ],
          stops: [0.0, progress, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _VerticalProgressPainter(progress),
      ),
    );
  }
  
  void _onPanStart(DragStartDetails details) {
    _startX = details.globalPosition.dx;
    _startY = details.globalPosition.dy;
    _startValue = _getCurrentValue();
    
    // Calculate display range centered on current value
    final range = widget.parameter.max - widget.parameter.min;
    final center = _startValue!;
    _displayMin = math.max(widget.parameter.min, center - range / 2);
    _displayMax = math.min(widget.parameter.max, center + range / 2);
    
    setState(() {
      _isDragging = true;
      _mode = 'idle';
    });
  }
  
  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDragging || _startX == null || _startY == null || _startValue == null) return;
    
    final dx = (details.globalPosition.dx - _startX!).abs();
    final dy = (details.globalPosition.dy - _startY!).abs();
    
    // Determine mode based on dominant axis
    String newMode = _mode;
    if (_mode == 'idle') {
      if (dx > _hysteresis) {
        newMode = 'coarse';
      } else if (dy > _hysteresis) {
        newMode = 'fine';
      }
    }
    
    if (newMode != _mode) {
      setState(() {
        _mode = newMode;
      });
    }
    
    // Calculate delta value
    final delta = _getDeltaValue();
    var newValue = (_startValue! + delta).clamp(
      widget.parameter.min,
      widget.parameter.max,
    );
    
    // Round to integer if parameter is int type
    if (widget.parameter.type == ParameterType.int) {
      newValue = newValue.round().toDouble();
    }
    
    // Update parameter
    DirectorTuner.instance.setParameter(widget.director, widget.paramName, newValue);
    widget.onValueChanged();
  }
  
  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
      _mode = 'idle';
      _startX = null;
      _startY = null;
      _startValue = null;
      _displayMin = null;
      _displayMax = null;
    });
  }
  
  double _getDeltaValue() {
    if (!_isDragging || _startX == null || _startY == null || _startValue == null) return 0.0;
    
    final range = _displayMax! - _displayMin!;
    
    if (_mode == 'coarse') {
      // X-axis: full range
      final screenWidth = MediaQuery.of(context).size.width;
      final dx = (MediaQuery.of(context).size.width / 2) - _startX!;
      return (dx / screenWidth) * range;
    } else if (_mode == 'fine') {
      // Y-axis: 10% of range (10x finer)
      final screenHeight = MediaQuery.of(context).size.height;
      final dy = (MediaQuery.of(context).size.height / 2) - _startY!;
      return (dy / screenHeight) * range * 0.1;
    }
    
    return 0.0;
  }
  
  double _getCurrentValue() {
    final value = DirectorTuner.instance.getValue(
      widget.director,
      widget.paramName,
      widget.parameter.defaultValue,
    );
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is bool) return value ? 1.0 : 0.0;
    return widget.parameter.defaultValue as double;
  }
  
  String _formatValue(double value) {
    if (widget.parameter.type == ParameterType.int) {
      return value.round().toString();
    }
    // Adaptive decimal formatting based on magnitude
    final absValue = value.abs();
    if (absValue >= 100) {
      return value.toStringAsFixed(1);
    } else if (absValue >= 10) {
      return value.toStringAsFixed(2);
    } else if (absValue >= 1) {
      return value.toStringAsFixed(3);
    } else if (absValue >= 0.01) {
      return value.toStringAsFixed(4);
    } else if (absValue >= 0.0001) {
      return value.toStringAsFixed(5);
    } else {
      return value.toStringAsFixed(6);
    }
  }
  
  String _formatDefaultValue() {
    final defaultValue = widget.parameter.defaultValue;
    if (defaultValue is int) {
      return defaultValue.toString();
    } else if (defaultValue is double) {
      return _formatValue(defaultValue);
    } else if (defaultValue is bool) {
      return defaultValue.toString();
    }
    return defaultValue.toString();
  }
}

class _HorizontalProgressPainter extends CustomPainter {
  final double progress;
  
  _HorizontalProgressPainter(this.progress);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.orange.withOpacity(0.3) // Reduced from 0.5
      ..strokeWidth = 3.0; // Reduced from 4.0
    
    final centerY = size.height / 2;
    final x = size.width * progress;
    
    canvas.drawLine(
      Offset(0, centerY),
      Offset(x, centerY),
      paint,
    );
  }
  
  @override
  bool shouldRepaint(_HorizontalProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _VerticalProgressPainter extends CustomPainter {
  final double progress;
  
  _VerticalProgressPainter(this.progress);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.3) // Reduced from 0.5
      ..strokeWidth = 3.0; // Reduced from 4.0
    
    final centerX = size.width / 2;
    final y = size.height * (1.0 - progress); // Invert for natural feel
    
    canvas.drawLine(
      Offset(centerX, size.height),
      Offset(centerX, y),
      paint,
    );
  }
  
  @override
  bool shouldRepaint(_VerticalProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

