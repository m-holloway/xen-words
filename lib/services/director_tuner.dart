import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tunable_parameter.dart';

/// Singleton service for managing Director parameter overrides
/// Provides runtime tuning without code changes or hot reload
class DirectorTuner extends ChangeNotifier {
  static final DirectorTuner _instance = DirectorTuner._internal();
  factory DirectorTuner() => _instance;
  DirectorTuner._internal();
  
  static DirectorTuner get instance => _instance;
  
  // Parameter registry: director -> param name -> TunableParameter
  final Map<String, Map<String, TunableParameter>> _parameters = {};
  
  // Runtime overrides: director -> param name -> value
  final Map<String, Map<String, dynamic>> _overrides = {};
  
  // Baseline values (defaults) for comparison
  final Map<String, Map<String, dynamic>> _baselines = {};
  
  // Toggle overlay signal
  final ValueNotifier<bool> overlayToggleSignal = ValueNotifier<bool>(false);
  
  /// Toggle the director overlay
  void toggleOverlay() {
    overlayToggleSignal.value = !overlayToggleSignal.value;
    print('🎹 DirectorTuner: toggleOverlay() called, signal value: ${overlayToggleSignal.value}');
  }
  
  /// Register a tunable parameter
  static void register(
    String director,
    String paramName, {
    required double min,
    required double max,
    required dynamic defaultValue,
    String? unit,
    String? description,
    ParameterType type = ParameterType.double,
  }) {
    final param = TunableParameter(
      name: paramName,
      director: director,
      type: type,
      min: min,
      max: max,
      defaultValue: defaultValue,
      unit: unit,
      description: description,
    );
    
    _instance._parameters.putIfAbsent(director, () => {})[paramName] = param;
    _instance._baselines.putIfAbsent(director, () => {})[paramName] = defaultValue;
  }
  
  /// Get a parameter value (override if exists, otherwise default)
  T getValue<T>(String director, String paramName, T defaultValue) {
    // Check for override first
    if (_overrides.containsKey(director) && 
        _overrides[director]!.containsKey(paramName)) {
      final value = _overrides[director]![paramName];
      if (value is T) return value;
      // Try to convert if needed
      if (T == double && value is int) return value.toDouble() as T;
      if (T == int && value is double) return value.toInt() as T;
    }
    
    // Return default
    return defaultValue;
  }
  
  /// Set a parameter override
  void setParameter(String director, String paramName, dynamic value) {
    // Validate parameter exists
    if (!_parameters.containsKey(director) || 
        !_parameters[director]!.containsKey(paramName)) {
      debugPrint('⚠️ Parameter $director.$paramName not registered');
      return;
    }
    
    final param = _parameters[director]![paramName]!;
    
    // Validate and clamp value
    if (!param.isValidValue(value)) {
      value = param.clampValue(value);
    }
    
    // Store override
    _overrides.putIfAbsent(director, () => {})[paramName] = value;
    
    // Notify listeners
    notifyListeners();
  }
  
  /// Reset a parameter to default
  void resetParameter(String director, String paramName) {
    if (_overrides.containsKey(director)) {
      _overrides[director]!.remove(paramName);
      if (_overrides[director]!.isEmpty) {
        _overrides.remove(director);
      }
      notifyListeners();
    }
  }
  
  /// Reset all parameters
  void resetAll() {
    _overrides.clear();
    notifyListeners();
  }
  
  // ==================================================================
  // 💾 PERSISTENCE - Save/Load overrides to SharedPreferences
  // ==================================================================
  
  static const String _keyDefaults = 'director_tuner_defaults';
  static const String _keySlot1 = 'director_tuner_slot1';
  static const String _keySlot2 = 'director_tuner_slot2';
  static const String _keySlot3 = 'director_tuner_slot3';
  static const String _keySlot4 = 'director_tuner_slot4';
  
