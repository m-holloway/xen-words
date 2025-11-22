import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Display widget for grouped words with smooth progress indicator
/// Provides auto-scrolling and graduated spotlight without shifting layout.
class GroupedWordDisplay extends StatefulWidget {
  final List<String> displayWords;
  final List<List<int>> wordGroups; // Groups of word indices
  final int currentWordIndex;
  final double smoothProgress; // 0.0 to 1.0 within current line
  final Function(int)? onWordTap;
  final bool readingComplete;
  final int? scrollWordIndex;
  final bool suppressNextLinger;
  final bool shouldAutoExpand;
  final Duration scrollDuration;
  final bool showCompletionCard;
  final Widget? completionCard;
  final double focusLineIndex;
  
  const GroupedWordDisplay({
    Key? key,
    required this.displayWords,
    required this.wordGroups,
    required this.currentWordIndex,
    this.smoothProgress = 0.0,
    this.onWordTap,
    this.readingComplete = false,
    this.scrollWordIndex,
    this.suppressNextLinger = false,
    this.shouldAutoExpand = false,
    this.showCompletionCard = false,
    this.completionCard,
    this.scrollDuration = const Duration(milliseconds: 1000),
    this.focusLineIndex = -1.0,
  }) : super(key: key);
  
  @override
  State<GroupedWordDisplay> createState() => _GroupedWordDisplayState();
}

class _GroupedWordDisplayState extends State<GroupedWordDisplay> {
  static const double _lineHeight = 100.0; // Revert to original spacing
  static const EdgeInsets _listPadding = EdgeInsets.symmetric(vertical: 12, horizontal: 8);
  static const Color _unreadBg = Color(0xFFF6F7FB);
  static const Color _unreadBorder = Color(0xFFE3E6EF);
  static final Color _unreadText = Colors.black.withOpacity(0.65);
  static const Color _activeBg = Color(0xFF5245FF);
  static const Color _activeBorder = Color(0xFF4134D8);
  static const Color _activeGlow = Color(0x334134D8);
  static const Color _readText = Color(0xFF475467);
  static const Duration _lingerDuration = Duration(milliseconds: 1000);
  final ScrollController _scrollController = ScrollController();
  int _lastScrollTarget = -1;
  Timer? _scrollDebounce;
  int? _previousActiveWordIndex;
  DateTime? _previousActiveTimestamp;
  Timer? _lingerTimer;
  Future<void>? _scrollAnimation;
  
  @override
  void initState() {
    super.initState();
    _scheduleScroll(immediate: true);
  }
  
