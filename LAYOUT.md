# Flutter Layout Guide for Xen Words

## Table of Contents
1. [Overview](#overview)
2. [Cross-Platform Considerations](#cross-platform-considerations)
3. [Performance-First Layout Principles](#performance-first-layout-principles)
4. [Common Layout Patterns](#common-layout-patterns)
5. [Special Cases: Scaling Animations](#special-cases-scaling-animations)
6. [Memory Management](#memory-management)
7. [Debugging Layout Issues](#debugging-layout-issues)
8. [Quick Reference](#quick-reference)

---

## Overview

This guide documents layout best practices for the Xen Words app, with emphasis on:
- **Cross-platform compatibility** (iOS, Android, tablets)
- **Memory efficiency** (critical on iOS with 2GB limits)
- **Runtime performance** (60fps+ animations)
- **Maintainability** (clear, debuggable widget trees)

### Key Philosophy
> Use the **simplest widget** that achieves the goal. Complex nested layouts increase memory, reduce performance, and make debugging harder.

---

## Cross-Platform Considerations

### Screen Sizes and Orientations
```dart
// ✅ GOOD: Responsive sizing using LayoutBuilder
LayoutBuilder(
  builder: (context, constraints) {
    final screenWidth = constraints.maxWidth;
    final margin = (screenWidth * 0.05).clamp(16.0, 40.0);
    final padding = (screenWidth * 0.08).clamp(20.0, 40.0);
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: margin),
      padding: EdgeInsets.symmetric(horizontal: padding),
      // ...
    );
  },
)

// ❌ BAD: Fixed pixel values
Container(
  margin: EdgeInsets.symmetric(horizontal: 40), // Won't adapt to small screens
  padding: EdgeInsets.symmetric(horizontal: 40),
)
```

### Device-Specific Adaptations
```dart
// Use MediaQuery for device capabilities
final mediaQuery = MediaQuery.of(context);
final isTablet = mediaQuery.size.shortestSide >= 600;
final pixelRatio = mediaQuery.devicePixelRatio;

// Adjust font sizes for tablets
final fontSize = isTablet ? 100.0 : 80.0;
```

### Safe Areas
```dart
// Always respect safe areas for iOS notches and Android gestures
SafeArea(
  child: YourWidget(),
)
```

---

## Performance-First Layout Principles

### 1. Minimize Widget Rebuilds
```dart
// ✅ GOOD: Specific AnimatedBuilder listens to only necessary controllers
AnimatedBuilder(
  animation: Listenable.merge([_controller1, _controller2]),
  builder: (context, child) {
    // Only rebuilds when animations change
    return Transform.scale(scale: _controller1.value, child: child);
  },
  child: ExpensiveWidget(), // Built once, reused
)

// ❌ BAD: Entire widget tree rebuilds on every setState
setState(() {
  _animationValue = newValue;
});
```

### 2. Use `const` Constructors
```dart
// ✅ GOOD: const widgets are never rebuilt
const Text('Hello', style: TextStyle(fontSize: 20))

// ❌ BAD: New widget instance on every build
Text('Hello', style: TextStyle(fontSize: 20))
```

### 3. Avoid Expensive Operations in `build()`
```dart
// ❌ BAD: Calculations in build method
Widget build(BuildContext context) {
  final expensiveResult = performHeavyCalculation(); // Called every frame!
  return Text(expensiveResult);
}

// ✅ GOOD: Cache calculated values
String? _cachedResult;

void _updateResult() {
  _cachedResult = performHeavyCalculation();
  setState(() {});
}

Widget build(BuildContext context) {
  return Text(_cachedResult ?? '');
}
```

### 4. Constrain Infinite Dimensions Early
```dart
// ✅ GOOD: Provide bounded constraints upfront
SizedBox(
  width: 400,
  height: 600,
  child: ListView(...), // Has bounded constraints
)

// ❌ BAD: ListView in Column with unbounded height
Column(
  children: [
    ListView(...), // ERROR: Unbounded height!
  ],
)
```

---

## Common Layout Patterns

### Pattern 1: Center Content with Responsive Sizing
```dart
// Use case: Word display box that adapts to content but stays centered
Center(
  child: Container(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.of(context).size.width * 0.8,
      maxHeight: 300,
    ),
    child: ContentWidget(),
  ),
)
```

### Pattern 2: Stack with Visual Overflow
```dart
// Use case: Animation effects that extend beyond parent bounds
Stack(
  alignment: Alignment.center,
  clipBehavior: Clip.none, // ⚠️ Allows visual overflow
  children: [
    // Main content - defines Stack size
    Container(
      width: 200,
      height: 100,
      child: MainContent(),
    ),
    // Overlay effect - can render outside Stack bounds
    Positioned.fill(
      child: OverlayEffect(),
    ),
  ],
)
```

### Pattern 3: Responsive Layout with LayoutBuilder
```dart
// Use case: Different layouts for different screen sizes
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth > 600) {
      return WideLayout(); // Tablet/desktop
    } else {
      return NarrowLayout(); // Phone
    }
  },
)
```

### Pattern 4: Scrollable Content with Fixed Header
```dart
// Use case: Game screen with fixed UI elements
Column(
  children: [
    // Fixed header
    Container(height: 100, child: Header()),
    // Scrollable content
    Expanded(
      child: SingleChildScrollView(
        child: GameContent(),
      ),
    ),
  ],
)
```

---

## Special Cases: Scaling Animations

### Problem: Animated Outlines Affecting Layout

When animating scaling effects (like celebration outlines), you need to:
1. **Visually render** the scaled effect outside parent bounds
2. **Prevent the effect** from participating in layout calculations
3. **Avoid expanding** parent containers

### Solution: Positioned.fill + Clip.none

```dart
// ✅ CORRECT: Celebration animation with scaling outline
Stack(
  alignment: Alignment.center,
  clipBehavior: Clip.none, // Visual overflow allowed
  children: [
    // This child defines the Stack's layout size
    Container(
      padding: EdgeInsets.all(24),
      child: Text('WORD'), // Stack sizes to this
    ),
    
    // Scaled outline - does NOT affect Stack size
    Positioned.fill(
      child: Transform.translate(
        offset: Offset(0, floatUpOffset),
        child: Transform.scale(
          scale: 2.5, // Can scale beyond Stack bounds
          child: Opacity(
            opacity: fadeOpacity,
            child: OutlineEffect(),
          ),
        ),
      ),
    ),
  ],
)
```

### Key Insights

**Why Positioned.fill works:**
- `Positioned` widgets are **excluded from Stack's intrinsic size calculation**
- Stack sizes itself based on **non-positioned children only**
- Positioned children receive the Stack's size as constraints
- `clipBehavior: Clip.none` allows visual rendering beyond bounds

**Why this matters:**
- Parent Container **doesn't expand** to accommodate the scaled outline
- Outline receives **bounded constraints** (Stack's size), not infinite
- CustomPaint inside outline gets **reasonable dimensions** (e.g., 200x150, not 2000x1000)
- **Memory usage** stays low (91% reduction vs unbounded)

### Common Mistakes

```dart
// ❌ BAD: Transform on non-positioned child
Stack(
  children: [
    Transform.scale(
      scale: 2.5, // Stack sizes to this scaled child!
      child: Outline(),
    ),
    Text('WORD'),
  ],
)
// Result: Stack becomes huge, parent Container expands

// ❌ BAD: IgnorePointer without Positioned
Stack(
  children: [
    IgnorePointer(
      child: Transform.scale(
        scale: 2.5,
        child: Outline(), // Still participates in layout!
      ),
    ),
    Text('WORD'),
  ],
)
// Result: IgnorePointer only affects hit-testing, not layout

// ✅ GOOD: Positioned.fill isolates from layout
Stack(
  clipBehavior: Clip.none,
  children: [
    Text('WORD'), // Defines Stack size
    Positioned.fill(
      child: Transform.scale(
        scale: 2.5,
        child: Outline(), // Excluded from layout
      ),
    ),
  ],
)
```

---

## Memory Management

### 1. CustomPaint Size Constraints

**Problem:** Large CustomPaint surfaces consume massive memory during rasterization.

```dart
// ❌ BAD: Unbounded CustomPaint (memory crash on iOS)
LayoutBuilder(
  builder: (context, constraints) {
    return CustomPaint(
      size: Size(
        constraints.maxWidth.isFinite ? constraints.maxWidth : 2000, // 2000!
        constraints.maxHeight.isFinite ? constraints.maxHeight : 1000, // 1000!
      ),
      painter: OutlinePainter(),
    );
  },
)
// Memory: 2000 × 1000 × 4 bytes/pixel × devicePixelRatio² 
// = ~24MB for 3x display (iPhone)

// ✅ GOOD: Bounded CustomPaint
LayoutBuilder(
  builder: (context, constraints) {
    return CustomPaint(
      size: Size(
        constraints.maxWidth.clamp(100, 800),  // Bounded
        constraints.maxHeight.clamp(100, 300), // Bounded
      ),
      painter: OutlinePainter(),
    );
  },
)
// Memory: 800 × 300 × 4 bytes × 9 = ~8.6MB (71% reduction)
```

### 2. Image Texture Sizing

**Problem:** Large textures (e.g., for 3D model textures) can exceed memory limits.

```dart
// ❌ BAD: Full resolution texture (memory crash)
final recorder = ui.PictureRecorder();
final canvas = Canvas(recorder);
final textureSize = 1024; // 1024×1024 = 4MB per texture

// ✅ GOOD: Reduced resolution (cache and reuse)
final recorder = ui.PictureRecorder();
final canvas = Canvas(recorder);
final textureSize = 512; // 512×512 = 1MB per texture (75% reduction)

// Even better: Check if cached version exists
final cacheFile = File('${tempDir.path}/cached_texture.png');
if (await cacheFile.exists()) {
  return await loadCachedTexture(cacheFile);
}
```

### 3. Animation Frame Optimization

```dart
// ✅ GOOD: Use AnimationController properly
_controller = AnimationController(
  vsync: this, // Syncs to display refresh rate
  duration: Duration(milliseconds: 1800),
);

// Dispose properly to prevent leaks
@override
void dispose() {
  _controller.dispose();
  super.dispose();
}
```

---

## Debugging Layout Issues

### Step 1: Enable Layout Debug Logging

In `lib/main.dart`:
```dart
void main() async {
  // ...
  
  // Enable layout debugging
  AppLogger.enableLayoutDebug = true;
  
  runApp(const XenWordsApp());
}
```

### Step 2: Add Measurement Points

In your widget file:
```dart
import '../utils/app_logger.dart';

// Add GlobalKeys for measurement
final GlobalKey _containerKey = GlobalKey();
final GlobalKey _stackKey = GlobalKey();

Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      // Log incoming constraints
      if (AppLogger.enableLayoutDebug) {
        AppLogger.layout.d('📐 Constraints: maxW=${constraints.maxWidth}, maxH=${constraints.maxHeight}');
      }
      
      // Schedule postFrameCallback to measure actual size
      if (AppLogger.enableLayoutDebug) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final renderBox = _containerKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            AppLogger.layout.d('📦 Actual size: ${renderBox.size.width} x ${renderBox.size.height}');
          }
        });
      }
      
      return Container(
        key: _containerKey,
        child: YourWidget(),
      );
    },
  );
}
```

### Step 3: Analyze Log Patterns

**Filter logs in terminal:**
```bash
flutter logs | grep "LAYOUT"
```

**What to look for:**

1. **Unexpected Size Changes**
   ```
   📦 CONTAINER actual size: 200.0 x 150.0, celebrating=false
   📦 CONTAINER actual size: 375.0 x 150.0, celebrating=true  ← Expanded!
   ```
   **Diagnosis:** Container expands during celebration → Child affecting layout

2. **Unbounded Constraints**
   ```
   📐 OUTER LayoutBuilder constraints: maxW=375.0, maxH=Infinity
   🎨 CUSTOMPAINT size: 375.0 x 1000.0  ← Taking infinite height!
   ```
   **Diagnosis:** CustomPaint using fallback size → Add bounded constraints

3. **Stack Size vs Children**
   ```
   🎉 STACK actual size: 2000.0 x 1000.0, scale=2.40
   📦 CONTAINER actual size: 2100.0 x 1100.0
   ```
   **Diagnosis:** Stack's large child (outline) participating in layout → Use Positioned.fill

### Step 4: Common Fixes

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Container expands to full width | Child requesting unbounded width | Wrap in `Center()` or `Align()` |
| "Stack requires bounded constraints" | Stack in Column/ListView without size | Wrap Stack in `SizedBox` with height |
| CustomPaint too large | LayoutBuilder defaulting to huge size | Clamp CustomPaint size: `.clamp(min, max)` |
| Animation affects layout | Scaled widget participating in Stack | Use `Positioned.fill` for scaled child |
| Memory spike during animation | Large CustomPaint surfaces | Reduce canvas size, cache if possible |

### Step 5: Disable Debug Logging

After fixing, comment out in `main.dart`:
```dart
// AppLogger.enableLayoutDebug = true;
```

**Important:** Layout debug logging is **very verbose** and impacts performance. Only enable when actively debugging layout issues.

---

## Quick Reference

### Widget Selection Flowchart

```
Need to position widgets overlapping?
├─ YES → Stack (with clipBehavior: Clip.none for overflow effects)
└─ NO → Continue

Need dynamic sizing based on parent?
├─ YES → LayoutBuilder
└─ NO → Continue

Need scrolling?
├─ YES → SingleChildScrollView or ListView
└─ NO → Continue

Need to center content?
├─ YES → Center or Align
└─ NO → Continue

Need responsive margins/padding?
├─ YES → Container with LayoutBuilder for calculations
└─ NO → Container with fixed values

Need animation?
├─ YES → AnimatedBuilder + AnimationController
└─ NO → Regular widget
```

### Performance Checklist

- [ ] Use `const` constructors where possible
- [ ] Minimize widget rebuilds (use AnimatedBuilder, not setState in parent)
- [ ] Cache expensive calculations outside `build()`
- [ ] Constrain infinite dimensions early (ListView, GridView, Stack)
- [ ] Use `RepaintBoundary` for complex animating widgets
- [ ] Dispose AnimationControllers in `dispose()`
- [ ] Clamp CustomPaint sizes to reasonable bounds
- [ ] Use `clipBehavior: Clip.none` sparingly (expensive)

### Memory Checklist

- [ ] CustomPaint size < 1000×1000 pixels
- [ ] Texture sizes ≤ 512×512 for mobile
- [ ] Cache generated assets (textures, GLB files)
- [ ] Check for memory leaks (undisposed controllers/streams)
- [ ] Test on iOS (stricter 2GB memory limit)
- [ ] Profile memory usage during animations

### Cross-Platform Checklist

- [ ] Use `MediaQuery.of(context).size` for screen dimensions
- [ ] Use `.clamp(min, max)` for responsive sizing
- [ ] Test on both orientations (portrait, landscape)
- [ ] Test on smallest target device (iPhone SE) and largest (iPad Pro)
- [ ] Use `SafeArea` for system UI overlaps
- [ ] Test on both iOS and Android

---

## Lessons Learned: Word Display Scaling Bug

### The Problem
The word display container was expanding to full screen width during celebration animations, but only the translucent container - the scaled outline was rendering correctly outside its bounds.

### The Root Cause
`Positioned.fill` was correctly being used, but during iterative debugging attempts, various wrappers (Center, Align, UnconstrainedBox) were tried that inadvertently broke the layout. A git revert restored the correct structure.

### The Solution
The **correct pattern** for scaling animations:
```dart
Stack(
  alignment: Alignment.center,
  clipBehavior: Clip.none, // Allow visual overflow
  children: [
    // This defines Stack size
    Container(
      padding: EdgeInsets.all(24),
      child: Text(word),
    ),
    // This is excluded from layout
    Positioned.fill(
      child: Transform.translate(
        offset: Offset(0, upwardOffset),
        child: Transform.scale(
          scale: outlineScale,
          child: Opacity(
            opacity: outlineOpacity,
            child: CustomPaint(...), // Receives bounded constraints
          ),
        ),
      ),
    ),
  ],
)
```

### Key Takeaways
1. **Positioned children don't affect Stack intrinsic size** - only non-positioned children do
2. **LayoutBuilder inside Positioned.fill receives Stack's size** as constraints (bounded)
3. **Git revert** can sometimes be the fastest fix when incremental changes create complexity
4. **Diagnostic logging** with actual measurements is more reliable than assumptions
5. **Hot restart vs full restart** can matter - full restart clears stale state

### Diagnostic Approach That Worked
1. Added `AppLogger.enableLayoutDebug` flag
2. Instrumented key measurement points with GlobalKeys
3. Logged constraints (input) and actual sizes (output) at each level
4. Ran tests and analyzed patterns in logs
5. Identified exact root cause from data, not guesswork
6. Applied targeted fix with confidence

**This diagnostic methodology should be the standard for complex layout issues going forward.**

---

## Additional Resources

- **Official Flutter Docs:** [Understanding constraints](https://docs.flutter.dev/ui/layout/constraints)
- **Layout Debugger:** Flutter DevTools → Layout Explorer
- **Performance:** [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices)
- **See also:** `LOGGING.md` for logging best practices

---

**Last Updated:** 2025-11-11  
**Maintained by:** Xen Words Development Team

