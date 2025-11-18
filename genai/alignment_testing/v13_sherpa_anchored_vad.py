#!/usr/bin/env python3
"""
V13 Sherpa-Anchored VAD tracker (Python parity with Dart implementation).

Two-phase flow:
1. Sherpa anchors/corrects position (trusted source of truth).
2. When anchored, VAD predicts the next script word instantly.
"""

from __future__ import annotations

import re
import sys
from collections import deque
from pathlib import Path
from typing import List

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

from test_phonetic_matching import word_to_phonemes, phonetic_similarity  # noqa:E402


def _sanitize_word(word: str) -> str:
    return re.sub(r'[^a-z]', '', (word or '').lower())


def _word_similarity(word_a: str, word_b: str) -> float:
    return phonetic_similarity(
        word_to_phonemes(word_a),
        word_to_phonemes(word_b),
    )


class V13SherpaAnchoredVAD:
    """Parity tracker for Dart V13 logic."""

    energy_threshold = 0.011
    onset_threshold = 0.007
    min_word_spacing = 0.30  # seconds
    min_silence_gap = 0.12   # seconds
    energy_history_size = 4
    max_predictions_before_lost_anchor = 5
    max_lookahead_words = 1
    phonetic_match_threshold = 0.68
    max_unconfirmed_catchup = 1

    def __init__(self, word_timings: List[dict], script_text: str, debug: bool = True):
        self.debug = debug
        self.word_timings = list(word_timings or [])
        self.script_text = script_text or ""

        raw_words = self._extract_script_words()
        self.display_words = raw_words
        self.script_words = [
            _sanitize_word(w) or w.lower()
            for w in raw_words
        ]

        self.total_words = len(self.script_words)

        if not self.word_timings:
            # Provide dummy timings if none are supplied.
            self.word_timings = [
                {"word": w, "start": 0.0, "end": 0.0}
                for w in self.script_words
            ]

        if len(self.word_timings) < self.total_words:
            last_end = self.word_timings[-1]["end"] if self.word_timings else 0.0
            for idx in range(len(self.word_timings), self.total_words):
                self.word_timings.append({
                    "word": self.script_words[idx],
                    "start": last_end,
                    "end": last_end,
                })

        # State
        self.current_word_idx = 0  # Next word to read
        self.estimated_time = 0.0

        # Anchor state
        self.is_anchored = False
        self.words_predicted_since_anchor = 0
        self.last_confirmed_word_idx = -1

        # Tracking stats
        self.vad_predictions = 0
        self.sherpa_anchors = 0
        self.sherpa_corrections = 0

        # VAD state
        self.energy_history = deque(maxlen=self.energy_history_size)
        self.is_speech = False
        self.last_onset_audio_time = 0.0
        self.last_silence_time = 0.0

        # Sherpa state
        self.last_sherpa_text = ""
        self.last_sherpa_word_count = 0

        # Calibration
        self.time_calibration_offset = 0.3

    def update(self, audio_chunk, audio_time: float, sherpa_text: str):
        """Feed 16 ms audio + latest Sherpa text; returns estimate tuple."""

        source = 'hold'
        confidence = 0.5

        if sherpa_text and sherpa_text != self.last_sherpa_text:
            sherpa_tokens = self._tokenize_sherpa_text(sherpa_text)
            new_word_count = len(sherpa_tokens)
            word_increase = new_word_count - self.last_sherpa_word_count
            new_tokens = sherpa_tokens[-word_increase:] if word_increase > 0 else []

            matched_words = 0
            anchored_by_similarity = False
            if word_increase > 0:
                matched_words = self._apply_phonetic_anchors(new_tokens)
                anchored_by_similarity = matched_words > 0
                residual_increase = max(0, word_increase - matched_words)
                if matched_words == 0:
                    residual_increase = min(residual_increase, self.max_unconfirmed_catchup)
                else:
                    residual_increase = residual_increase

                if self.words_predicted_since_anchor > word_increase:
                    correction = self.words_predicted_since_anchor - word_increase
                    self.current_word_idx = max(0, self.current_word_idx - correction)
                    self.sherpa_corrections += 1
                    source = 'sherpa_correction'
                    if self.debug:
                        print(f"  🔧 V13 Correction: -{correction} words "
                              f"(predicted {self.words_predicted_since_anchor}, Sherpa saw {word_increase})")
                elif self.words_predicted_since_anchor < residual_increase:
                    catch_up = residual_increase - self.words_predicted_since_anchor
                    self.current_word_idx = min(self.total_words, self.current_word_idx + catch_up)
                    source = 'sherpa_anchor' if self.words_predicted_since_anchor == 0 else 'sherpa_catchup'
                    if self.debug:
                        print(f"  📝 V13 Catch-up: +{catch_up} words (Sherpa ahead)")

                self.is_anchored = True
                self.words_predicted_since_anchor = 0
                self.sherpa_anchors += 1
                self.last_confirmed_word_idx = self.current_word_idx
                self.last_silence_time = self.last_onset_audio_time

                if self.debug and new_word_count <= 3:
                    last_word = sherpa_tokens[-1] if sherpa_tokens else ''
                    print(f"  ⚓ V13 Anchored at word {self.current_word_idx} (Sherpa: '{last_word}')")

                if anchored_by_similarity and (source == 'hold' or source.startswith('sherpa')):
                    source = 'sherpa_anchor'
                    confidence = 0.95
                elif source.startswith('sherpa'):
                    confidence = 0.9

            self.last_sherpa_text = sherpa_text
            self.last_sherpa_word_count = new_word_count

        onset = self._detect_onset(audio_chunk, audio_time)

        if onset and self.is_anchored and self.current_word_idx < self.total_words:
            has_confirmed = self.last_confirmed_word_idx >= 0
            max_allowed = (self.total_words if not has_confirmed
                           else min(self.total_words, self.last_confirmed_word_idx + self.max_lookahead_words))

            if has_confirmed and self.current_word_idx >= max_allowed:
                source = 'hold'
                confidence = 0.7
                if self.debug:
                    print(f"  🛑 V13 lookahead cap hit (idx {self.current_word_idx}, "
                          f"confirmed {self.last_confirmed_word_idx})")
            else:
                prev_idx = self.current_word_idx
                self.current_word_idx = min(self.total_words, self.current_word_idx + 1)
                self.vad_predictions += 1
                self.words_predicted_since_anchor += 1
                source = 'vad'
                confidence = 0.85

                if self.debug:
                    word_idx = min(prev_idx, len(self.script_words) - 1)
                    print(f"  ⚡ V13 VAD Predicts: word {word_idx} '{self.script_words[word_idx]}'")

                if self.words_predicted_since_anchor >= self.max_predictions_before_lost_anchor:
                    self.is_anchored = False
                    if self.debug:
                        print("  ⚠ V13 Lost anchor (too many predictions without confirmation)")

        self._update_estimated_time()

        return (self.estimated_time, self.current_word_idx, 0.0, source, confidence)

    # Internal helpers -----------------------------------------------------

    def _extract_script_words(self) -> List[str]:
        if isinstance(self.script_text, str) and self.script_text.strip():
            normalized = (self.script_text
                          .replace('—', ' ')
                          .replace('-', ' '))
            return [w.strip() for w in re.split(r'\s+', normalized) if w.strip()]
        return [
            (wt.get('word') or '').strip()
            for wt in self.word_timings
            if (wt.get('word') or '').strip()
        ]

    def _tokenize_sherpa_text(self, text: str) -> List[str]:
        sanitized = re.sub(r'[^a-z0-9\s]', ' ', text.lower())
        return [tok for tok in sanitized.split() if tok]

    def _apply_phonetic_anchors(self, new_tokens: List[str]) -> int:
        matched = 0
        for token in new_tokens:
            normalized = _sanitize_word(token)
            if not normalized:
                continue
            match_index = self._find_best_script_match(normalized)
            if match_index >= 0:
                prev_idx = self.current_word_idx
                self.current_word_idx = min(self.total_words, match_index + 1)
                self.last_confirmed_word_idx = match_index
                self.words_predicted_since_anchor = 0
                self.is_anchored = True
                matched += 1

                if self.debug:
                    print(f"  🔉 Phonetic anchor: '{normalized}' → "
                          f"script[{match_index}]='{self.script_words[match_index]}' "
                          f"(idx {prev_idx} → {self.current_word_idx})")
        return matched

    def _find_best_script_match(self, candidate: str) -> int:
        window_start = max(0, self.current_word_idx - 1)
        window_end = min(self.total_words - 1, self.current_word_idx + 1)

        best_score = 0.0
        best_index = -1

        for idx in range(window_start, window_end + 1):
            score = _word_similarity(candidate, self.script_words[idx])
            if score > best_score:
                best_score = score
                best_index = idx

        if best_score >= self.phonetic_match_threshold:
            if self.debug:
                print(f"  🔍 Phonetic window match '{candidate}' → script[{best_index}]="
                      f"'{self.script_words[best_index]}' (score={best_score:.2f})")
            return best_index

        if self.debug:
            print(f"  🔍 Phonetic window miss '{candidate}' (best={best_score:.2f}) "
                  f"around idx {self.current_word_idx}")
        return -1

    def _detect_onset(self, audio_chunk, audio_time: float) -> bool:
        if audio_chunk is None or len(audio_chunk) == 0:
            return False

        energy = float(np.sqrt(np.mean(audio_chunk ** 2)))
        self.energy_history.append(energy)

        if len(self.energy_history) < 3:
            return False

        was_speech = self.is_speech
        self.is_speech = energy > self.energy_threshold

        if not self.is_speech and was_speech:
            self.last_silence_time = audio_time

        if (not was_speech) and self.is_speech:
            time_since_last = audio_time - self.last_onset_audio_time
            time_since_silence = audio_time - self.last_silence_time

            if (time_since_last >= self.min_word_spacing and
                    time_since_silence >= self.min_silence_gap):
                avg_energy = float(sum(self.energy_history) / len(self.energy_history))

                hist = list(self.energy_history)
                energy_increasing = (
                    len(hist) >= 3 and
                    hist[-1] > hist[-2] * 0.8 and
                    hist[-2] > hist[-3] * 0.8
                )

                if avg_energy > self.onset_threshold:
                    if energy_increasing or avg_energy > self.onset_threshold * 1.5:
                        self.last_onset_audio_time = audio_time
                        return True

        return False

    def _update_estimated_time(self):
        if not self.word_timings:
            self.estimated_time = 0.0
            return
        idx = min(self.current_word_idx, len(self.word_timings) - 1)
        word_time = self.word_timings[idx]['start']
        self.estimated_time = word_time + self.time_calibration_offset


if __name__ == '__main__':
    print("V13 Sherpa-Anchored VAD tracker ready (Python parity build).")

