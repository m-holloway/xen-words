import 'package:flutter/material.dart';
import '../services/director_tuner.dart';

/// Interactive goto command parser with predictive display
class GotoCommand extends StatefulWidget {
  final Function(String director, String paramName)? onNavigate;
  
  const GotoCommand({
    Key? key,
    this.onNavigate,
  }) : super(key: key);
  
  @override
  State<GotoCommand> createState() => _GotoCommandState();
}

class _GotoCommandState extends State<GotoCommand> {
  final TextEditingController _controller = TextEditingController();
  String _command = '';
  List<String> _predictions = [];
  
  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCommandChanged);
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  void _onCommandChanged() {
    setState(() {
      _command = _controller.text;
      _updatePredictions();
    });
  }
  
  void _updatePredictions() {
    if (_command.isEmpty) {
      _predictions = [];
      return;
    }
    
    final tuner = DirectorTuner.instance;
    final directors = tuner.getDirectors();
    
    // Parse command: gl10.1 = lighting director, param 10, sub-param 1
    if (_command.length == 1) {
      // After 'g': show director options
      _predictions = directors
          .where((d) => d.startsWith(_command))
          .map((d) => '$d - ${_getDirectorName(d)}')
          .toList();
    } else if (_command.length == 2 && _command.startsWith('g')) {
      // After 'gl' or 'gc': show director or start param list
      final dirChar = _command[1];
      final matchingDir = directors.firstWhere(
        (d) => d.startsWith(dirChar),
        orElse: () => '',
      );
      
      if (matchingDir.isNotEmpty) {
        // Show first 10 parameters
        final params = tuner.getParameters(matchingDir);
        _predictions = params.take(10).map((p) => '${params.indexOf(p)} - ${p.name}').toList();
      } else {
        _predictions = [];
      }
    } else if (_command.length >= 2) {
      // Parse: gl10 or gl10.1
      final parts = _command.substring(1).split('.');
      if (parts.isNotEmpty) {
        final dirChar = parts[0].isEmpty ? '' : parts[0][0];
        final matchingDir = directors.firstWhere(
          (d) => d.startsWith(dirChar),
          orElse: () => '',
        );
        
        if (matchingDir.isNotEmpty) {
          final params = tuner.getParameters(matchingDir);
          
          if (parts.length == 1) {
            // gl10: show matching params
            final paramIndex = int.tryParse(parts[0].substring(1)) ?? -1;
            if (paramIndex >= 0 && paramIndex < params.length) {
              final param = params[paramIndex];
              // Check if param has sub-components
              if (param.name.contains('.x') || param.name.contains('.y') || param.name.contains('.z')) {
                _predictions = ['0 - x', '1 - y', '2 - z'];
              } else {
                _predictions = ['✓ ${param.name}'];
              }
            } else {
              // Show params matching the number
              _predictions = params
                  .where((p) => params.indexOf(p).toString().startsWith(parts[0].substring(1)))
                  .take(10)
                  .map((p) => '${params.indexOf(p)} - ${p.name}')
                  .toList();
            }
          } else if (parts.length == 2) {
            // gl10.1: show sub-param
            final paramIndex = int.tryParse(parts[0].substring(1)) ?? -1;
            if (paramIndex >= 0 && paramIndex < params.length) {
              final param = params[paramIndex];
              final subIndex = int.tryParse(parts[1]) ?? -1;
              if (subIndex >= 0 && subIndex < 3) {
                final components = ['x', 'y', 'z'];
                _predictions = ['✓ ${param.name}.${components[subIndex]}'];
              }
            }
          }
        }
      }
    }
  }
  
  String _getDirectorName(String director) {
    switch (director) {
      case 'lighting':
        return 'Lighting Director';
      case 'camera':
        return 'Camera Director';
      default:
        return director;
    }
  }
  
  void _executeCommand() {
    if (_command.isEmpty) return;
    
    // Parse: gl10.1
    final parts = _command.substring(1).split('.');
    if (parts.isEmpty) return;
    
    final tuner = DirectorTuner.instance;
    final directors = tuner.getDirectors();
    final dirChar = parts[0].isEmpty ? '' : parts[0][0];
    final matchingDir = directors.firstWhere(
      (d) => d.startsWith(dirChar),
      orElse: () => '',
    );
    
    if (matchingDir.isEmpty) return;
    
    final params = tuner.getParameters(matchingDir);
    if (params.isEmpty) return;
    
    String? paramName;
    
    if (parts.length == 1) {
      // gl10: navigate to param
      final paramIndex = int.tryParse(parts[0].substring(1)) ?? -1;
      if (paramIndex >= 0 && paramIndex < params.length) {
        paramName = params[paramIndex].name;
      }
    } else if (parts.length == 2) {
      // gl10.1: navigate to sub-param
      final paramIndex = int.tryParse(parts[0].substring(1)) ?? -1;
      final subIndex = int.tryParse(parts[1]) ?? -1;
      if (paramIndex >= 0 && paramIndex < params.length && subIndex >= 0 && subIndex < 3) {
        final param = params[paramIndex];
        final components = ['x', 'y', 'z'];
        paramName = '${param.name}.${components[subIndex]}';
      }
    }
    
    if (paramName != null && widget.onNavigate != null) {
      widget.onNavigate!(matchingDir, paramName);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Goto Command',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: const InputDecoration(
              hintText: 'gl10.1',
              hintStyle: TextStyle(color: Colors.white54),
              border: OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white54),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
            onSubmitted: (_) => _executeCommand(),
          ),
          if (_predictions.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._predictions.map((pred) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                pred,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            )),
          ],
        ],
      ),
    );
  }
}

