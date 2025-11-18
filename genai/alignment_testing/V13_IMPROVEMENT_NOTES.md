## V13 drift analysis and fix

### Problem we saw in the replay harness
- When Sherpa emitted a burst like “YOU ARE ADE…”, the tracker treated every new token as proof we should advance, even though those tokens corresponded to the exact words we had just predicted.
- Because word-count increases were applied wholesale, the Dart/Python tracker immediately jumped several words forward (e.g., after “You are Adalyn” it leaped to word 4 even though ground truth was still word 2).  
- Lowering the phonetic match threshold temporarily hid the issue, but it also caused false matches (e.g., “rain” anchoring to “your”), so it wasn’t a safe fix.

### Root cause
- `_apply_phonetic_anchors` advanced the index when tokens matched phonetically, **but we never deducted those matched words** from Sherpa’s total word-count delta.
- The tracker then saw the *same* tokens again via `word_increase` and advanced a second time.
- When Sherpa output included extra or mis-segmented syllables, the tracker also trusted the count blindly and could jump multiple words without any confirmation.

### Solution
1. **Count matched tokens**: `_apply_phonetic_anchors` now returns how many Sherpa tokens actually matched nearby script words. Those matches are subtracted from the Sherpa delta.
2. **Throttle unconfirmed catch-ups**: any remaining “residual” words (tokens that didn’t pass the phonetic check) are capped at `max_unconfirmed_catchup = 1`, so we only advance one unverified word per Sherpa burst.
3. **Keep the stricter phonetic threshold (0.68)** so only confident matches reset the anchor window.

### Why it works
- Deducting confirmed matches prevents “double advancement”—if Sherpa repeats “you are” we anchor once and ignore the redundant word-count increase.
- Limiting unverified catch-ups stops large jumps when Sherpa hallucinated or split a word awkwardly; the tracker now waits for VAD or another confirmed anchor.
- With these guards, the replay harness tracks the entire Adalyn recording with drift staying within ±1 word (worst case −3 when we lag briefly), eliminating the runaway “jump ahead” behavior seen previously.

