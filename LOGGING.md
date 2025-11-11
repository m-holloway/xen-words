# Logging Best Practices for Xen Words

## Table of Contents
1. [Why Use Logging Instead of Print](#why-use-logging-instead-of-print)
2. [AppLogger Overview](#applogger-overview)
3. [Log Levels](#log-levels)
4. [Domain-Specific Loggers](#domain-specific-loggers)
5. [Usage Examples](#usage-examples)
6. [Configuration](#configuration)
7. [Performance Considerations](#performance-considerations)
8. [Debugging Workflows](#debugging-workflows)
9. [Quick Reference](#quick-reference)

---

## Why Use Logging Instead of Print

### ❌ Problems with `print()`

```dart
// ❌ BAD: Using print statements
print('Game started');
print('User score: $score');
print('Error loading audio: $error');
```

**Issues:**
1. **No context:** All messages look the same - can't distinguish errors from info
2. **No filtering:** Can't disable debug messages in production
3. **Performance impact:** Always executed, even when not needed
4. **Hard to search:** All prefixed with `flutter: `, no domain tags
5. **No severity levels:** Can't prioritize important messages
6. **Not production-ready:** Can't easily disable or redirect
7. **Cluttered console:** Excessive output makes debugging harder

### ✅ Benefits of `AppLogger`

```dart
// ✅ GOOD: Using AppLogger
AppLogger.game.i('Game started');
AppLogger.game.d('User score: $score');
AppLogger.audio.e('Error loading audio', error: error, stackTrace: stackTrace);
```

**Advantages:**
1. **Clear context:** Domain prefix (GAME, AUDIO) identifies source
2. **Severity levels:** trace, debug, info, warning, error, fatal
3. **Configurable:** Disable in production, adjust verbosity per environment
4. **Searchable:** Filter by domain: `flutter logs | grep AUDIO`
5. **Performance:** Minimal overhead when disabled
6. **Professional:** Clean, structured output
7. **Extensible:** Add custom loggers as needed

---

## AppLogger Overview

The `AppLogger` class (in `lib/utils/app_logger.dart`) provides a centralized, domain-organized logging system built on the `logger` package.

### Architecture

```
AppLogger (static class)
├── Configuration
│   ├── globalLevel: Level (trace, debug, info, warning, error, fatal)
│   ├── enabled: bool (toggle all logging)
│   ├── enablePerformanceLogging: bool (frame-by-frame updates)
│   └── enableLayoutDebug: bool (layout measurements)
│
├── Domain Loggers
│   ├── game: Game logic (words, progression, states)
│   ├── speech: Speech recognition (Sherpa-ONNX)
│   ├── audio: Sound effects and pronunciations
│   ├── rendering: 3D rendering (O3DE, textures)
│   ├── lighting: Lighting calculations
│   ├── animation: Character animations
│   ├── camera: Camera movements
│   ├── ui: UI interactions and layout
│   ├── layout: Layout debugging (measurements)
│   ├── network: Network requests
│   ├── storage: File I/O and caching
│   ├── performance: Performance metrics
│   └── system: App lifecycle, initialization
│
└── Methods
    ├── configureForEnvironment(isProduction, level)
    ├── setLevel(Level)
    ├── setEnabled(bool)
    └── setPerformanceLogging(bool)
```

---

## Log Levels

### Level Hierarchy (Low to High Severity)

```dart
Level.trace    // Very detailed, for debugging specific code paths
Level.debug    // Detailed info for development
Level.info     // General information (default in production)
Level.warning  // Warnings that don't prevent operation
Level.error    // Errors that should be investigated
Level.fatal    // Critical errors that may crash the app
```

### When to Use Each Level

#### TRACE (.t)
**Use for:** Frame-by-frame updates, very detailed debugging

```dart
AppLogger.rendering.t('Frame rendered at ${DateTime.now()}');
AppLogger.animation.t('Bone transform updated: $boneMatrix');
```

**Characteristics:**
- Most verbose
- Typically disabled even in debug builds
- Use only when actively debugging specific code paths

#### DEBUG (.d)
**Use for:** Development information, state changes, function calls

```dart
AppLogger.speech.d('⚡ Early recognition: "$text" (sequence: $sequence)');
AppLogger.game.d('Word transition: $oldWord → $newWord');
AppLogger.ui.d('Button pressed: $buttonId');
```

**Characteristics:**
- Default level in debug builds
- Helps understand app flow during development
- Disabled in release builds

#### INFO (.i)
**Use for:** Important application events, milestones

```dart
AppLogger.system.i('🚀 App starting in DEBUG mode');
AppLogger.game.i('📖 Displaying word 5: hello');
AppLogger.audio.i('🎵 Success audio complete, moving to next word');
```

**Characteristics:**
- Default level in production
- User-facing events (game progress, major state changes)
- Minimal performance impact

#### WARNING (.w)
**Use for:** Unexpected situations that don't break functionality

```dart
AppLogger.rendering.w('Texture quality reduced due to memory pressure');
AppLogger.audio.w('Pronunciation file not found, using fallback');
AppLogger.speech.w('Recognition confidence low: ${confidence}%');
```

**Characteristics:**
- Should be investigated but not critical
- May indicate degraded functionality
- Always logged in production

#### ERROR (.e)
**Use for:** Errors that prevent a feature from working

```dart
AppLogger.audio.e('Failed to load sound effect', error: e, stackTrace: st);
AppLogger.rendering.e('Failed to load 3D model', error: e, stackTrace: st);
AppLogger.speech.e('Sherpa-ONNX initialization failed', error: e);
```

**Characteristics:**
- **Always include `error` and `stackTrace` parameters**
- Feature broken, but app continues
- Requires attention and fixing

#### FATAL (.f)
**Use for:** Critical errors that will crash the app

```dart
AppLogger.system.f('Failed to initialize Flutter engine', error: e, stackTrace: st);
AppLogger.storage.f('Critical data corruption detected', error: e, stackTrace: st);
```

**Characteristics:**
- App cannot continue
- Rare - most errors should be recoverable
- Always logged, always investigated immediately

---

## Domain-Specific Loggers

### Available Loggers

#### `AppLogger.game`
**Game logic, word progression, scoring**

```dart
AppLogger.game.i('📖 Displaying word $index: $word');
AppLogger.game.i('✅ Correct word!');
AppLogger.game.i('🎉 Game completed!');
AppLogger.game.d('Score updated: $oldScore → $newScore');
```

#### `AppLogger.speech`
**Speech recognition (Sherpa-ONNX)**

```dart
AppLogger.speech.i('🎤 Starting continuous listening...');
AppLogger.speech.d('⚡ Early recognition: "$text"');
AppLogger.speech.i('📝 Result: $recognized, Expected: $expected');
AppLogger.speech.e('Recognition error', error: e, stackTrace: st);
```

#### `AppLogger.audio`
**Sound effects and word pronunciations**

```dart
AppLogger.audio.i('🎵 Playing sound effect: $effectName');
AppLogger.audio.i('🔊 Playing word pronunciation: $word');
AppLogger.audio.e('Failed to load audio file', error: e, stackTrace: st);
```

#### `AppLogger.rendering`
**3D rendering, textures, O3DE**

```dart
AppLogger.rendering.i('Initializing 3D scene');
AppLogger.rendering.t('Frame rendered: ${frameCount}');
AppLogger.rendering.w('Low memory: reducing texture quality');
AppLogger.rendering.e('Failed to load GLB model', error: e);
```

#### `AppLogger.lighting`
**Lighting calculations and updates**

```dart
AppLogger.lighting.d('Light updated: $lightName, intensity=$intensity');
AppLogger.lighting.d('Ambient light color: $color');
```

#### `AppLogger.animation`
**Character animations**

```dart
AppLogger.animation.d('🎬 Character animation: $state → "$animationName"');
AppLogger.animation.d('🎉 Random celebration animation selected: "$name"');
AppLogger.animation.i('ℹ️ Found ${count} celebration animations');
```

#### `AppLogger.camera`
**Camera movements and settings**

```dart
AppLogger.camera.d('Camera moving to position: $position');
AppLogger.camera.d('Camera FOV updated: $fov');
```

#### `AppLogger.ui`
**UI interactions and state**

```dart
AppLogger.ui.d('Button tapped: $buttonId');
AppLogger.ui.i('Dialog shown: $dialogType');
AppLogger.ui.t('Widget rebuilt: $widgetName');
```

#### `AppLogger.layout`
**Layout debugging and measurements**

```dart
AppLogger.layout.d('📐 Constraints: maxW=$maxWidth, maxH=$maxHeight');
AppLogger.layout.d('📦 Actual size: ${width} x ${height}');
AppLogger.layout.d('🎉 STACK actual size: ${stackWidth} x ${stackHeight}');
```

**Important:** Only use when `AppLogger.enableLayoutDebug = true`

#### `AppLogger.system`
**App lifecycle, initialization**

```dart
AppLogger.system.i('🚀 App starting in RELEASE mode');
AppLogger.system.i('App paused');
AppLogger.system.i('App resumed');
```

---

## Usage Examples

### Basic Logging

```dart
import '../utils/app_logger.dart';

class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    AppLogger.ui.d('Building MyWidget');
    
    return ElevatedButton(
      onPressed: () {
        AppLogger.ui.i('Button pressed');
        doSomething();
      },
      child: Text('Press Me'),
    );
  }
}
```

### Error Logging with Context

```dart
Future<void> loadAsset() async {
  try {
    AppLogger.storage.d('Loading asset: $assetPath');
    final data = await rootBundle.load(assetPath);
    AppLogger.storage.i('Asset loaded successfully: ${data.lengthInBytes} bytes');
  } catch (e, st) {
    AppLogger.storage.e(
      'Failed to load asset: $assetPath',
      error: e,
      stackTrace: st,
    );
    rethrow;
  }
}
```

### Conditional Logging for Performance

```dart
// ✅ GOOD: Guarded by flag
if (AppLogger.enablePerformanceLogging) {
  AppLogger.performance.t('Frame time: ${frameTime}ms');
}

// ❌ BAD: Always computed
AppLogger.performance.t('Frame time: ${expensiveCalculation()}ms');
// The expensive calculation runs even if logging is disabled!

// ✅ GOOD: Lazy evaluation
if (AppLogger.enabled && AppLogger.globalLevel.index <= Level.trace.index) {
  final result = expensiveCalculation();
  AppLogger.performance.t('Result: $result');
}
```

### State Transition Logging

```dart
void updateGameState(GameState newState) {
  final oldState = _currentState;
  _currentState = newState;
  
  AppLogger.game.i('State transition: $oldState → $newState');
  
  if (newState == GameState.celebrating) {
    AppLogger.game.d('🎉 Triggering celebration animation');
  } else if (newState == GameState.failing) {
    AppLogger.game.w('❌ Triggering failure animation');
  }
}
```

### Animation Logging

```dart
@override
void didUpdateWidget(MyWidget oldWidget) {
  super.didUpdateWidget(oldWidget);
  
  if (widget.gameState == GameState.celebrating && 
      oldWidget.gameState != GameState.celebrating) {
    AppLogger.animation.d('🎉 Starting celebration animation');
    _startCelebrationAnimation();
  }
}
```

---

## Configuration

### Environment-Based Configuration

In `lib/main.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'utils/app_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure logging based on build mode
  AppLogger.configureForEnvironment(
    isProduction: kReleaseMode,
    level: kReleaseMode 
      ? Level.info                    // Production: info and above
      : (kProfileMode 
          ? Level.info                // Profile: info and above
          : Level.debug),             // Debug: debug and above
  );
  
  AppLogger.system.i('🚀 App starting in ${
    kReleaseMode ? 'RELEASE' : (kProfileMode ? 'PROFILE' : 'DEBUG')
  } mode');
  
  runApp(const MyApp());
}
```

### Runtime Configuration Changes

```dart
// Disable all logging temporarily (performance testing)
AppLogger.setEnabled(false);
runPerformanceTest();
AppLogger.setEnabled(true);

// Change log level dynamically
AppLogger.setLevel(Level.trace); // Very verbose
doDetailedDebugging();
AppLogger.setLevel(Level.info);  // Back to normal

// Enable performance logging
AppLogger.setPerformanceLogging(true);
runAnimation();
AppLogger.setPerformanceLogging(false);

// Enable layout debugging
AppLogger.enableLayoutDebug = true;
testLayout();
AppLogger.enableLayoutDebug = false;
```

---

## Performance Considerations

### 1. Logging Has Zero Overhead When Disabled

```dart
// When AppLogger.enabled = false:
AppLogger.game.d('This message is never processed'); // No-op, instant return
```

The logger filter checks `enabled` flag **before** any string formatting or processing.

### 2. Avoid Expensive Operations in Log Messages

```dart
// ❌ BAD: Expensive operation always runs
AppLogger.game.d('Result: ${performHeavyCalculation()}');
// Calculation runs even if debug logging is disabled!

// ✅ GOOD: Guard with level check
if (AppLogger.enabled && AppLogger.globalLevel.index <= Level.debug.index) {
  final result = performHeavyCalculation();
  AppLogger.game.d('Result: $result');
}

// ✅ BETTER: Use a flag for very expensive operations
if (AppLogger.enablePerformanceLogging) {
  final result = performHeavyCalculation();
  AppLogger.performance.d('Result: $result');
}
```

### 3. Frame-by-Frame Logging

```dart
// ❌ BAD: Logs every frame (60+ times per second!)
@override
Widget build(BuildContext context) {
  AppLogger.ui.d('Building widget');
  return MyWidget();
}

// ✅ GOOD: Only log important rebuilds
@override
Widget build(BuildContext context) {
  if (AppLogger.enableLayoutDebug) {
    AppLogger.layout.d('Building widget: important state change');
  }
  return MyWidget();
}

// ✅ BETTER: Use postFrameCallback for measurements
@override
Widget build(BuildContext context) {
  if (AppLogger.enableLayoutDebug) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.layout.d('Widget size: ${renderBox.size}');
    });
  }
  return MyWidget();
}
```

### 4. Production Builds

In production (release mode):
- **Default level:** `Level.info`
- **Enabled:** `false` by default
- **Performance impact:** Near zero
- **Debug/trace logs:** Completely filtered out
- **Only critical logs:** Info, warning, error, fatal

---

## Debugging Workflows

### Workflow 1: Investigating a Crash

1. **Reproduce the crash** in debug mode
2. **Check error logs:**
   ```bash
   flutter logs | grep "ERROR\|FATAL"
   ```
3. **Trace the error** back through the logs:
   ```bash
   flutter logs | grep "GAME\|SPEECH" > debug.log
   ```
4. **Enable trace logging** for specific domain:
   ```dart
   AppLogger.setLevel(Level.trace);
   ```
5. **Reproduce** and analyze detailed logs
6. **Restore normal level** after fixing:
   ```dart
   AppLogger.setLevel(Level.debug);
   ```

### Workflow 2: Debugging Layout Issues

1. **Enable layout debugging** in `main.dart`:
   ```dart
   AppLogger.enableLayoutDebug = true;
   ```
2. **Add measurement points** in problematic widget:
   ```dart
   if (AppLogger.enableLayoutDebug) {
     WidgetsBinding.instance.addPostFrameCallback((_) {
       final box = _key.currentContext?.findRenderObject() as RenderBox?;
       AppLogger.layout.d('Size: ${box?.size}');
     });
   }
   ```
3. **Filter layout logs:**
   ```bash
   flutter logs | grep "LAYOUT"
   ```
4. **Analyze patterns:**
   - Unexpected size changes?
   - Unbounded constraints?
   - Parent/child size mismatch?
5. **Disable after fixing:**
   ```dart
   // AppLogger.enableLayoutDebug = true;
   ```

See `LAYOUT.md` for comprehensive layout debugging guide.

### Workflow 3: Performance Profiling

1. **Baseline measurement** (logging disabled):
   ```dart
   AppLogger.setEnabled(false);
   // Run performance test
   ```
2. **Enable performance logging:**
   ```dart
   AppLogger.enablePerformanceLogging = true;
   AppLogger.setLevel(Level.trace);
   ```
3. **Run specific scenario** and log metrics:
   ```dart
   final stopwatch = Stopwatch()..start();
   await performOperation();
   stopwatch.stop();
   AppLogger.performance.i('Operation took ${stopwatch.elapsedMilliseconds}ms');
   ```
4. **Analyze bottlenecks** in logs
5. **Disable after profiling:**
   ```dart
   AppLogger.enablePerformanceLogging = false;
   AppLogger.setLevel(Level.info);
   ```

### Workflow 4: Tracing State Changes

1. **Add state transition logs:**
   ```dart
   void setState(VoidCallback fn) {
     final oldState = _currentState;
     super.setState(fn);
     AppLogger.ui.d('State changed: $oldState → $_currentState');
   }
   ```
2. **Run scenario** and collect logs
3. **Trace backwards** from error to find root cause:
   ```bash
   flutter logs | grep "State changed" > state_trace.log
   ```

---

## Quick Reference

### Migration from Print to AppLogger

| Old (print) | New (AppLogger) |
|-------------|-----------------|
| `print('Starting...')` | `AppLogger.game.i('Starting...')` |
| `print('Debug: $value')` | `AppLogger.game.d('Value: $value')` |
| `print('Error: $e')` | `AppLogger.game.e('Error occurred', error: e, stackTrace: st)` |
| `debugPrint('Widget built')` | `AppLogger.ui.d('Widget built')` |

### Log Level Quick Guide

| Level | Method | Use Case | Example |
|-------|--------|----------|---------|
| TRACE | `.t()` | Frame-by-frame, very detailed | `AppLogger.rendering.t('Frame: $frameNum')` |
| DEBUG | `.d()` | Development info, state | `AppLogger.game.d('Score: $score')` |
| INFO | `.i()` | Important events | `AppLogger.game.i('Game started')` |
| WARNING | `.w()` | Unexpected but recoverable | `AppLogger.audio.w('File not found, using fallback')` |
| ERROR | `.e()` | Feature broken | `AppLogger.audio.e('Load failed', error: e, stackTrace: st)` |
| FATAL | `.f()` | App will crash | `AppLogger.system.f('Engine failed', error: e, stackTrace: st)` |

### Domain Selection Guide

| Domain | Use For |
|--------|---------|
| `game` | Word progression, scoring, game states |
| `speech` | Speech recognition, microphone, Sherpa-ONNX |
| `audio` | Sound effects, pronunciations |
| `rendering` | 3D models, textures, O3DE |
| `lighting` | Lights, shadows |
| `animation` | Character animations |
| `camera` | Camera position, FOV |
| `ui` | Button clicks, dialogs, user interactions |
| `layout` | Widget sizes, constraints (debug only) |
| `system` | App lifecycle, initialization |
| `performance` | Timing, profiling |
| `storage` | File I/O, caching |
| `network` | API calls, downloads |

### Configuration Quick Commands

```dart
// Disable all logging
AppLogger.setEnabled(false);

// Set to info level (production)
AppLogger.setLevel(Level.info);

// Set to debug level (development)
AppLogger.setLevel(Level.debug);

// Enable performance logging
AppLogger.enablePerformanceLogging = true;

// Enable layout debugging
AppLogger.enableLayoutDebug = true;
```

### Terminal Filtering Commands

```bash
# Filter by domain
flutter logs | grep "GAME"
flutter logs | grep "SPEECH"

# Filter by level
flutter logs | grep "ERROR"
flutter logs | grep "INFO"

# Filter by emoji
flutter logs | grep "🎉"  # Celebrations
flutter logs | grep "❌"  # Errors

# Filter layout logs
flutter logs | grep "LAYOUT\|📐\|📦\|🎉\|🖼️\|🎨"

# Multiple domains
flutter logs | grep "GAME\|SPEECH\|AUDIO"

# Save to file
flutter logs > app_logs.txt
```

---

## Additional Resources

- **Implementation:** `lib/utils/app_logger.dart`
- **Package:** [logger on pub.dev](https://pub.dev/packages/logger)
- **Layout Debugging:** See `LAYOUT.md`
- **Main README:** See `README.md` for project overview

---

**Last Updated:** 2025-11-11  
**Maintained by:** Xen Words Development Team

