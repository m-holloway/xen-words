<!-- e4d56297-1256-4907-8b1a-d3fcfe7ed444 7a83818b-3899-42e8-aba3-48931e752a18 -->
# Live Director Tuning System

## Overview

Create a minimally intrusive, keyboard-focused overlay system for live-tuning Director parameters (lighting, camera, etc.) with full-screen touch adjustment, interactive goto navigation, and JSON persistence.

## Architecture

### 1. Parameter Registry & Metadata System

**File:** `lib/services/director_tuner.dart`

Create a generic parameter registration system that Directors use to declare their tunable parameters:

- `DirectorTuner` singleton (ChangeNotifier) manages runtime overrides
- `TunableParameter` class describes each parameter (name, type, range, default, current value)
- Support parameter types: `double`, `Vector3` components, `Duration`, `bool`, `ShotComposition` components, `LightDirection` components
- Store overrides in a map: `Map<String, Map<String, dynamic>>` (director → param → value)
- Provide `getValue<T>(director, param, defaultValue)` method that checks overrides first
- Methods: `setParameter()`, `resetParameter()`, `resetAll()`, `exportToJson()`, `importFromJson()`

### 2. Director Integration

**Files:** `lib/widgets/lighting_director.dart`, `lib/widgets/camera_director.dart`

Modify Directors to register parameters and use tuner for values:

- Add static `registerParameters()` method called during app init
- Replace direct const usage with `DirectorTuner.instance.getValue()` calls
- For composite types (LightDirection, ShotComposition), register individual components
- Example registration:
  ```dart
  DirectorTuner.register('lighting', 'primaryIntensity', 
    min: 0, max: 300000, default: 120000, unit: 'lux');
  DirectorTuner.register('lighting', 'fillDirection.x',
    min: -1, max: 1, default: -0.2, unit: 'direction');
  ```


### 3. Overlay UI Widget

**File:** `lib/widgets/director_overlay.dart`

Build the main overlay interface:

- Translucent, dismissible overlay (opacity ~0.85)
- Header: Current mode → parameter → sub-setting breadcrumb
- Parameter list view (when not adjusting)
- Touch-anywhere relative slider (when adjusting)
- Live value display during adjustment
- Minimizes to small indicator when slider is active

**States:**

- **Browse mode**: Show mode/param list with keyboard navigation
- **Adjust mode**: Full-screen touch slider with live value
- **Goto mode**: Interactive command input with predictive display
- **Report mode**: Overlay showing changed parameters from baseline

### 4. Keyboard Navigation System

**File:** `lib/services/keyboard_handler.dart`

Implement keyboard shortcuts:

- `d`: Toggle director overlay
- `Tab` or `m`: Cycle modes (lighting → camera → ...)
- `↑/↓`: Navigate parameter list
- `←/→`: Cycle sub-settings (x/y/z components)
- `Enter`: Enter adjust mode for selected parameter
- `PgUp/PgDn`: Coarse adjustment (when in adjust mode)
- `+/-`: Fine adjustment (when in adjust mode)
- `Esc`: Exit adjust mode / close overlay
- `r`: Toggle report overlay (show changes from baseline)
- `g`: Enter goto mode

### 5. Interactive Goto System

**File:** `lib/widgets/goto_command.dart`

Build the goto command parser and predictor:

- Parse commands like `gl10.1` → lighting director, param 10, sub-param 1
- Interactive display as user types:
  - After `g`: show `l - lighting`, `c - camera`
  - After `gl`: show numbered parameter list (first 10)
  - After `gl1`: show matching params (1, 10-19)
  - After `gl10.`: show sub-params (0=x, 1=y, 2=z)
- Overlay predictive display near cursor
- Execute on `Enter`, cancel on `Esc`

### 6. Full-Screen Touch Slider

**File:** `lib/widgets/relative_touch_slider.dart`

Implement the touch adjustment system:

- **Touch down**: Record start position and current value
- **X-axis drag** (beyond 30px hysteresis): Coarse mode
  - Map pixel delta to full parameter range
  - Visual feedback: horizontal progress bar
- **Y-axis drag** (beyond 30px hysteresis): Fine mode  
  - Map pixel delta to 10% of parameter range (10x finer)
  - Visual feedback: vertical progress bar
- **Modulo range calculation**: Center slider on current value
  - If param range is -100 to +100 and current is 20:
  - Display range becomes -80 to +120 (centered on 20)
  - Lock extents during touch (no recomputation)
