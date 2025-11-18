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
  final Duration scrollDuration;
  
  const GroupedWordDisplay({
    Key? key,
    required this.displayWords,
    required this.wordGroups,
    required this.currentWordIndex,
    this.smoothProgress = 0.0,
    this.onWordTap,
    this.readingComplete = false,
    this.scrollWordIndex,
    this.scrollDuration = const Duration(milliseconds: 1000),
  }) : super(key: key);
  
  @override
  State<GroupedWordDisplay> createState() => _GroupedWordDisplayState();
}

class _GroupedWordDisplayState extends State<GroupedWordDisplay> {
  static const double _lineHeight = 130.0;
  static const EdgeInsets _listPadding = EdgeInsets.symmetric(vertical: 16, horizontal: 12);
  final ScrollController _scrollController = ScrollController();
  int _lastScrollTarget = -1;
  Timer? _scrollDebounce;
  
  @override
  void initState() {
    super.initState();
    _scheduleScroll(immediate: true);
  }
  
  @override
  void didUpdateWidget(GroupedWordDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentWordIndex != widget.currentWordIndex ||
        oldWidget.scrollWordIndex != widget.scrollWordIndex) {
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
      _scrollController.animateTo(
        targetOffset,
        duration: widget.scrollDuration,
        curve: Curves.easeInOutCubic,
      );
    } else {
      _scrollController.jumpTo(targetOffset);
    }
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _scrollDebounce?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final currentLineIndex = _findLineForWord(widget.currentWordIndex);
    final viewportHeight = _estimateViewportHeight();
    
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: SizedBox(
        height: viewportHeight,
        child: ScrollConfiguration(
          behavior: const _NoGlowScrollBehavior(),
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
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
        ),
      ),
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
    if (lineIndex < 0 || lineIndex >= widget.wordGroups.length) {
      return const SizedBox.shrink();
    }
    
    final wordIndices = widget.wordGroups[lineIndex];
    
    final completed = lineIndex < currentLineIndex;
    final bgColor = isCurrent
        ? Colors.blue.shade50
        : completed
            ? Colors.green.shade50
            : Colors.white;
    final borderColor = isCurrent
        ? Colors.blue.shade300
        : completed
            ? Colors.green.shade200
            : Colors.grey.shade200;
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCurrent ? 4 : 8, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isCurrent ? 2 : 1),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: Colors.blue.shade200.withOpacity(0.3),
                    offset: const Offset(0, 6),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Center(child: _buildLineWords(wordIndices)),
      ),
    );
  }
  
  Widget _buildLineWords(List<int> wordIndices) {
    if (wordIndices.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return LayoutBuilder(
      builder: (context, _) {
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final wordIdx in wordIndices) _buildWordChip(wordIdx),
          ],
        );
      },
    );
  }

  Widget _buildWordChip(int wordIndex) {
    if (wordIndex < 0 || wordIndex >= widget.displayWords.length) {
      return const SizedBox.shrink();
    }
    
    final distance = (wordIndex - widget.currentWordIndex).abs();
    final bool isActiveWord = !widget.readingComplete && wordIndex == widget.currentWordIndex;
    final bool isRead = wordIndex < widget.currentWordIndex ||
        (widget.readingComplete && wordIndex <= widget.currentWordIndex);
    
    Color textColor = Colors.grey.shade700;
    Color bgColor = Colors.transparent;
    FontWeight weight = FontWeight.w600;
    
    if (isActiveWord) {
      textColor = Colors.orange.shade900;
      bgColor = Colors.orange.shade100;
      weight = FontWeight.w700;
    } else if (!widget.readingComplete && distance == 1) {
      textColor = isRead ? Colors.orange.shade700 : Colors.blue.shade700;
      bgColor = (isRead ? Colors.orange : Colors.blue).shade50;
    } else if (!widget.readingComplete && distance == 2) {
      textColor = isRead ? Colors.orange.shade500 : Colors.blue.shade500;
    } else if (isRead) {
      textColor = Colors.green.shade700;
      bgColor = Colors.green.shade50;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        widget.displayWords[wordIndex],
        style: TextStyle(
          fontSize: 22,
          fontWeight: weight,
          color: textColor,
          letterSpacing: 0.4,
        ),
      ),
    );
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

