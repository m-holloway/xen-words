import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/director_tuner.dart';
import '../models/tunable_parameter.dart';
import 'relative_touch_slider.dart';
import 'goto_command.dart';
import 'director_report.dart';

enum OverlayState {
  hidden,
  browse,
  adjust,
  goto,
  report,
}

/// Intent for toggling director overlay
class _ToggleDirectorIntent extends Intent {
  const _ToggleDirectorIntent();
}

/// Main director overlay widget with keyboard navigation
class DirectorOverlay extends StatefulWidget {
  final VoidCallback onValueChanged;
  final VoidCallback? onRefreshScene;
  
  const DirectorOverlay({
    Key? key,
    required this.onValueChanged,
    this.onRefreshScene,
  }) : super(key: key);
  
  @override
  State<DirectorOverlay> createState() => _DirectorOverlayState();
}

class _DirectorOverlayState extends State<DirectorOverlay> {
  OverlayState _state = OverlayState.hidden;
  OverlayState? _previousState; // Track previous state for back navigation
  String _currentDirector = '';
  int _selectedParamIndex = 0;
  int _selectedSubParam = 0; // 0=x, 1=y, 2=z
  int _selectedReportIndex = 0; // Selected index in report mode
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _reportScrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    print('🎹 DirectorOverlay: initState called');
    final tuner = DirectorTuner.instance;
    final directors = tuner.getDirectors();
    print('🎹 DirectorOverlay: Found ${directors.length} directors: $directors');
    if (directors.isNotEmpty) {
      _currentDirector = directors.first;
      print('🎹 DirectorOverlay: Initial director set to $_currentDirector');
    }
    
    // Listen to focus changes for debugging
    _focusNode.addListener(() {
      print('🎹 DirectorOverlay: Focus changed - hasFocus: ${_focusNode.hasFocus}, hasPrimaryFocus: ${_focusNode.hasPrimaryFocus}');
    });
    
    // Listen to toggle signal from DirectorTuner
    tuner.overlayToggleSignal.addListener(_onToggleSignal);
    
