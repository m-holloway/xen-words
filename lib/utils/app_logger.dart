import 'package:logger/logger.dart';

/// Centralized logging configuration for the application.
/// 
/// Features:
/// - Domain-specific loggers for better organization
/// - Configurable log levels per domain
/// - Performance-friendly (minimal overhead when disabled)
/// - Easy to adjust verbosity for debugging vs production
/// - Lazy evaluation prevents performance impact when logging is disabled
/// 
/// Usage:
/// ```dart
/// AppLogger.game.i('Game started');
/// AppLogger.speech.d('Processing audio chunk');
/// AppLogger.rendering.t('Frame rendered');
/// 
/// // With emoji shortcuts
/// AppLogger.game.success('Level complete!');
/// AppLogger.audio.progress('Loading audio assets...');
/// ```
/// 
/// Log Levels (from least to most severe):
/// - trace (t): Very detailed, for debugging specific code paths
/// - debug (d): Detailed info for debugging (default in debug mode)
/// - info (i): General information (default in release mode)
/// - warning (w): Warnings that don't prevent operation
/// - error (e): Errors that should be investigated
/// - fatal (f): Critical errors that may crash the app
class AppLogger {
  // Private constructor to prevent instantiation
  AppLogger._();

  /// Global log level - set to Level.off in production builds
  static Level globalLevel = Level.debug;

  /// Enable/disable all logging (useful for production)
  static bool enabled = true;
  
  /// Enable/disable performance-intensive logging (e.g., frame-by-frame updates)
  static bool enablePerformanceLogging = false;
  
  /// Enable/disable layout debugging (frame-by-frame layout measurements)
  static bool enableLayoutDebug = false;

  // Domain-specific loggers
  static final Logger game = _createLogger('GAME');
  static final Logger speech = _createLogger('SPEECH');
  static final Logger audio = _createLogger('AUDIO');
  static final Logger rendering = _createLogger('RENDER');
  static final Logger lighting = _createLogger('LIGHT');
  static final Logger animation = _createLogger('ANIM');
  static final Logger camera = _createLogger('CAMERA');
  static final Logger ui = _createLogger('UI');
  static final Logger layout = _createLogger('LAYOUT');
  static final Logger network = _createLogger('NET');
  static final Logger storage = _createLogger('STORAGE');
  static final Logger performance = _createLogger('PERF');
  static final Logger system = _createLogger('SYSTEM');

  /// Create a custom logger for specific use cases
  static Logger custom(String name) => _createLogger(name);

  /// Create a logger instance with custom configuration
  static Logger _createLogger(String name) {
    return Logger(
      filter: _AppLogFilter(),
      printer: _AppLogPrinter(name),
      output: _AppLogOutput(),
    );
  }

  /// Configure logging for different environments
  static void configureForEnvironment({
    required bool isProduction,
    Level? level,
    bool? allowPerformanceLogging,
  }) {
    if (isProduction) {
      // In production, disable all logging by default
      enabled = false;
      globalLevel = Level.off;
      enablePerformanceLogging = false;
    } else {
      // In development, enable logging
      enabled = true;
      globalLevel = level ?? Level.warning;
      enablePerformanceLogging = allowPerformanceLogging ?? false;
    }
  }

  /// Set log level for debugging specific domains
  static void setLevel(Level level) {
    globalLevel = level;
  }
  
  /// Quick toggle for all logging (useful for performance testing)
  static void setEnabled(bool value) {
    enabled = value;
  }
  
  /// Toggle performance logging (frame updates, etc.)
  static void setPerformanceLogging(bool value) {
    enablePerformanceLogging = value;
  }
}

/// Custom log filter that respects global settings
class _AppLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (!AppLogger.enabled) return false;
    return event.level.index >= AppLogger.globalLevel.index;
  }
}

/// Custom printer with clean, readable output
class _AppLogPrinter extends LogPrinter {
  final String domain;
  final bool includeEmojis;
  final bool includeTimestamp;

  _AppLogPrinter(
    this.domain, {
    this.includeEmojis = true,
    this.includeTimestamp = false,
  });

  static const Map<Level, String> _levelEmojis = {
    Level.trace: '🔍',
    Level.debug: '🐛',
    Level.info: 'ℹ️',
    Level.warning: '⚠️',
    Level.error: '❌',
    Level.fatal: '💀',
  };

  static const Map<Level, String> _levelColors = {
    Level.trace: '\x1B[90m', // Gray
    Level.debug: '\x1B[36m', // Cyan
    Level.info: '\x1B[37m',  // White
    Level.warning: '\x1B[33m', // Yellow
    Level.error: '\x1B[31m', // Red
    Level.fatal: '\x1B[35m', // Magenta
  };

  static const String _resetColor = '\x1B[0m';

  @override
  List<String> log(LogEvent event) {
    final color = _levelColors[event.level] ?? '';
    final emoji = includeEmojis ? (_levelEmojis[event.level] ?? '') : '';
    final timestamp = includeTimestamp 
        ? '[${DateTime.now().toIso8601String().substring(11, 23)}] '
        : '';
    
    final prefix = '$color$emoji [$domain]$_resetColor';
    final message = event.message;
    
    final lines = <String>[];
    lines.add('$timestamp$prefix $message');
    
    // Add error and stack trace if present
    if (event.error != null) {
      lines.add('$prefix Error: ${event.error}');
    }
    
    if (event.stackTrace != null && event.level.index >= Level.error.index) {
      lines.add('$prefix Stack trace:');
      lines.addAll(
        event.stackTrace.toString().split('\n').map((line) => '$prefix   $line')
      );
    }
    
    return lines;
  }
}

/// Custom output that writes to console
class _AppLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (var line in event.lines) {
      // ignore: avoid_print
      print(line);
    }
  }
}

/// Extension methods for convenience
extension LoggerExtensions on Logger {
  /// Log with custom emoji prefix
  void emoji(String emoji, String message, [dynamic error, StackTrace? stackTrace]) {
    i('$emoji $message', error: error, stackTrace: stackTrace);
  }
  
  /// Success logging (convenience method)
  void success(String message) {
    i('✅ $message');
  }
  
  /// Progress/loading logging (convenience method)
  void progress(String message) {
    i('🔄 $message');
  }
}

