# Build Fix for Thermion Native Assets Issue

## Problem
Even after running `flutter config --enable-native-assets`, the build still fails with:
```
Package(s) thermion_dart require the native assets feature to be enabled.
```

## Solution Steps

### 1. Verify Flutter Channel
Thermion requires Flutter **beta** channel. Check your channel:
```bash
flutter channel
```

If you're on `stable`, switch to `beta`:
```bash
flutter channel beta
flutter upgrade
```

### 2. Verify Native Assets is Enabled
```bash
flutter config
```

Look for `enable-native-assets: true` in the output.

### 3. Complete Clean
Delete all cached files:
```bash
flutter clean
rm -rf .dart_tool
rm -rf build
rm -rf .flutter-plugins-dependencies
rm -rf .flutter-plugins
```

### 4. Regenerate Everything
```bash
flutter pub get
flutter pub cache repair  # Optional but can help
```

### 5. Try Building Again
```bash
flutter run
```

## Alternative: Check Flutter Version
If you're on Flutter 3.35.5, native assets should work. But Thermion might require a specific minimum version. Check Thermion's requirements:
- Minimum Flutter version: Check pub.dev page
- Required channel: Beta (as per Thermion docs)

## If Still Failing
The issue might be that the Flutter build system isn't reading the config. Try:
1. Restart your terminal/IDE
2. Check if there's a `settings.json` or config file that needs updating
3. Try running from a fresh terminal session