- **Live value display**: Show numeric value prominently
- **Live scene update**: Call `DirectorTuner.setParameter()` continuously

### 7. Report & Export System

**File:** `lib/widgets/director_report.dart`

Build the self-aware parameter report overlay for annotated screenshots:

- **Diff Detection**: Automatically compare current values vs. baseline (const defaults)
- **Display Only Changes**: Show ONLY parameters that differ from starting point
- **Concise Format**: 
  ```
  DIRECTOR TUNING REPORT
  ═══════════════════════
  lighting.primaryIntensity: 120000 → 150000
  lighting.fillDirection.x: -0.2 → -0.3
  camera.playingShot.distance: 6.0 → 6.5
  ═══════════════════════
  ```

- **Screenshot-Friendly Layout**:
  - Semi-transparent background (can see scene)
  - Positioned in corner to not obscure character
  - Monospace font for alignment
  - Compact formatting
- **Actions**: "Export JSON", "Copy to Clipboard", "Reset All", "Dismiss"
- **JSON Export**: Save tuned parameters for later import/hot-reload
- **Use Case**: Press 'r' to overlay report, take screenshot, get perfect documentation of exact parameter values that created that visual result

### 8. Scene Integration

**File:** `lib/widgets/character_view.dart`

Integrate tuner with live scene updates:

- Listen to `DirectorTuner` changes
- When parameters change, recreate lights/reposition camera
- Use existing `_setupLighting()` and camera position methods
- No hot reload needed - changes apply immediately

### 9. App Integration

**File:** `lib/main.dart`

Wire up the overlay:

- Initialize `DirectorTuner.instance`
- Call `LightingDirector.registerParameters()`
- Call `CameraDirector.registerParameters()`
- Wrap game screen with `KeyboardListener` for shortcuts
- Add `DirectorOverlay` as a Stack overlay (initially hidden)

## Key Implementation Details

**Parameter Range Handling:**

- Each parameter declares min/max/default
- For normalized vectors (directions), use -1 to 1 per component
- For intensities, use reasonable physical ranges (0-300000 lux)
- For durations, store as milliseconds (int)

**Live Update Optimization:**

- Debounce updates during rapid slider movement (every 16ms / 60fps max)
- Batch multiple parameter changes if possible
- Cache baseline values for fast "reset to default"

**Future Extensibility:**

- MCP integration point: `DirectorTuner.setParameter()` can be called externally
- Automated exploration: Keyboard commands can be scripted
- Screenshot coordination: Report overlay + scene capture = perfect documentation

## Files to Create

1. `lib/services/director_tuner.dart` - Core tuning system
2. `lib/services/keyboard_handler.dart` - Keyboard shortcuts
3. `lib/widgets/director_overlay.dart` - Main UI
4. `lib/widgets/goto_command.dart` - Goto parser & predictor
5. `lib/widgets/relative_touch_slider.dart` - Touch adjustment
6. `lib/widgets/director_report.dart` - Report overlay
7. `lib/models/tunable_parameter.dart` - Parameter metadata

## Files to Modify

1. `lib/widgets/lighting_director.dart` - Add registration & tuner integration
2. `lib/widgets/camera_director.dart` - Add registration & tuner integration  
3. `lib/widgets/character_view.dart` - Listen for tuner changes
4. `lib/main.dart` - Initialize and wire up system

## Testing Strategy

1. Start with lighting parameters (simpler than camera)
2. Test keyboard navigation thoroughly
3. Verify touch slider feels natural (adjust hysteresis/sensitivity)
4. Test goto command with all parameter types
5. Verify JSON export/import round-trips correctly
6. Test hot reload doesn't break tuner state

### To-dos

- [ ] Create DirectorTuner singleton with parameter registry, override storage, and ChangeNotifier
- [ ] Create TunableParameter model for parameter metadata (type, range, units)
- [ ] Add parameter registration and tuner integration to LightingDirector
- [ ] Add parameter registration and tuner integration to CameraDirector
- [ ] Implement keyboard shortcut system with mode switching and navigation
- [ ] Build interactive goto command parser with predictive display
- [ ] Implement full-screen relative touch slider with coarse/fine modes
- [ ] Build main director overlay with browse/adjust/goto states
- [ ] Create report overlay with JSON export/import functionality
- [ ] Integrate tuner with character_view for live scene updates
- [ ] Wire up overlay and keyboard handler in main.dart