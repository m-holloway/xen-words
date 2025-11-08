import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/director_tuner.dart';
import '../models/tunable_parameter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Report overlay showing changed parameters from baseline
/// Designed for screenshot documentation
class DirectorReport extends StatefulWidget {
  final VoidCallback onDismiss;
  final void Function(String director, String paramName)? onNavigateToParam;
  final int selectedIndex;
  final ScrollController scrollController;
  
  const DirectorReport({
    Key? key,
    required this.onDismiss,
    this.onNavigateToParam,
    this.selectedIndex = 0,
    required this.scrollController,
  }) : super(key: key);
  
  @override
  State<DirectorReport> createState() => _DirectorReportState();
}

class _DirectorReportState extends State<DirectorReport> {
  // Track which memory slots are occupied
  final Map<int, bool> _slotOccupied = {1: false, 2: false, 3: false, 4: false};
  
  @override
  void initState() {
    super.initState();
    _checkSlotOccupancy();
    // Listen to tuner changes so the report updates when slots are loaded
    DirectorTuner.instance.addListener(_onTunerChanged);
  }
  
  @override
  void dispose() {
    DirectorTuner.instance.removeListener(_onTunerChanged);
    super.dispose();
  }
  
  void _onTunerChanged() {
    if (mounted) {
      setState(() {
        // Report will rebuild with updated values
      });
    }
  }
  
  Future<void> _checkSlotOccupancy() async {
    for (int i = 1; i <= 4; i++) {
      final occupied = await DirectorTuner.instance.isSlotOccupied(i);
      if (mounted) {
        setState(() {
          _slotOccupied[i] = occupied;
        });
      }
    }
  }
  
  /// Format a value for display based on its type
  String _formatValue(dynamic value, TunableParameter? param) {
    if (value is bool) {
      return value.toString();
    } else if (value is int) {
      return value.toString();
    } else if (value is double) {
      // For doubles, show 2-3 decimal places depending on the value
      if (value.abs() >= 1000) {
        return value.toStringAsFixed(1);
      } else if (value.abs() >= 100) {
        return value.toStringAsFixed(2);
      } else if (value.abs() >= 1) {
        return value.toStringAsFixed(3);
      } else {
        return value.toStringAsFixed(4);
      }
    }
    return value.toString();
  }
  
