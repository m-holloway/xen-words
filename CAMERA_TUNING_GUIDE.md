# 🎛️ Camera Tuning Guide

## Quick Start

All camera parameters are now in **ONE FILE**: `lib/widgets/camera_director.dart`

Open that file, adjust values, hot reload, and see results instantly!

---

## 🎯 What You Can Tune

### 1. **Shot Composition** (How close/far/high/low)

```dart
// Located in: CameraDirector class
static const ShotComposition celebratingShot = ShotComposition(
  distance: 2.0,           // ← Change this to push in closer or pull back
  heightOffset: 0.5,       // ← Change this to boom up/down
  angleOffset: 0.0,        // ← Change this for side angle
  description: "...",
);
```

**To exaggerate success reaction:**
- Decrease `distance` (try 1.5 for VERY close)
- Increase `heightOffset` (try 0.8 for dramatic hero angle)

**To exaggerate failure reaction:**
- Increase `distance` (try 6.0 for VERY wide)
- Decrease `heightOffset` (try -0.5 for more vulnerable angle)

---

### 2. **Transition Timing** (How fast camera moves)

```dart
// Located in: CameraDirector class
static const Duration successTransitionSpeed = Duration(milliseconds: 500);
static const Duration failureTransitionSpeed = Duration(milliseconds: 1200);
```

**To make success feel MORE energetic:**
- Reduce milliseconds (try 300 for snap-zoom)

**To make failure feel MORE empathetic:**
- Increase milliseconds (try 1800 for very gentle)

---

### 3. **Organic Breathing** (How much camera moves during idle)

```dart
// Located in: CameraDirector class
static const BreathingLayer primaryBreathing = BreathingLayer(
  frequency: 1.5,          // ← Cycles per second (lower = slower breathing)
  amplitude: 0.012,        // ← Movement amount (higher = more motion)
  description: "...",
);
```

**To see breathing more clearly:**
- Increase all `amplitude` values by 2-3x
- Try: `amplitude: 0.036` for exaggerated breathing

**To make it more subtle:**
- Decrease all `amplitude` values by half
- Try: `amplitude: 0.006` for very gentle breathing

**Quick intensity control:**
```dart
static const double breathingIntensityMultiplier = 1.0;
// Set to 2.0 to double all breathing
// Set to 0.5 to halve all breathing
// Set to 0.0 to disable completely
```

---

### 4. **Random Variation** (Makes each reaction feel different)

```dart
// Located in: CameraDirector class
static const RandomVariation shotVariation = RandomVariation(
  distanceVariation: 0.1,      // ± variation in distance
  heightVariation: 0.05,       // ± variation in height
  angleVariation: 0.05,        // ± variation in angle
  enabled: true,               // ← Set to false to disable
);
```

**To see variation clearly:**
- Increase all variation values (try 0.3 for distance)
- Get a word right multiple times and watch camera vary

**To make reactions more consistent:**
- Decrease variation values (try 0.02)
- Or set `enabled: false`

---

## 🔧 Tuning Workflow

### Step 1: Exaggerate to See Effect
1. Open `camera_director.dart`
2. Find the parameter you want to tune
3. **Make it EXTREME** (2-3x bigger/smaller)
4. Hot reload
5. Trigger the effect (get word right/wrong)
6. Observe what changed

### Step 2: Dial Back to Sweet Spot
1. Once you see the effect clearly
2. Gradually reduce/increase toward middle ground
3. Hot reload after each change
4. Keep testing until it "feels right"

### Step 3: Test Multiple Times
1. Because of random variation, test 3-5 times
2. Make sure it feels good in different scenarios
3. Adjust if needed

---

## 📊 Example Tuning Sessions

### Making Success More Exciting

**Current:**
```dart
distance: 2.0,
heightOffset: 0.5,
successTransitionSpeed: Duration(milliseconds: 500),
```

**Exaggerated (to see effect):**
```dart
distance: 1.0,           // MUCH closer
heightOffset: 1.0,       // MUCH higher
successTransitionSpeed: Duration(milliseconds: 200),  // MUCH faster
```

**Tuned back (feels right):**
```dart
distance: 1.5,           // Sweet spot
heightOffset: 0.7,       // Sweet spot
successTransitionSpeed: Duration(milliseconds: 350),  // Sweet spot
```

---

### Making Breathing More Noticeable

**Current:**
```dart
amplitude: 0.012,
breathingIntensityMultiplier: 1.0,
```

**Exaggerated (to see effect):**
```dart
amplitude: 0.036,        // 3x bigger
breathingIntensityMultiplier: 2.0,  // 2x multiplier
```