  /// Load defaults from SharedPreferences on app startup
  Future<void> loadDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_keyDefaults);
      if (jsonString != null) {
        final Map<String, dynamic> data = jsonDecode(jsonString);
        _loadOverridesFromMap(data);
        print('✅ Loaded director defaults from SharedPreferences (${data.length} parameters)');
      } else {
        print('ℹ️  No saved director defaults found');
      }
    } catch (e) {
      print('⚠️ Error loading director defaults: $e');
    }
  }
  
  /// Save current overrides as defaults
  Future<void> saveAsDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final overrides = getOverrides();
      final jsonString = jsonEncode(overrides);
      await prefs.setString(_keyDefaults, jsonString);
      print('✅ Saved ${overrides.length} parameters as defaults:');
      overrides.forEach((key, value) => print('   $key: $value'));
    } catch (e) {
      print('⚠️ Error saving defaults: $e');
      rethrow;
    }
  }
  
  /// Save current overrides to a memory slot (1-4)
  Future<void> saveToSlot(int slotNumber) async {
    if (slotNumber < 1 || slotNumber > 4) {
      throw ArgumentError('Slot number must be 1-4');
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final overrides = getOverrides();
      final jsonString = jsonEncode(overrides);
      final key = _getSlotKey(slotNumber);
      await prefs.setString(key, jsonString);
      print('✅ Saved ${overrides.length} parameters to memory slot $slotNumber:');
      overrides.forEach((key, value) => print('   $key: $value'));
    } catch (e) {
      print('⚠️ Error saving to slot $slotNumber: $e');
      rethrow;
    }
  }
  
  /// Load overrides from a memory slot (1-4)
  Future<void> loadFromSlot(int slotNumber) async {
    if (slotNumber < 1 || slotNumber > 4) {
      throw ArgumentError('Slot number must be 1-4');
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getSlotKey(slotNumber);
      final jsonString = prefs.getString(key);
      
      if (jsonString != null) {
        final Map<String, dynamic> data = jsonDecode(jsonString);
        _loadOverridesFromMap(data);
        print('✅ Loaded memory slot $slotNumber (${data.length} parameters)');
      } else {
        print('ℹ️  Memory slot $slotNumber is empty');
      }
    } catch (e) {
      print('⚠️ Error loading from slot $slotNumber: $e');
      rethrow;
    }
  }
  
  /// Check if a memory slot has saved data
  Future<bool> isSlotOccupied(int slotNumber) async {
    if (slotNumber < 1 || slotNumber > 4) {
      return false;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getSlotKey(slotNumber);
      return prefs.containsKey(key);
    } catch (e) {
      return false;
    }
  }
  
  /// Clear a memory slot
  Future<void> clearSlot(int slotNumber) async {
    if (slotNumber < 1 || slotNumber > 4) {
      throw ArgumentError('Slot number must be 1-4');
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getSlotKey(slotNumber);
      await prefs.remove(key);
      print('✅ Cleared memory slot $slotNumber');
    } catch (e) {
      print('⚠️ Error clearing slot $slotNumber: $e');
      rethrow;
    }
  }
  
  /// Get the SharedPreferences key for a slot
  String _getSlotKey(int slotNumber) {
    switch (slotNumber) {
      case 1: return _keySlot1;
      case 2: return _keySlot2;
      case 3: return _keySlot3;
      case 4: return _keySlot4;
      default: throw ArgumentError('Invalid slot number: $slotNumber');
    }
  }
  
  /// Load overrides from a map (helper method)
  void _loadOverridesFromMap(Map<String, dynamic> data) {
    _overrides.clear();
    
    print('📥 Loading ${data.length} parameters:');
    for (final entry in data.entries) {
      // Parse "director.paramName" format
      final parts = entry.key.split('.');
      if (parts.length == 2) {
        final director = parts[0];
        final paramName = parts[1];
        _overrides.putIfAbsent(director, () => {})[paramName] = entry.value;
        print('   $director.$paramName: ${entry.value}');
      }
    }
    
    print('📊 Loaded into ${_overrides.length} director(s)');
    notifyListeners();
  }
  
  /// Get all registered directors
  List<String> getDirectors() {
    return _parameters.keys.toList()..sort();
  }
  
  /// Get all parameters for a director
  List<TunableParameter> getParameters(String director) {
    if (!_parameters.containsKey(director)) return [];
    return _parameters[director]!.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
  
  /// Get parameter metadata
  TunableParameter? getParameter(String director, String paramName) {
    return _parameters[director]?[paramName];
  }
  
  /// Check if a parameter has been overridden
  bool isOverridden(String director, String paramName) {
    return _overrides.containsKey(director) && 
           _overrides[director]!.containsKey(paramName);
  }
  
  /// Get all changed parameters (compared to baseline)
  Map<String, Map<String, dynamic>> getChangedParameters() {
    final changed = <String, Map<String, dynamic>>{};
    
    for (final director in _overrides.keys) {
      final directorChanges = <String, dynamic>{};
      for (final paramName in _overrides[director]!.keys) {
        final current = _overrides[director]![paramName];
        final baseline = _baselines[director]?[paramName];
        if (current != baseline) {
          directorChanges[paramName] = current;
        }
      }
      if (directorChanges.isNotEmpty) {
        changed[director] = directorChanges;
      }
    }
    
    return changed;
  }
  
  /// Get all current overrides in flat "director.paramName" format
  Map<String, dynamic> getOverrides() {
    final flat = <String, dynamic>{};
    for (final director in _overrides.keys) {
      for (final paramName in _overrides[director]!.keys) {
        flat['$director.$paramName'] = _overrides[director]![paramName];
      }
    }
    return flat;
  }
  
  /// Export current overrides to JSON
  String exportToJson() {
    final data = <String, dynamic>{};
    for (final director in _overrides.keys) {
      data[director] = Map<String, dynamic>.from(_overrides[director]!);
    }
    return const JsonEncoder.withIndent('  ').convert(data);
  }
  
  /// Import overrides from JSON
  void importFromJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      _overrides.clear();
      for (final director in data.keys) {
        final params = data[director] as Map<String, dynamic>;
        _overrides[director] = Map<String, dynamic>.from(params);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error importing JSON: $e');
    }
  }
  
  /// Get baseline value for a parameter
  dynamic getBaseline(String director, String paramName) {
    return _baselines[director]?[paramName];
  }
}

