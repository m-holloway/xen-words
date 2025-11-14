import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/app_logger.dart';

/// Parental gate widget to prevent children from accessing restricted content.
/// 
/// Uses a simple math problem (e.g., "What is 7 + 5?") to verify adult access.
/// This is COPPA-compliant and prevents accidental taps by children.
/// 
/// Usage:
/// ```dart
/// final allowed = await ParentalGate.show(context);
/// if (allowed) {
///   // Show settings, external links, etc.
/// }
/// ```
class ParentalGate {
  /// Shows the parental gate dialog and returns true if the user passes.
  static Future<bool> show(
    BuildContext context, {
    String title = 'Adult Verification',
    String message = 'Please solve this problem to continue:',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _ParentalGateDialog(
        title: title,
        message: message,
      ),
    );
    
    return result ?? false;
  }
}

class _ParentalGateDialog extends StatefulWidget {
  final String title;
  final String message;
  
  const _ParentalGateDialog({
    required this.title,
    required this.message,
  });
  
  @override
  State<_ParentalGateDialog> createState() => _ParentalGateDialogState();
}

class _ParentalGateDialogState extends State<_ParentalGateDialog> {
  final _random = Random();
  late int _num1;
  late int _num2;
  late int _correctAnswer;
  final _answerController = TextEditingController();
  int _attempts = 0;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _generateProblem();
  }
  
  void _generateProblem() {
    // Generate numbers between 5 and 15 for addition
    // This is easy for adults but hard for young children
    _num1 = 5 + _random.nextInt(11); // 5-15
    _num2 = 5 + _random.nextInt(11); // 5-15
    _correctAnswer = _num1 + _num2;
    
    AppLogger.ui.d('Parental gate: $_num1 + $_num2 = $_correctAnswer');
  }
  
  void _checkAnswer() {
    final userAnswer = int.tryParse(_answerController.text);
    _attempts++;
    
    if (userAnswer == null) {
      setState(() {
        _errorMessage = 'Please enter a number';
      });
      return;
    }
    
    if (userAnswer == _correctAnswer) {
      AppLogger.ui.i('Parental gate passed (attempts: $_attempts)');
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorMessage = 'Incorrect answer. Please try again.';
      });
      
      _answerController.clear();
      
      // After 3 failed attempts, generate a new problem
      if (_attempts >= 3) {
        _generateProblem();
        _attempts = 0;
        setState(() {
          _errorMessage = 'Let\'s try a different problem...';
        });
      }
      
      AppLogger.ui.w('Parental gate failed (attempt $_attempts)');
    }
  }
  
  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lock_outline, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            
            // Math problem
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'What is $_num1 + $_num2?',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Answer input
            TextField(
              controller: _answerController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Your answer',
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
              ),
              onSubmitted: (_) => _checkAnswer(),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              'This verification helps keep children safe.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            AppLogger.ui.d('Parental gate cancelled');
            Navigator.of(context).pop(false);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _checkAnswer,
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

/// A button wrapper that shows parental gate before executing an action.
/// 
/// Usage:
/// ```dart
/// ParentalGatedButton(
///   onPassed: () => Navigator.push(...),
///   child: Text('Settings'),
/// )
/// ```
class ParentalGatedButton extends StatelessWidget {
  final VoidCallback onPassed;
  final Widget child;
  final String? gateTitle;
  final String? gateMessage;
  
  const ParentalGatedButton({
    Key? key,
    required this.onPassed,
    required this.child,
    this.gateTitle,
    this.gateMessage,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final passed = await ParentalGate.show(
          context,
          title: gateTitle ?? 'Adult Verification',
          message: gateMessage ?? 'Please solve this problem to continue:',
        );
        
        if (passed) {
          onPassed();
        }
      },
      child: child,
    );
  }
}

/// A wrapper for IconButton that shows parental gate.
class ParentalGatedIconButton extends StatelessWidget {
  final VoidCallback onPassed;
  final IconData icon;
  final String? tooltip;
  final String? gateTitle;
  final String? gateMessage;
  
  const ParentalGatedIconButton({
    Key? key,
    required this.onPassed,
    required this.icon,
    this.tooltip,
    this.gateTitle,
    this.gateMessage,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: () async {
        final passed = await ParentalGate.show(
          context,
          title: gateTitle ?? 'Adult Verification',
          message: gateMessage ?? 'Please solve this problem to continue:',
        );
        
        if (passed) {
          onPassed();
        }
      },
    );
  }
}