    // Try to request focus immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🎹 DirectorOverlay: Requesting initial focus');
      _focusNode.requestFocus();
    });
  }
  
  void _onToggleSignal() {
    print('🎹 DirectorOverlay: Toggle signal received! Current state: $_state');
    _toggleOverlay();
  }
  
  @override
  void dispose() {
    DirectorTuner.instance.overlayToggleSignal.removeListener(_onToggleSignal);
    _focusNode.dispose();
    _scrollController.dispose();
    _reportScrollController.dispose();
    super.dispose();
  }
  
  void _toggleOverlay() {
    setState(() {
      final wasHidden = _state == OverlayState.hidden;
      _state = wasHidden ? OverlayState.browse : OverlayState.hidden;
      print('🎹 DirectorOverlay: State changed to $_state');
      
      // Request focus when showing overlay
      if (wasHidden) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
          print('🎹 DirectorOverlay: Focus requested');
        });
      }
    });
  }
  
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Debug logging for all key events
    print('🎹 DirectorOverlay: Key event received - type: ${event.runtimeType}, logicalKey: ${event.logicalKey}, state: $_state');
    
    if (event is KeyDownEvent) {
      print('🎹 DirectorOverlay: KeyDownEvent - logicalKey: ${event.logicalKey}, keyLabel: ${event.logicalKey.keyLabel}');
      
      if (event.logicalKey == LogicalKeyboardKey.keyD) {
        print('🎹 DirectorOverlay: D key pressed! Toggling overlay from $_state');
        _toggleOverlay();
        return KeyEventResult.handled;
      } else if (_state == OverlayState.browse) {
        print('🎹 DirectorOverlay: Handling browse key');
        _handleBrowseKey(event);
        return KeyEventResult.handled;
      } else if (_state == OverlayState.adjust) {
        print('🎹 DirectorOverlay: Handling adjust key');
        _handleAdjustKey(event);
        return KeyEventResult.handled;
      } else if (_state == OverlayState.goto) {
        print('🎹 DirectorOverlay: Handling goto key');
        _handleGotoKey(event);
        return KeyEventResult.handled;
      } else if (_state == OverlayState.report) {
        print('🎹 DirectorOverlay: Handling report key');
        _handleReportKey(event);
        return KeyEventResult.handled;
      } else {
        print('🎹 DirectorOverlay: Key ignored (overlay is hidden)');
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.ignored;
  }
  
  void _scrollToSelected() {
    // Scroll to selected item after a brief delay to ensure the widget tree is updated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _selectedParamIndex >= 0) {
        final tuner = DirectorTuner.instance;
        final params = tuner.getParameters(_currentDirector);
        
        if (_selectedParamIndex < params.length) {
          // Estimate item height more accurately
          // Each item has padding (8*2 = 16) + text content (~40-60px depending on description)
          const baseItemHeight = 50.0;
          const itemWithDescriptionHeight = 70.0;
          
          // Calculate cumulative height up to selected item
          double targetOffset = 0.0;
          for (int i = 0; i < _selectedParamIndex; i++) {
            final param = params[i];
            // Items with descriptions are taller
            targetOffset += param.description != null ? itemWithDescriptionHeight : baseItemHeight;
          }
          
          // Get viewport height to center the item
          final viewportHeight = _scrollController.position.viewportDimension;
          final itemHeight = params[_selectedParamIndex].description != null 
              ? itemWithDescriptionHeight 
              : baseItemHeight;
          
          // Center the selected item in the viewport
          final centeredOffset = (targetOffset + itemHeight / 2) - (viewportHeight / 2);
          
          // Scroll to show the selected item, clamped to valid range
          _scrollController.animateTo(
            centeredOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }
  
  void _handleBrowseKey(KeyEvent event) {
    print('🎹 DirectorOverlay: _handleBrowseKey - logicalKey: ${event.logicalKey}');
    final tuner = DirectorTuner.instance;
    final directors = tuner.getDirectors();
    final params = tuner.getParameters(_currentDirector);
    
    if (event.logicalKey == LogicalKeyboardKey.tab || 
        event.logicalKey == LogicalKeyboardKey.keyM) {
      // Cycle modes
      final currentIndex = directors.indexOf(_currentDirector);
      final nextIndex = (currentIndex + 1) % directors.length;
      setState(() {
        _currentDirector = directors[nextIndex];
        _selectedParamIndex = 0;
      });
      _scrollToSelected();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      // Navigate up
      setState(() {
        _selectedParamIndex = (_selectedParamIndex - 1).clamp(0, params.length - 1);
      });
      _scrollToSelected();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      // Navigate down
      setState(() {
        _selectedParamIndex = (_selectedParamIndex + 1).clamp(0, params.length - 1);
      });
      _scrollToSelected();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      // Cycle sub-settings left
      setState(() {
        _selectedSubParam = (_selectedSubParam - 1).clamp(0, 2);
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      // Cycle sub-settings right
      setState(() {
        _selectedSubParam = (_selectedSubParam + 1).clamp(0, 2);
      });
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      // Enter adjust mode
      setState(() {
        _previousState = _state; // Save current state
        _state = OverlayState.adjust;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.keyG) {
      // Enter goto mode
      setState(() {
        _previousState = _state; // Save current state
        _state = OverlayState.goto;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
      // Toggle report
      setState(() {
        if (_state == OverlayState.report) {
          _state = OverlayState.browse;
          _previousState = null;
          _selectedReportIndex = 0;
        } else {
          _previousState = _state; // Save current state
          _selectedReportIndex = 0; // Reset selection
          _state = OverlayState.report;
        }
      });
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Close overlay
      setState(() {
        _state = OverlayState.hidden;
      });
    }
  }
  
  void _handleAdjustKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Go back to previous state, or browse if no previous state
      setState(() {
        _state = _previousState ?? OverlayState.browse;
        _previousState = null; // Clear previous state
        print('🎹 DirectorOverlay: Back pressed, returning to $_state');
      });
    } else if (event.logicalKey == LogicalKeyboardKey.delete ||
               event.logicalKey == LogicalKeyboardKey.backspace) {
      // Reset parameter to default value
      final tuner = DirectorTuner.instance;
      final params = tuner.getParameters(_currentDirector);
      if (_selectedParamIndex >= 0 && _selectedParamIndex < params.length) {
        final param = params[_selectedParamIndex];
        print('🎹 DirectorOverlay: Resetting ${param.name} to default value: ${param.defaultValue}');
        tuner.resetParameter(_currentDirector, param.name);
        widget.onValueChanged();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      // Coarse adjustment
      _adjustParameter(0.1);
    } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      // Coarse adjustment down
      _adjustParameter(-0.1);
    } else if (event.logicalKey == LogicalKeyboardKey.equal || 
               event.logicalKey == LogicalKeyboardKey.numpadAdd) {
      // Fine adjustment up
      _adjustParameter(0.01);
    } else if (event.logicalKey == LogicalKeyboardKey.minus || 
               event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      // Fine adjustment down
      _adjustParameter(-0.01);
    }
  }
  
  void _handleGotoKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _state = OverlayState.browse;
      });
    }
  }
  
  void _handleReportKey(KeyEvent event) {
    final tuner = DirectorTuner.instance;
    final changes = tuner.getChangedParameters();
    
    // Build flat list of all changed parameters for navigation
    final reportItems = <MapEntry<String, MapEntry<String, dynamic>>>[];
    for (final directorEntry in changes.entries) {
      for (final paramEntry in directorEntry.value.entries) {
        reportItems.add(MapEntry(directorEntry.key, paramEntry));
      }
    }
    
    if (event.logicalKey == LogicalKeyboardKey.escape || 
        event.logicalKey == LogicalKeyboardKey.keyR) {
      setState(() {
        _state = OverlayState.browse;
        _previousState = null;
        _selectedReportIndex = 0;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      // Navigate up
      setState(() {
        _selectedReportIndex = (_selectedReportIndex - 1).clamp(0, reportItems.length - 1);
      });
      _scrollReportToSelected();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      // Navigate down
      setState(() {
        _selectedReportIndex = (_selectedReportIndex + 1).clamp(0, reportItems.length - 1);
      });
      _scrollReportToSelected();
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      // Enter adjust mode for selected parameter
      if (_selectedReportIndex >= 0 && _selectedReportIndex < reportItems.length) {
        final item = reportItems[_selectedReportIndex];
        _navigateToAdjust(item.key, item.value.key);
      }
    }
  }
  
  void _scrollReportToSelected() {
    // Scroll to selected item after a brief delay to ensure the widget tree is updated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_reportScrollController.hasClients && _selectedReportIndex >= 0) {
        // Estimate item height
        const estimatedItemHeight = 20.0;
        final targetOffset = _selectedReportIndex * estimatedItemHeight;
        
        // Get viewport height to center the item
        final viewportHeight = _reportScrollController.position.viewportDimension;
        final centeredOffset = (targetOffset + estimatedItemHeight / 2) - (viewportHeight / 2);
        
        // Scroll to show the selected item, clamped to valid range
        _reportScrollController.animateTo(
          centeredOffset.clamp(0.0, _reportScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  void _adjustParameter(double delta) {
    final tuner = DirectorTuner.instance;
    final params = tuner.getParameters(_currentDirector);
    if (_selectedParamIndex >= 0 && _selectedParamIndex < params.length) {
      final param = params[_selectedParamIndex];
      final currentValue = tuner.getValue(_currentDirector, param.name, param.defaultValue);
      
      // Handle boolean parameters differently
      if (param.type == ParameterType.bool) {
        // Toggle boolean value
        final newValue = !(currentValue as bool);
        tuner.setParameter(_currentDirector, param.name, newValue);
        widget.onValueChanged();
        return;
      }
      
      // Handle integer parameters - always adjust by 1
      if (param.type == ParameterType.int) {
        final intValue = (currentValue is num ? currentValue : param.defaultValue as num).toInt();
        final step = delta > 0 ? 1 : -1; // Always step by 1 for integers
        final newValue = (intValue + step).clamp(param.min.toInt(), param.max.toInt());
        tuner.setParameter(_currentDirector, param.name, newValue);
        widget.onValueChanged();
        return;
      }
      
      // Handle double parameters with adaptive step sizing
      final numValue = currentValue is num ? currentValue : (param.defaultValue as num);
      final range = param.max - param.min;
      
      // Calculate adaptive step size for better precision across all ranges
      // Use smaller steps for small ranges, reasonable steps for large ranges
      double step;
      
      if (range <= 1.0) {
        // Small range (0-1): use percentage of range
        step = delta * range;
      } else if (range <= 10.0) {
        // Medium range (1-10): use 1% of range for fine, 10% for coarse
        step = delta * range;
      } else if (range <= 100.0) {
        // Larger range (10-100): cap step size to reasonable value
        // 0.01 delta (fine) = 0.1-1.0 step, 0.1 delta (coarse) = 1-10 step
        step = delta * math.min(range, 100.0);
      } else {
        // Very large range (100+): use logarithmic-ish scaling
        // Make adjustments proportional to current value magnitude, but with min/max bounds
        final magnitude = math.max(numValue.abs(), 1.0);
        final baseStep = delta * magnitude;
        
        // Clamp step to reasonable bounds (0.5% to 5% of range)
        final minStep = range * 0.005;
        final maxStep = range * 0.05;
        step = baseStep.clamp(minStep, maxStep);
      }
      
      final newValue = (numValue + step).clamp(param.min, param.max);
      tuner.setParameter(_currentDirector, param.name, newValue);
      widget.onValueChanged();
    }
  }
  
  void _navigateToParam(String director, String paramName) {
    final tuner = DirectorTuner.instance;
    final params = tuner.getParameters(director);
    final index = params.indexWhere((p) => p.name == paramName);
    if (index >= 0) {
      setState(() {
        _currentDirector = director;
        _selectedParamIndex = index;
        _state = OverlayState.browse;
      });
    }
  }
  
  /// Navigate to adjust mode for a specific parameter (from report)
  void _navigateToAdjust(String director, String paramName) {
    final tuner = DirectorTuner.instance;
    final params = tuner.getParameters(director);
    final index = params.indexWhere((p) => p.name == paramName);
    if (index >= 0) {
      setState(() {
        _previousState = _state; // Save current state (report)
        _currentDirector = director;
        _selectedParamIndex = index;
        _state = OverlayState.adjust;
        print('🎹 DirectorOverlay: Navigating to adjust mode for $director.$paramName');
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    print('🎹 DirectorOverlay: build() called, state: $_state');
    
    // Use Shortcuts widget for reliable keyboard handling
    // Always render it so it can receive key events even when hidden
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyD): _ToggleDirectorIntent(),
      },
      child: Actions(
        actions: {
          _ToggleDirectorIntent: CallbackAction<_ToggleDirectorIntent>(
            onInvoke: (_) {
              print('🎹 DirectorOverlay: Shortcut triggered! Toggling overlay');
              _toggleOverlay();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _focusNode,
          canRequestFocus: true,
          skipTraversal: false,
          onKeyEvent: _handleKeyEvent,
          child: Builder(
            builder: (context) {
              print('🎹 DirectorOverlay: Builder called, hasFocus: ${_focusNode.hasFocus}');
              
              // In adjust mode, use very transparent background so scene is visible
              // In other modes, use darker background for UI visibility
              final backgroundColor = _state == OverlayState.adjust
                  ? Colors.black.withOpacity(0.05) // Almost transparent
                  : Colors.black.withOpacity(0.85); // Dark for UI visibility
              
              return _state == OverlayState.hidden
                  ? const SizedBox.shrink()
                  : GestureDetector(
                      onTap: () {
                        print('🎹 DirectorOverlay: Tap detected, requesting focus');
                        _focusNode.requestFocus();
                      },
                      child: Container(
                        color: backgroundColor,
                        child: Stack(
                          children: [
                            if (_state == OverlayState.browse)
                              _buildBrowseView()
                            else if (_state == OverlayState.adjust)
                              _buildAdjustView()
                            else if (_state == OverlayState.goto)
                              _buildGotoView()
                            else if (_state == OverlayState.report)
                              _buildReportView(),
                          ],
                        ),
                      ),
                    );
            },
          ),
        ),
      ),
    );
  }
  
  Widget _buildBrowseView() {
    final tuner = DirectorTuner.instance;
    final params = tuner.getParameters(_currentDirector);
    
    return Positioned(
      top: 50,
      left: 50,
      right: 50,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Director: $_currentDirector',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: params.length,
                itemBuilder: (context, index) {
                  final param = params[index];
                  final isSelected = index == _selectedParamIndex;
                  final currentValue = tuner.getValue(
                    _currentDirector,
                    param.name,
                    param.defaultValue,
                  );
                  
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedParamIndex = index;
                        _state = OverlayState.adjust;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue.withOpacity(0.3) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  param.name,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                if (param.description != null)
                                  Text(
                                    param.description!,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 10,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            flex: 1,
                            child: Text(
                              _formatValue(currentValue, param),
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white60,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '↑/↓: Navigate | ←/→: Sub-params | Enter: Adjust | G: Goto | R: Report | Esc: Close',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAdjustView() {
    final tuner = DirectorTuner.instance;
    final params = tuner.getParameters(_currentDirector);
    
    if (_selectedParamIndex < 0 || _selectedParamIndex >= params.length) {
      return _buildBrowseView();
    }
    
    final param = params[_selectedParamIndex];
    
    return RelativeTouchSlider(
      director: _currentDirector,
      paramName: param.name,
      parameter: param,
      onValueChanged: widget.onValueChanged,
    );
  }
  
  Widget _buildGotoView() {
    return Center(
      child: GotoCommand(
        onNavigate: _navigateToParam,
      ),
    );
  }
  
  Widget _buildReportView() {
    return DirectorReport(
      selectedIndex: _selectedReportIndex,
      scrollController: _reportScrollController,
      onDismiss: () {
        setState(() {
          _state = OverlayState.browse;
          _previousState = null;
          _selectedReportIndex = 0;
        });
      },
      onNavigateToParam: _navigateToAdjust,
    );
  }
  
  String _formatValue(dynamic value, TunableParameter param) {
    if (value is bool) {
      return value.toString();
    } else if (value is num) {
      if (param.type == ParameterType.int) {
        return value.round().toString();
      }
      return value.toStringAsFixed(2);
    }
    return value.toString();
  }
}