  @override
  void didUpdateWidget(GroupedWordDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentWordIndex != widget.currentWordIndex ||
        oldWidget.scrollWordIndex != widget.scrollWordIndex ||
        oldWidget.suppressNextLinger != widget.suppressNextLinger) {
      if (widget.suppressNextLinger) {
        _previousActiveWordIndex = null;
        _previousActiveTimestamp = null;
        _lingerTimer?.cancel();
      } else if (oldWidget.currentWordIndex != widget.currentWordIndex &&
          oldWidget.currentWordIndex >= 0) {
        _previousActiveWordIndex = oldWidget.currentWordIndex;
        _previousActiveTimestamp = DateTime.now();
        _lingerTimer?.cancel();
        _lingerTimer = Timer(_lingerDuration, () {
          if (mounted) {
            setState(() {
              _previousActiveWordIndex = null;
              _previousActiveTimestamp = null;
            });
          }
        });
      }
      if (oldWidget.currentWordIndex != widget.currentWordIndex &&
          oldWidget.currentWordIndex >= 0 &&
          widget.suppressNextLinger) {
        // already handled
      }
      _scheduleScroll();
    }
  }
  
  void _scheduleScroll({bool immediate = false}) {
    _scrollDebounce?.cancel();
    final delay = immediate ? Duration.zero : const Duration(milliseconds: 16);
    _scrollDebounce = Timer(delay, () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToCurrentLine(animated: !immediate);
      });
    });
  }
  
  void _scrollToCurrentLine({bool animated = true}) {
    if (!mounted || widget.wordGroups.isEmpty) return;
    if (widget.shouldAutoExpand) {
      return;
    }
    if (!_scrollController.hasClients || !_scrollController.position.hasPixels) return;
    
    final targetWord = widget.scrollWordIndex ?? widget.currentWordIndex;
    final anchorLine = _findLineForWord(targetWord);
    final targetLine = math.max(0, anchorLine - 1);
    if (targetLine < 0) return;
    
    final shouldAnimate = animated && targetLine != _lastScrollTarget;
    _lastScrollTarget = targetLine;
    
    final position = _scrollController.position;
    final double lineExtent = _lineHeight;
    final double targetOffset = (_listPadding.top + targetLine * lineExtent)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    
    if (shouldAnimate) {
      final animation = _scrollController.animateTo(
        targetOffset,
        duration: widget.scrollDuration,
        curve: Curves.easeInOutCubic,
      );
      _scrollAnimation = animation;
      animation.whenComplete(() {
        if (_scrollAnimation == animation) {
          _scrollAnimation = null;
        }
      });
    } else {
      if (_scrollAnimation != null) {
        // Let the in-flight animation finish to avoid jumpy transitions.
        return;
      }
      _scrollController.jumpTo(targetOffset);
    }
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _scrollDebounce?.cancel();
    _lingerTimer?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final currentLineIndex = _findLineForWord(widget.currentWordIndex);
    
    final double? heightConstraint = widget.shouldAutoExpand ? null : _estimateViewportHeight();
    
    Widget listContent = ScrollConfiguration(
      behavior: const _NoGlowScrollBehavior(),
      child: ListView.builder(
        controller: _scrollController,
        physics: widget.shouldAutoExpand 
            ? const NeverScrollableScrollPhysics() 
            : const BouncingScrollPhysics(),
        shrinkWrap: widget.shouldAutoExpand,
        padding: _listPadding,
        itemExtent: _lineHeight,
        itemCount: widget.wordGroups.length,
        itemBuilder: (context, lineIdx) {
          final isCurrent = lineIdx == currentLineIndex;
          final progress = isCurrent
              ? widget.smoothProgress
              : (lineIdx < currentLineIndex ? 1.0 : 0.0);
          
          return _buildLine(
            lineIdx,
            currentLineIndex: currentLineIndex,
            isCurrent: isCurrent,
            progress: progress,
          );
        },
      ),
    );

    if (heightConstraint != null) {
      listContent = SizedBox(height: heightConstraint, child: listContent);
    }
    
    if (widget.shouldAutoExpand) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          listContent,
          if (widget.showCompletionCard && widget.completionCard != null) ...[
            const SizedBox(height: 24),
            widget.completionCard!,
          ],
        ],
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: listContent,
    );
  }
  
  double _estimateViewportHeight() {
    const maxHeight = 360.0;
    const minHeight = 200.0;
    final contentHeight = widget.wordGroups.length * _lineHeight + _listPadding.vertical;
    return math.max(
      minHeight,
      math.min(maxHeight, contentHeight),
    );
  }
  
  Widget _buildLine(
    int lineIndex, {
    required int currentLineIndex,
    required bool isCurrent,
    required double progress,
  }) {
    final wordIndices = widget.wordGroups[lineIndex];
    
    final completed = lineIndex < currentLineIndex;
    final isNext = lineIndex == currentLineIndex + 1;
    final isPrevious = lineIndex == currentLineIndex - 1;
    final colorPalette = _RailColors.forState(
      isCurrent: isCurrent,
      isNext: isNext,
      isPrevious: isPrevious,
      completed: completed,
    );
    
    // Fading logic based on focusLineIndex
    // If focusLineIndex is valid (>= 0), we fade out lines far from it.
    // User request: fade out historical rows before active-1.
    // We interpret this as: keep visible range around [focus - 1.5, focus + 2.5].
    // If user scrolls up, focusLineIndex decreases, so older lines fall into visible range.
    
    double opacity = 1.0;
    if (!widget.readingComplete && widget.focusLineIndex >= 0) {
       // Standard reading range
       // Keep 2 lines of history (active-2, active-1), active, and 2 lines of future (active+1, active+2)
       // If we scroll up, we shift this window back.
       
       // Lower bound: fade out if lineIndex < focus - 2.5
       // Upper bound: fade out if lineIndex > focus + 2.5
       
       if (lineIndex < widget.focusLineIndex - 2.5 || lineIndex > widget.focusLineIndex + 2.5) {
         opacity = 0.0;
       }
    } else if (!widget.readingComplete) {
       // Fallback if focus not tracked (shouldn't happen with new logic)
       if (lineIndex > currentLineIndex + 2) opacity = 0.0;
    }

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOut,
      child: Padding(
      padding: EdgeInsets.symmetric(horizontal: isCurrent ? 4 : 8, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colorPalette.background,
          borderRadius: BorderRadius.circular(18),
          border: colorPalette.border,
          boxShadow: colorPalette.shadow,
        ),
        child: SizedBox(
            height: 68, // Revert to original height
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildLineWords(wordIndices),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildLineWords(List<int> wordIndices) {
    if (wordIndices.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final chips = <Widget>[];
    for (final wordIdx in wordIndices) {
      chips.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _buildWordChip(wordIdx),
      ));
    }

    return ClipRect(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: chips,
        ),
      ),
    );
  }

  Widget _buildWordChip(int wordIndex) {
    if (wordIndex < 0 || wordIndex >= widget.displayWords.length) {
      return const SizedBox.shrink();
    }
    
    final bool isActiveWord = !widget.readingComplete && wordIndex == widget.currentWordIndex;
    final bool isRead = widget.readingComplete
        ? wordIndex <= widget.currentWordIndex
        : wordIndex < widget.currentWordIndex;
    final bool isLingerWord = !isActiveWord &&
        _previousActiveWordIndex == wordIndex &&
        _previousActiveTimestamp != null &&
        DateTime.now().difference(_previousActiveTimestamp!) < _lingerDuration;

    Color textColor = _unreadText;
    Color bgColor = Colors.transparent;
    Border? border;
    List<BoxShadow>? shadows;
    FontWeight weight = FontWeight.w600;
    double activeFadeProgress = 0.0;
    bool hasActiveFadeProgress = false;

    if (isActiveWord || isLingerWord) {
      final double rawProgress = isLingerWord
          ? DateTime.now().difference(_previousActiveTimestamp!).inMilliseconds /
              _lingerDuration.inMilliseconds
          : 0.0;
      final double clamped = rawProgress.clamp(0.0, 1.0);
      activeFadeProgress = clamped;
      hasActiveFadeProgress = true;

      const double stageBreak = 0.85; // first phase: vibrant to outlined
      final double stageOneProgress = (clamped / stageBreak).clamp(0.0, 1.0);
      final double stageTwoProgress = clamped <= stageBreak
          ? 0.0
          : ((clamped - stageBreak) / (1 - stageBreak)).clamp(0.0, 1.0);

      // Stage 1: white text on solid indigo → indigo text on white background with blue border.
      final Color stageOneText = Color.lerp(Colors.white, Colors.white, stageOneProgress * 0.9)!;
      final Color stageOneBg = Color.lerp(_activeBg, _activeBg.withOpacity(0.7), stageOneProgress)!;
      final Color stageOneBorder = Color.lerp(_activeBorder, _activeBorder.withOpacity(0.9), stageOneProgress)!;
      // Stage 2: indigo text on white → final read styling.
      textColor = Color.lerp(stageOneText, _readText, stageTwoProgress * 0.9)!;
      bgColor = Color.lerp(stageOneBg, Colors.white, stageTwoProgress * 0.9)!;
      border = Border.all(
        color: Color.lerp(stageOneBorder, Colors.white, stageTwoProgress)!,
        width: 2.0,
      );
      weight = FontWeight.w800;
      shadows = [
        BoxShadow(
          color: Color.lerp(_activeGlow, Colors.transparent, stageTwoProgress * 0.8)!,
          blurRadius: 18 - (8 * stageTwoProgress),
          offset: Offset(0, 8 - (4 * stageTwoProgress)),
        ),
      ];
    } else if (isRead) {
      textColor = _readText.withOpacity(0.85);
      bgColor = Colors.transparent;
    } else {
      bgColor = _unreadBg.withOpacity(0.5);
      border = Border.all(color: _unreadBorder.withOpacity(0.4), width: 1.6);
      textColor = _unreadText.withOpacity(0.5);
    }

    double scale = 1.0;
    if (isActiveWord) {
      scale = 1.08;
    } else if (isLingerWord && hasActiveFadeProgress) {
      scale = 1.02 + (0.04 * (1.0 - activeFadeProgress));
    }

    final Duration scaleDuration = Duration(
      milliseconds: isLingerWord ? 450 : (isActiveWord ? 240 : 180),
    );

    Widget chip = AnimatedScale(
      scale: scale,
      duration: scaleDuration,
      curve: isLingerWord ? Curves.easeOutBack : Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), // Revert to original padding
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: border,
          boxShadow: shadows,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.displayWords[wordIndex],
              style: TextStyle(
                fontSize: 22,
                fontWeight: weight,
                color: textColor,
                letterSpacing: 0.4,
              ),
            ),
            if (isActiveWord)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 28,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    
    if (widget.onWordTap != null) {
      chip = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => widget.onWordTap?.call(wordIndex),
        child: chip,
      );
    }
    
    return chip;
  }
  
  int _findLineForWord(int wordIndex) {
    for (int i = 0; i < widget.wordGroups.length; i++) {
      if (widget.wordGroups[i].contains(wordIndex)) {
        return i;
      }
    }
    return math.max(0, widget.wordGroups.length - 1);
  }
}

class _RailColors {
  final Color background;
  final Border? border;
  final List<BoxShadow>? shadow;

  const _RailColors({
    required this.background,
    this.border,
    this.shadow,
  });

  static _RailColors forState({
    required bool isCurrent,
    required bool isNext,
    required bool isPrevious,
    required bool completed,
  }) {
    if (isCurrent) {
      return _RailColors(
        background: Colors.white,
        border: Border.all(color: const Color(0xFFDAD1FF), width: 2),
        shadow: const [
          BoxShadow(
            color: Color(0x145245FF),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      );
    }
    
    if (isNext || isPrevious) {
      return _RailColors(
        background: Colors.white.withOpacity(0.45),
        border: Border.all(color: Colors.grey.shade300.withOpacity(0.7)),
      );
    }

    if (completed) {
      return _RailColors(
        background: Colors.white.withOpacity(0.3),
        border: Border.all(color: Colors.grey.shade400.withOpacity(0.35)),
      );
    }

    return _RailColors(
      background: Colors.white.withOpacity(0.25),
      border: Border.all(color: Colors.grey.shade300.withOpacity(0.3)),
    );
  }
}

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();
  
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