**Tuned back (feels right):**
```dart
amplitude: 0.018,        // Sweet spot (50% increase)
breathingIntensityMultiplier: 1.0,
```

---

### Adding More Random Variety

**Current:**
```dart
distanceVariation: 0.1,
heightVariation: 0.05,
enabled: true,
```

**Exaggerated (to see effect):**
```dart
distanceVariation: 0.5,   // Huge variation
heightVariation: 0.3,     // Huge variation
enabled: true,
```

**Tuned back (feels right):**
```dart
distanceVariation: 0.2,   // Sweet spot
heightVariation: 0.1,     // Sweet spot
enabled: true,
```

---

## 🎬 What Each Parameter FEELS Like

### Distance (closer ↔ farther)
- **Closer** (1.5-2.0) = Intimate, intense, personal, excited
- **Medium** (2.5-3.5) = Comfortable, neutral, observing
- **Farther** (4.0-5.5) = Spacious, calm, giving room, empathetic

### Height Offset (boom down ↔ boom up)
- **Down** (-0.5 to -0.2) = Vulnerable, empathetic, understanding
- **Eye Level** (-0.1 to 0.1) = Neutral, equal, conversational
- **Up** (0.3 to 0.8) = Powerful, heroic, triumphant, empowering

### Transition Speed (fast ↔ slow)
- **Fast** (200-400ms) = Energetic, excited, reactive, punchy
- **Medium** (600-900ms) = Natural, comfortable, fluid
- **Slow** (1200-1800ms) = Gentle, patient, empathetic, careful

### Breathing Amplitude (subtle ↔ obvious)
- **Subtle** (0.005-0.010) = Professional, barely noticeable, subconscious
- **Medium** (0.012-0.020) = Natural, organic, human-like
- **Obvious** (0.030+) = Expressive, stylized, intentional

### Random Variation (consistent ↔ varied)
- **Low** (0.0-0.05) = Predictable, consistent, reliable
- **Medium** (0.1-0.2) = Natural variety, stays fresh
- **High** (0.3+) = Surprising, dynamic, unpredictable

---

## 🚨 Common Mistakes

### ❌ Changing Too Many Things at Once
**Problem:** Can't tell what caused the change
**Solution:** Change ONE parameter at a time, test, then move to next

### ❌ Not Exaggerating Enough Initially
**Problem:** Changes too subtle to notice
**Solution:** Make it RIDICULOUS first, then dial back

### ❌ Only Testing Once
**Problem:** Random variation means one test isn't enough
**Solution:** Test each change 3-5 times

### ❌ Forgetting to Hot Reload
**Problem:** Think change didn't work, but just didn't reload
**Solution:** Always hot reload after editing camera_director.dart

---

## 🎯 Recommended Starting Points

If current values feel too subtle, try these:

### More Dramatic Reactions
```dart
// Success - make it MORE exciting
celebratingShot: distance: 1.5 (was 2.0)
successTransitionSpeed: 350ms (was 500ms)

// Failure - make it MORE empathetic  
failingShot: distance: 6.0 (was 5.0)
failureTransitionSpeed: 1500ms (was 1200ms)
```

### More Noticeable Breathing
```dart
breathingIntensityMultiplier: 1.5 (was 1.0)
// This multiplies all breathing by 50%
```

### More Variety
```dart
shotVariation: 
  distanceVariation: 0.2 (was 0.1)
  heightVariation: 0.1 (was 0.05)
```

---

## 💡 Pro Tips

1. **Use descriptive comments** in camera_director.dart as you tune
2. **Save your "exaggerated" values** in comments for reference
3. **Test with kids** - they're the real judges!
4. **Record video** of before/after to compare
5. **Trust your gut** - if it feels right, it IS right

---

## 🎓 Understanding the Frame of Reference

All camera positions are relative to the character, not absolute world coordinates. This means:

- `distance: 3.0` means "3 units away from character" (wherever character is)
- `heightOffset: 0.5` means "0.5 units above character's center" (moves with character)
- `angleOffset: 0.3` means "0.3 units to the right of character" (tracks character)

You never need to think about absolute world positions or do coordinate math!

---

## 🔄 Iteration Loop

```
1. Open camera_director.dart
2. Change a parameter (exaggerate it!)
3. Hot reload
4. Test the effect 3-5 times
5. Adjust toward sweet spot
6. Hot reload
7. Test again
8. Repeat until it feels perfect!
```

Happy tuning! 🎬