  @override
  Widget build(BuildContext context) {
    final tuner = DirectorTuner.instance;
    final changes = tuner.getChangedParameters();
    
    return Positioned(
      top: 20,
      right: 20,
      left: 20,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 600),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Press ↑/↓ to navigate, Enter to adjust, Esc to go back',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            const Text(
              'DIRECTOR TUNING REPORT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const Text(
              '══════════════════════',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            // Build flat list of all changed parameters for navigation
            Expanded(
              child: changes.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'No changes from baseline\n\nYou can still use persistence controls below to save current settings or load from slots.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final reportItems = <({String director, String paramName, dynamic currentValue, dynamic baseline, TunableParameter? param})>[];
                        for (final directorEntry in changes.entries) {
                          for (final paramEntry in directorEntry.value.entries) {
                            final param = tuner.getParameter(directorEntry.key, paramEntry.key);
                            reportItems.add((
                              director: directorEntry.key,
                              paramName: paramEntry.key,
                              currentValue: paramEntry.value,
                              baseline: tuner.getBaseline(directorEntry.key, paramEntry.key),
                              param: param,
                            ));
                          }
                        }
                        
                        return ListView.builder(
                          controller: widget.scrollController,
                          shrinkWrap: true,
                          itemCount: reportItems.length,
                          itemBuilder: (context, index) {
                            final item = reportItems[index];
                            final isSelected = index == widget.selectedIndex;
                            final formattedBaseline = _formatValue(item.baseline, item.param);
                            final formattedCurrent = _formatValue(item.currentValue, item.param);
                            
                            return InkWell(
                              onTap: widget.onNavigateToParam != null
                                  ? () => widget.onNavigateToParam!(item.director, item.paramName)
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.blue.withOpacity(0.3) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.director}.${item.paramName}: $formattedBaseline → $formattedCurrent',
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.white70,
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (widget.onNavigateToParam != null)
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 12,
                                        color: isSelected ? Colors.white : Colors.white54,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            const Text(
              '══════════════════════',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 6),
            // Persistence buttons
            const Text(
              'PERSISTENCE',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                TextButton(
                  onPressed: () => _saveAsDefaults(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Save Defaults', style: TextStyle(fontSize: 9)),
                ),
                TextButton(
                  onPressed: () => _showMemorySlotsDialog(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Slots...', style: TextStyle(fontSize: 9)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              '──────────────────────',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                TextButton(
                  onPressed: () => _exportJson(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Export', style: TextStyle(fontSize: 9)),
                ),
                TextButton(
                  onPressed: () => _copyToClipboard(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Copy', style: TextStyle(fontSize: 9)),
                ),
                TextButton(
                  onPressed: () {
                    tuner.resetAll();
                    widget.onDismiss();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reset All', style: TextStyle(fontSize: 9)),
                ),
                TextButton(
                  onPressed: widget.onDismiss,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Dismiss', style: TextStyle(fontSize: 9)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _exportJson(BuildContext context) async {
    try {
      final tuner = DirectorTuner.instance;
      final json = tuner.exportToJson();
      
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/director_tuning_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(json);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to ${file.path}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting: $e')),
        );
      }
    }
  }
  
  Future<void> _copyToClipboard(BuildContext context) async {
    try {
      final tuner = DirectorTuner.instance;
      final json = tuner.exportToJson();
      
      await Clipboard.setData(ClipboardData(text: json));
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error copying: $e')),
        );
      }
    }
  }
  
  Future<void> _saveAsDefaults(BuildContext context) async {
    try {
      await DirectorTuner.instance.saveAsDefaults();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Saved as defaults (will load on app startup)'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving defaults: $e')),
        );
      }
    }
  }
  
  void _showMemorySlotsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.black.withOpacity(0.9),
          title: const Text(
            'Memory Slots',
            style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 1; i <= 4; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Slot $i ${_slotOccupied[i] == true ? "●" : "○"}',
                            style: TextStyle(
                              color: _slotOccupied[i] == true ? Colors.green : Colors.white54,
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _saveToSlot(context, i, setDialogState),
                          child: const Text('Save', style: TextStyle(fontSize: 11)),
                        ),
                        if (_slotOccupied[i] == true)
                          TextButton(
                            onPressed: () => _loadFromSlot(context, i),
                            child: const Text('Load', style: TextStyle(fontSize: 11)),
                          ),
                        if (_slotOccupied[i] == true)
                          TextButton(
                            onPressed: () => _clearSlot(context, i, setDialogState),
                            child: const Text(
                              'Clear',
                              style: TextStyle(fontSize: 11, color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _saveToSlot(BuildContext context, int slotNumber, [void Function(void Function())? setDialogState]) async {
    try {
      await DirectorTuner.instance.saveToSlot(slotNumber);
      
      // Update slot occupancy
      final occupied = await DirectorTuner.instance.isSlotOccupied(slotNumber);
      if (mounted) {
        setState(() {
          _slotOccupied[slotNumber] = occupied;
        });
      }
      
      // Also update dialog if setState callback provided
      if (setDialogState != null) {
        setDialogState(() {
          _slotOccupied[slotNumber] = occupied;
        });
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Saved to memory slot $slotNumber'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving to slot $slotNumber: $e')),
        );
      }
    }
  }
  
  Future<void> _loadFromSlot(BuildContext context, int slotNumber) async {
    try {
      await DirectorTuner.instance.loadFromSlot(slotNumber);
      if (context.mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Loaded from memory slot $slotNumber'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading from slot $slotNumber: $e')),
        );
      }
    }
  }
  
  Future<void> _clearSlot(BuildContext context, int slotNumber, [void Function(void Function())? setDialogState]) async {
    try {
      await DirectorTuner.instance.clearSlot(slotNumber);
      
      // Update slot occupancy
      final occupied = await DirectorTuner.instance.isSlotOccupied(slotNumber);
      if (mounted) {
        setState(() {
          _slotOccupied[slotNumber] = occupied;
        });
      }
      
      // Also update dialog if setState callback provided
      if (setDialogState != null) {
        setDialogState(() {
          _slotOccupied[slotNumber] = occupied;
        });
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ Cleared memory slot $slotNumber'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing slot $slotNumber: $e')),
        );
      }
    }
  }
}

