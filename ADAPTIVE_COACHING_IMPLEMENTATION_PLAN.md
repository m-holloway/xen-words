# Adaptive Speech Coaching: Implementation Plan

**Status**: Phase 0 Ready to Start  
**Last Updated**: November 11, 2025

---

## Vision Summary

Transform Xen Words from a speech recognition app into a **family learning ecosystem** where:
- Parents coach their children using intelligent pattern detection
- Voice morphing creates coaching in parent's voice (privacy-preserving)
- Progressive scaffolding adapts to each child's pronunciation journey

---

## User Priorities (From Clarifying Questions)

### 1. **Next Milestone**: Research First, Then Build
- **Phase 0A**: Voice morphing feasibility research (2-3 weeks)
- **Phase 0B**: Parent review interface MVP (6-8 weeks)

### 2. **Parent Review MVP Features**
- Word list with pattern detection
- Progress tracking over time
- Parent can record their own pronunciation
- Audio playback of child attempts
- Review/grading interface

### 3. **Voice Morphing**: Parallel Research Track
- Investigate while building other features
- Don't block on it, but explore feasibility

### 4. **Privacy Strategy**: Local First, Embedding-Based Cloud Optional
- All recordings stay local
- Offline voice morphing (5-10x slower than realtime OK)
- Cloud TTS: Send embedding vectors only (NOT raw audio)
- Zero retention policy
- Opt-in for improvement data (only when trust is built)

### 5. **Monetization**
- **Tier 1 (Premium)**: Parent review interface
- **Tier 2 (Premium+)**: Voice morphing
- Free tier: Basic game with ASR

---

## Phase 0A: Voice Morphing Research (2-3 weeks)

**Goal**: Determine if voice cloning is feasible on mobile devices with acceptable quality and performance.

### Week 1: Technology Evaluation

#### Task 1.1: Survey Voice Cloning Models
**Candidates**:
- **Fish Speech** (mentioned by user)
  - Architecture: ?
  - Mobile support: ?
  - Sample requirements: ?
  
- **Bark** (Suno AI)
  - Size: ~500 MB
  - Quality: High
  - Speed: Slow (may need NPU/GPU)
  
- **Piper TTS**
  - Size: ~50 MB
  - Quality: Good
  - Speed: Fast (CPU-friendly)
  - Voice cloning: Limited
  
- **Coqui TTS / XTTS**
  - Size: ~200 MB
  - Quality: Excellent
  - Voice cloning: Yes (5-10 seconds of audio)
  - Speed: Medium
  
- **Tortoise TTS**
  - Quality: Very high
  - Speed: Very slow (may be too slow even for background)
  
- **Wav2Vec2 + FastSpeech2**
  - Embedding extraction + TTS pipeline
  - Custom approach

**Deliverable**: Technology comparison matrix

| Model | Size | Quality | Speed | Samples Needed | Mobile Support | License |
|-------|------|---------|-------|----------------|----------------|---------|
| Fish Speech | ? | ? | ? | ? | ? | ? |
| Bark | 500 MB | High | Slow | 10-30s | iOS/Android (NPU) | MIT |
| Piper | 50 MB | Good | Fast | N/A (no cloning) | ✅ | MIT |
| Coqui XTTS | 200 MB | Excellent | Medium | 5-10s | ✅ | Apache 2.0 |
| Tortoise | 2 GB | Very High | Very Slow | 10s | ❌ (too slow) | Apache 2.0 |

#### Task 1.2: Build Proof-of-Concept (Python)
**Goal**: Test voice cloning quality before committing to mobile integration.

```python
# poc/voice_cloning_test.py

import torch
from TTS.api import TTS  # Coqui TTS

# Test with sample parent voice recordings
def test_voice_cloning():
    # Load model
    tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2")
    
    # Sample parent recording (10 seconds)
    parent_recording = "samples/parent_voice.wav"
    
    # Generate all sight words
    sight_words = ["all", "were", "see", "for", ...]
    
    for word in sight_words:
        output_path = f"output/{word}.wav"
        
        # Clone voice
        tts.tts_to_file(
            text=word,
            speaker_wav=parent_recording,
            file_path=output_path,
            language="en"
        )
        
        print(f"Generated: {word} ({time_elapsed}s)")
    
    # Measure:
    # - Generation time per word
    # - Quality (human evaluation)
    # - Minimum recording length needed
```

**Deliverable**: 
- 61 generated words in cloned voice
- Quality assessment (1-5 scale)
- Performance metrics (time per word)
- Minimum samples needed for good quality

### Week 2: Mobile Integration Feasibility

#### Task 2.1: Flutter/Dart Integration Options

**Option A: Native Plugin** (iOS: Core ML, Android: TFLite)
- Export model to ONNX/TFLite
- Create Flutter plugin
- Pros: Full control, best performance
- Cons: Most work, platform-specific

**Option B: FFI (Foreign Function Interface)**
- Compile TTS engine to native library
- Call from Dart via FFI
- Pros: Cross-platform
- Cons: Complex build setup

**Option C: Platform Channels**
- Implement TTS in native code (Swift/Kotlin)
- Bridge to Flutter
- Pros: Standard Flutter pattern
- Cons: Duplicated logic per platform

**Option D: Cloud-Based (Embedding Only)**
- Extract embedding on-device (small model)
- Send embedding to cloud TTS API
- Receive generated audio
- Pros: Fast, no large model on device
- Cons: Requires internet, privacy concerns (mitigated by embedding-only approach)

**Recommendation**: Start with **Option D** (cloud + embedding) for MVP, build **Option A** (native) for premium offline tier later.

#### Task 2.2: Embedding Extraction Model
**Goal**: Extract voice embedding on-device without full TTS model.

Candidates:
- **Resemblyzer** (~50 MB, speaker verification model)
- **TitaNet** (NVIDIA, speaker embedding)
- **Wav2Vec2** (Facebook, general audio embedding)

```dart
// lib/services/voice_embedding_extractor.dart

class VoiceEmbeddingExtractor {
  late Interpreter _interpreter;
  
  Future<void> initialize() async {
    // Load TFLite model for embedding extraction
    _interpreter = await Interpreter.fromAsset('models/resemblyzer.tflite');
  }
  
  Future<Float32List> extractEmbedding(String audioPath) async {
    // Load audio
    final audioData = await loadAudio(audioPath);
    
    // Preprocess
    final input = preprocessAudio(audioData);
    
    // Run inference
    var output = List.filled(256, 0.0).reshape([1, 256]);
    _interpreter.run(input, output);
    
    return Float32List.fromList(output[0]);
  }
  
  Future<Float32List> createVoiceProfile(List<String> recordings) async {
    // Average embeddings from multiple samples
    List<Float32List> embeddings = [];
    
    for (final recording in recordings) {
      final embedding = await extractEmbedding(recording);
      embeddings.add(embedding);
    }
    
    // Average
    return averageEmbeddings(embeddings);
  }
}
```

**Deliverable**:
- Embedding extractor working on iOS/Android
- Voice profile creation from 10 recordings
- Profile size measurement (~1-10 KB)

#### Task 2.3: Cloud TTS API (Privacy-Preserving)
**Goal**: Build stateless TTS service that accepts embeddings only.

```python
# cloud/tts_api.py

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import torch
from TTS.api import TTS

app = FastAPI()

# Load model once at startup
tts_model = TTS("tts_models/multilingual/multi-dataset/xtts_v2")

class TTSRequest(BaseModel):
    text: str
    embedding: list[float]  # 256-dimensional vector
    
@app.post("/synthesize")
async def synthesize(request: TTSRequest):
    """
    Generate speech from text + embedding.
    
    Privacy guarantees:
    - No audio stored
    - Embedding deleted after use
    - Zero retention policy
    - No logging of embeddings
    """
    try:
        # Generate speech using embedding
        audio = tts_model.tts_with_embedding(
            text=request.text,
            speaker_embedding=torch.tensor(request.embedding)
        )
        
        # Return audio (base64 or binary)
        return {
            "audio": encode_audio(audio),
            "format": "wav",
            "sample_rate": 22050
        }
        
    finally:
        # Explicitly clear embedding from memory
        del request.embedding
        
    # Note: No data persisted to disk or database
```

**Deliverable**:
- Working API endpoint
- Flutter client integration
- Privacy policy draft
- Performance testing (latency, throughput)

### Week 3: Quality Assessment & Decision

#### Task 3.1: User Testing
**Test with real parent voices**:
- Recruit 5-10 parents
- Record 10 words each
- Generate full sight word set (61 words)
- Quality assessment survey

**Metrics**:
- **Naturalness**: 1-5 scale (does it sound like a real person?)
- **Intelligibility**: 1-5 scale (can you understand it clearly?)
- **Similarity**: 1-5 scale (does it sound like the parent?)
- **Acceptability**: Would you use this with your child? (yes/no)

#### Task 3.2: Go/No-Go Decision

**Decision Criteria**:
- ✅ **Quality**: Average scores ≥ 4/5 on all metrics
- ✅ **Performance**: Generation time ≤ 20 seconds/word (background acceptable)
- ✅ **Privacy**: Embedding-only approach validated
- ✅ **Cost**: Cloud TTS cost ≤ $0.05/user/month (61 words @ $0.001/word = $0.06)

**Outcomes**:
1. **GO** → Proceed with voice morphing in Phase 2
2. **DEFER** → Build parent review MVP first, revisit voice morphing later
3. **PIVOT** → Use simpler approach (parent recordings only, no morphing)

### Research Phase Deliverables
- [ ] Technology comparison matrix
- [ ] Python PoC with quality assessment
- [ ] Mobile embedding extraction working
- [ ] Cloud TTS API functional
- [ ] User testing results
- [ ] Go/No-Go decision documented

---

## Phase 0B: Foundation (Parallel with Research, 4-6 weeks)

**Goal**: Build data infrastructure needed for parent review interface.

### Data Models & Storage

#### Task 0B.1: Define Domain Models (Week 1)

```dart
// lib/models/pronunciation_attempt.dart

class PronunciationAttempt {
  final String id;
  final String childId;
  final String word;
  final String recognizedText;
  final double asrConfidence;
  final double phoneticSimilarity;  // NEW: CMUdict-based similarity
  final DateTime timestamp;
  final String? audioFileId;
  final int attemptNumber;  // 1st, 2nd, 3rd attempt, etc.
  
  // Computed fields
  Duration? get timeSinceLastAttempt;
  bool get isCorrect => phoneticSimilarity >= 0.85;
  bool get isClose => phoneticSimilarity >= 0.65 && phoneticSimilarity < 0.85;
}

// lib/models/pronunciation_pattern.dart

class PronunciationPattern {
  final String word;
  final String substitution;  // What child says instead
  final List<PronunciationAttempt> attempts;
  final double avgPhoneticSimilarity;
  final bool isPersistent;  // 3+ attempts with same pattern
  final bool isImproving;   // Similarity increasing over time
  final double urgency;     // How urgently needs parent review (0-1)
  
  // Computed
  int get attemptCount => attempts.length;
  DateTime get firstAttempt => attempts.first.timestamp;
  DateTime get lastAttempt => attempts.last.timestamp;
  Duration get timeSpan => lastAttempt.difference(firstAttempt);
}

// lib/models/parent_review.dart

class ParentReview {
  final String id;
  final String childId;
  final String word;
  final List<String> attemptIds;
  final ReviewGrade grade;
  final List<IssueType> issues;
  final String coachingMessage;
  final String? parentRecordingId;
  final DateTime timestamp;
}

enum ReviewGrade {
  CORRECT_GIVE_CREDIT,
  CLOSE_NEEDS_COACHING,
  PRACTICE_LATER,
  WRONG_WORD,
}

enum IssueType {
  VOWEL_SOUND,
  CONSONANT_SOUND,
  MISSING_FINAL_CONSONANT,
  STRESS_EMPHASIS,
  TOO_FAST,
  TOO_SLOW,
  UNCLEAR,
}
```

#### Task 0B.2: SQLite Database Schema (Week 1)

```sql
-- schema.sql

CREATE TABLE pronunciation_attempts (
  id TEXT PRIMARY KEY,
  child_id TEXT NOT NULL,
  word TEXT NOT NULL,
  recognized_text TEXT NOT NULL,
  asr_confidence REAL NOT NULL,
  phonetic_similarity REAL NOT NULL,
  timestamp INTEGER NOT NULL,
  audio_file_id TEXT,
  attempt_number INTEGER NOT NULL,
  FOREIGN KEY (audio_file_id) REFERENCES audio_files(id)
);

CREATE INDEX idx_attempts_child_word ON pronunciation_attempts(child_id, word);
CREATE INDEX idx_attempts_timestamp ON pronunciation_attempts(timestamp DESC);

CREATE TABLE audio_files (
  id TEXT PRIMARY KEY,
  file_path TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  codec TEXT NOT NULL,
  sample_rate INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE parent_reviews (
  id TEXT PRIMARY KEY,
  child_id TEXT NOT NULL,
  word TEXT NOT NULL,
  grade TEXT NOT NULL,
  issues TEXT,  -- JSON array
  coaching_message TEXT,
  parent_recording_id TEXT,
  timestamp INTEGER NOT NULL,
  FOREIGN KEY (parent_recording_id) REFERENCES audio_files(id)
);

CREATE TABLE review_attempts (
  review_id TEXT NOT NULL,
  attempt_id TEXT NOT NULL,
  PRIMARY KEY (review_id, attempt_id),
  FOREIGN KEY (review_id) REFERENCES parent_reviews(id),
  FOREIGN KEY (attempt_id) REFERENCES pronunciation_attempts(id)
);

CREATE TABLE children (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  birth_date INTEGER,
  created_at INTEGER NOT NULL
);

CREATE TABLE parent_recordings (
  id TEXT PRIMARY KEY,
  parent_id TEXT NOT NULL,
  word TEXT NOT NULL,
  audio_file_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (audio_file_id) REFERENCES audio_files(id)
);
```

#### Task 0B.3: Repository Implementation (Week 2)

```dart
// lib/repositories/pronunciation_repository.dart

class PronunciationRepository {
  final Database _db;
  
  Future<void> saveAttempt(PronunciationAttempt attempt) async {
    await _db.insert('pronunciation_attempts', attempt.toMap());
  }
  
  Future<List<PronunciationPattern>> detectPatterns(String childId) async {
    // Group attempts by word
    final attempts = await getAttempts(childId);
    final byWord = groupBy(attempts, (a) => a.word);
    
    List<PronunciationPattern> patterns = [];
    
    for (final word in byWord.keys) {
      final wordAttempts = byWord[word]!;
      
      // Look for substitution patterns
      final substitutions = wordAttempts
          .where((a) => !a.isCorrect)
          .map((a) => a.recognizedText)
          .toList();
      
      if (substitutions.isEmpty) continue;
      
      // Find most common substitution
      final mostCommon = mode(substitutions);
      final occurrences = substitutions.where((s) => s == mostCommon).length;
      
      if (occurrences >= 2) {  // Pattern threshold
        patterns.add(PronunciationPattern(
          word: word,
          substitution: mostCommon,
          attempts: wordAttempts,
          avgPhoneticSimilarity: average(wordAttempts.map((a) => a.phoneticSimilarity)),
          isPersistent: occurrences >= 3,
          isImproving: _checkImprovement(wordAttempts),
          urgency: _calculateUrgency(wordAttempts, occurrences),
        ));
      }
    }
    
    return patterns;
  }
  
  double _calculateUrgency(List<PronunciationAttempt> attempts, int occurrences) {
    // Factors:
    // - Persistence (more attempts = more urgent)
    // - Recency (recent attempts = more urgent)
    // - Lack of improvement (plateau = more urgent)
    
    final persistenceScore = min(occurrences / 10.0, 1.0);
    final recencyScore = _calculateRecency(attempts.last.timestamp);
    final improvementScore = _checkImprovement(attempts) ? 0.0 : 1.0;
    
    return (persistenceScore * 0.4 + recencyScore * 0.3 + improvementScore * 0.3);
  }
  
  bool _checkImprovement(List<PronunciationAttempt> attempts) {
    if (attempts.length < 3) return false;
    
    // Linear regression on phonetic similarity over time
    final similarities = attempts.map((a) => a.phoneticSimilarity).toList();
    final slope = linearRegressionSlope(similarities);
    
    return slope > 0.02;  // Improving if slope > 2% per attempt
  }
}
```

### Phonetic Similarity Calculation

#### Task 0B.4: CMUdict Integration (Week 2-3)

**Goal**: Calculate phonetic distance between recognized text and target word.

```dart
// lib/services/phonetic_analyzer.dart

class PhoneticAnalyzer {
  late Map<String, List<String>> _cmudict;
  
  Future<void> initialize() async {
    // Load CMUdict from assets
    final cmudictText = await rootBundle.loadString('assets/cmudict.txt');
    _cmudict = parseCMUdict(cmudictText);
  }
  
  double calculateSimilarity(String recognized, String target) {
    final recognizedPhonemes = _cmudict[recognized.toLowerCase()];
    final targetPhonemes = _cmudict[target.toLowerCase()];
    
    if (recognizedPhonemes == null || targetPhonemes == null) {
      // Fallback to string similarity
      return _levenshteinSimilarity(recognized, target);
    }
    
    // Calculate phoneme edit distance
    final distance = _phonemeEditDistance(recognizedPhonemes, targetPhonemes);
    final maxLen = max(recognizedPhonemes.length, targetPhonemes.length);
    
    return 1.0 - (distance / maxLen);
  }
  
  int _phonemeEditDistance(List<String> a, List<String> b) {
    // Levenshtein distance on phoneme sequences
    // But with phoneme-specific costs
    
    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    
    for (int i = 0; i <= m; i++) dp[i][0] = i;
    for (int j = 0; j <= n; j++) dp[0][j] = j;
    
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i-1] == b[j-1]) {
          dp[i][j] = dp[i-1][j-1];  // Match
        } else {
          final substitutionCost = _phonemeSubstitutionCost(a[i-1], b[j-1]);
          
          dp[i][j] = min3(
            dp[i-1][j] + 1,                    // Deletion
            dp[i][j-1] + 1,                    // Insertion
            dp[i-1][j-1] + substitutionCost,   // Substitution
          );
        }
      }
    }
    
    return dp[m][n];
  }
  
  double _phonemeSubstitutionCost(String p1, String p2) {
    // Some substitutions are more similar than others
    // e.g., AO (all) → OW (oh) is closer than AO → IY (ee)
    
    // Simplified: group phonemes by type
    final vowels = {'AA', 'AE', 'AH', 'AO', 'AW', 'AY', 'EH', 'ER', 'EY', 'IH', 'IY', 'OW', 'OY', 'UH', 'UW'};
    final consonants = {...};  // All others
    
    if (vowels.contains(p1) && vowels.contains(p2)) {
      return 0.5;  // Vowel-vowel substitution (more forgivable)
    } else if (consonants.contains(p1) && consonants.contains(p2)) {
      return 0.7;  // Consonant-consonant
    } else {
      return 1.0;  // Vowel-consonant (very different)
    }
  }
  
  List<PhonemeSubstitution> identifySubstitutions(String recognized, String target) {
    // Align phonemes and identify where they differ
    final recognizedPhonemes = _cmudict[recognized.toLowerCase()] ?? [];
    final targetPhonemes = _cmudict[target.toLowerCase()] ?? [];
    
    final alignment = _alignPhonemes(recognizedPhonemes, targetPhonemes);
    
    return alignment.where((a) => a.isDifferent).toList();
  }
}

class PhonemeSubstitution {
  final int position;
  final String? recognized;  // null if missing
  final String expected;
  final String type;  // 'vowel', 'consonant', 'stress'
  
  bool get isDifferent => recognized != expected;
  bool get isMissing => recognized == null;
}
```

### Audio Recording Infrastructure

#### Task 0B.5: Recording on Recognition Attempts (Week 3)

**Challenge**: We already have audio stream for Sherpa-ONNX. How do we save it?

**Approach**: Circular buffer + save on recognition result.

```dart
// lib/services/audio_recorder.dart

class AudioRecorder {
  final int sampleRate = 16000;
  final int maxBufferSeconds = 5;  // Keep last 5 seconds
  
  late CircularBuffer<Int16List> _buffer;
  bool _isRecording = false;
  
  void startRecording() {
    _buffer = CircularBuffer<Int16List>(
      capacity: maxBufferSeconds * sampleRate ~/ 1024,  // Assuming 1024 samples per chunk
    );
    _isRecording = true;
  }
  
  void onAudioChunk(Uint8List audioData) {
    if (!_isRecording) return;
    
    // Convert to Int16
    final int16Data = _convertToInt16(audioData);
    _buffer.add(int16Data);
  }
  
  Future<String> saveRecording(String attemptId) async {
    // Extract all buffered audio
    final allChunks = _buffer.toList();
    final combinedAudio = _combineChunks(allChunks);
    
    // Encode to Opus
    final opusData = await _encodeOpus(combinedAudio);
    
    // Save to file
    final fileName = '$attemptId.opus';
    final filePath = await _saveToDisk(fileName, opusData);
    
    return filePath;
  }
  
  void stopRecording() {
    _isRecording = false;
    _buffer.clear();
  }
}
```

**Integration with Sherpa Recognizer**:

```dart
// lib/services/sherpa_recognizer.dart (additions)

class SherpaRecognizer {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final PronunciationRepository _repository = PronunciationRepository();
  
  Future<void> startListening() async {
    // Start audio recording
    _audioRecorder.startRecording();
    
    // Existing Sherpa setup...
  }
  
  void _processAudioData(Uint8List audioData) {
    // Feed to audio recorder
    _audioRecorder.onAudioChunk(audioData);
    
    // Existing Sherpa processing...
  }
  
  void _onRecognitionResult(String result) {
    // Save recording
    final attemptId = _uuid.v4();
    final audioFileId = await _audioRecorder.saveRecording(attemptId);
    
    // Calculate phonetic similarity
    final similarity = _phoneticAnalyzer.calculateSimilarity(result, _expectedWord);
    
    // Save attempt to database
    final attempt = PronunciationAttempt(
      id: attemptId,
      childId: _currentChild,
      word: _expectedWord,
      recognizedText: result,
      asrConfidence: _lastConfidence,
      phoneticSimilarity: similarity,
      timestamp: DateTime.now(),
      audioFileId: audioFileId,
      attemptNumber: await _repository.getAttemptCount(_currentChild, _expectedWord) + 1,
    );
    
    await _repository.saveAttempt(attempt);
    
    // Existing game logic...
  }
}
```

#### Task 0B.6: Audio Storage Management (Week 4)

```dart
// lib/services/audio_storage_manager.dart

class AudioStorageManager {
  static const int MAX_RECORDINGS_PER_WORD = 10;
  static const Duration RETENTION_PERIOD = Duration(days: 90);
  
  Future<void> cleanup() async {
    // Get all attempts
    final attempts = await _repository.getAllAttempts();
    
    // Group by word
    final byWord = groupBy(attempts, (a) => a.word);
    
    List<String> toDelete = [];
    
    for (final word in byWord.keys) {
      final wordAttempts = byWord[word]!
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));  // Newest first
      
      for (int i = 0; i < wordAttempts.length; i++) {
        final attempt = wordAttempts[i];
        
        // Keep if:
        // 1. Has parent review
        final hasReview = await _repository.hasReview(attempt.id);
        if (hasReview) continue;
        
        // 2. Within retention period
        final age = DateTime.now().difference(attempt.timestamp);
        if (age < RETENTION_PERIOD) continue;
        
        // 3. Within top N per word
        if (i < MAX_RECORDINGS_PER_WORD) continue;
        
        // Otherwise, mark for deletion
        if (attempt.audioFileId != null) {
          toDelete.add(attempt.audioFileId!);
        }
      }
    }
    
    // Delete files
    for (final fileId in toDelete) {
      await _deleteAudioFile(fileId);
    }
    
    AppLogger.speech.i('Cleaned up ${toDelete.length} old recordings');
  }
  
  Future<StorageStats> getStats(String childId) async {
    final attempts = await _repository.getAttempts(childId);
    final audioFiles = attempts
        .where((a) => a.audioFileId != null)
        .map((a) => a.audioFileId!)
        .toSet();
    
    int totalSize = 0;
    for (final fileId in audioFiles) {
      final file = await _getAudioFile(fileId);
      totalSize += file.lengthSync();
    }
    
    return StorageStats(
      attemptCount: attempts.length,
      audioFileCount: audioFiles.length,
      totalSizeBytes: totalSize,
      totalSizeMB: (totalSize / 1024 / 1024).toStringAsFixed(2),
    );
  }
}
```

### Privacy Framework

#### Task 0B.7: Privacy Policy & Consent Flow (Week 5)

**Deliverables**:
1. Privacy policy (legal review recommended)
2. Parental consent screen
3. Data export functionality
4. Data deletion functionality

```dart
// lib/screens/privacy_consent_screen.dart

class PrivacyConsentScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Privacy & Data')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Child\'s Privacy Matters',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 16),
            
            _buildSection(
              icon: Icons.phone_android,
              title: 'Local First',
              description: 'All recordings stay on your device. No data uploaded without permission.',
            ),
            
            _buildSection(
              icon: Icons.lock,
              title: 'Secure Storage',
              description: 'Audio files are encrypted and only accessible by you.',
            ),
            
            _buildSection(
              icon: Icons.delete,
              title: 'You Control the Data',
              description: 'Export or delete all data anytime.',
            ),
            
            SizedBox(height: 24),
            
            Text(
              'Features That Use Recordings:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            
            SwitchListTile(
              title: Text('Parent Review'),
              subtitle: Text('Save recordings for parent review of near-misses'),
              value: _enableRecording,
              onChanged: (value) {
                setState(() => _enableRecording = value);
              },
            ),
            
            SwitchListTile(
              title: Text('Voice Coaching (Premium)'),
              subtitle: Text('Record your voice to create personalized coaching'),
              value: _enableVoiceCoaching,
              onChanged: (value) {
                setState(() => _enableVoiceCoaching = value);
              },
            ),
            
            Divider(),
            
            ListTile(
              leading: Icon(Icons.download),
              title: Text('Export My Data'),
              onTap: _exportData,
            ),
            
            ListTile(
              leading: Icon(Icons.delete_forever),
              title: Text('Delete All Data'),
              onTap: _confirmDeleteAll,
            ),
            
            SizedBox(height: 24),
            
            ElevatedButton(
              onPressed: _saveSettings,
              child: Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Foundation Phase Deliverables
- [ ] Data models defined and implemented
- [ ] SQLite database schema created
- [ ] Repository with pattern detection
- [ ] Phonetic analyzer working
- [ ] Audio recording on attempts
- [ ] Storage management with cleanup
- [ ] Privacy consent flow
- [ ] Data export/delete functionality

---

## Phase 1: Parent Review Interface MVP (6-8 weeks)

**Goal**: Parents can review patterns and coach their children.

### Week 1-2: Dashboard UI

#### Task 1.1: Parent Mode Entry

```dart
// lib/screens/home_screen.dart (add parent mode button)

// Secret gesture: Long press on settings icon for 3 seconds
GestureDetector(
  onLongPressStart: (_) => _startParentModeTimer(),
  onLongPressEnd: (_) => _cancelParentModeTimer(),
  child: IconButton(
    icon: Icon(Icons.settings),
    onPressed: () {/* Normal settings */},
  ),
)

void _startParentModeTimer() {
  _parentModeTimer = Timer(Duration(seconds: 3), () {
    _showParentAuthentication();
  });
}

void _showParentAuthentication() {
  // Show PIN or biometric prompt
  showDialog(
    context: context,
    builder: (context) => ParentAuthDialog(),
  );
}
```

#### Task 1.2: Word List with Patterns

```dart
// lib/screens/parent_dashboard_screen.dart

class ParentDashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${childName}\'s Progress'),
      ),
      body: FutureBuilder<List<PronunciationPattern>>(
        future: _repository.detectPatterns(childId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return CircularProgressIndicator();
          
          final patterns = snapshot.data!
            ..sort((a, b) => b.urgency.compareTo(a.urgency));  // Most urgent first
          
          return ListView.builder(
            itemCount: patterns.length,
            itemBuilder: (context, index) {
              final pattern = patterns[index];
              return _buildPatternCard(pattern);
            },
          );
        },
      ),
    );
  }
  
  Widget _buildPatternCard(PronunciationPattern pattern) {
    return Card(
      margin: EdgeInsets.all(8),
      child: ListTile(
        leading: _buildUrgencyIndicator(pattern.urgency),
        title: Text(
          pattern.word.toUpperCase(),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text('Says: "${pattern.substitution}"'),
            SizedBox(height: 4),
            Text('${pattern.attemptCount} attempts, ${(pattern.avgPhoneticSimilarity * 100).round()}% similar'),
            if (pattern.isPersistent)
              Chip(
                label: Text('Persistent pattern'),
                backgroundColor: Colors.orange.shade100,
              ),
            if (pattern.isImproving)
              Chip(
                label: Text('Improving ✓'),
                backgroundColor: Colors.green.shade100,
              ),
          ],
        ),
        trailing: Icon(Icons.arrow_forward),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PatternDetailScreen(pattern: pattern),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildUrgencyIndicator(double urgency) {
    Color color;
    IconData icon;
    
    if (urgency >= 0.7) {
      color = Colors.red;
      icon = Icons.priority_high;
    } else if (urgency >= 0.4) {
      color = Colors.orange;
      icon = Icons.warning;
    } else {
      color = Colors.blue;
      icon = Icons.info;
    }
    
    return CircleAvatar(
      backgroundColor: color,
      child: Icon(icon, color: Colors.white),
    );
  }
}
```

### Week 3-4: Pattern Detail & Review

#### Task 1.3: Audio Playback Interface

```dart
// lib/screens/pattern_detail_screen.dart

class PatternDetailScreen extends StatefulWidget {
  final PronunciationPattern pattern;
  
  @override
  _PatternDetailScreenState createState() => _PatternDetailScreenState();
}

class _PatternDetailScreenState extends State<PatternDetailScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  int _currentAttemptIndex = 0;
  
  @override
  Widget build(BuildContext context) {
    final attempt = widget.pattern.attempts[_currentAttemptIndex];
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Review: ${widget.pattern.word}'),
      ),
      body: Column(
        children: [
          // Progress indicator
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Attempt ${_currentAttemptIndex + 1} of ${widget.pattern.attemptCount}'),
                Text(_formatTimestamp(attempt.timestamp)),
              ],
            ),
          ),
          
          // Audio playback
          Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Listen to what ${childName} said:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: 16),
                  
                  // Waveform visualization (optional)
                  Container(
                    height: 60,
                    child: _buildWaveform(attempt.audioFileId),
                  ),
                  
                  SizedBox(height: 16),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(Icons.play_arrow, size: 48),
                        onPressed: () => _playAttempt(attempt),
                      ),
                      SizedBox(width: 16),
                      IconButton(
                        icon: Icon(Icons.replay, size: 32),
                        onPressed: () => _playAttempt(attempt),
                      ),
                    ],
                  ),
                  
                  Divider(),
                  
                  Text(
                    'Compare with correct pronunciation:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: 8),
                  
                  ElevatedButton.icon(
                    icon: Icon(Icons.volume_up),
                    label: Text('Play "${widget.pattern.word}"'),
                    onPressed: () => _playCorrectPronunciation(widget.pattern.word),
                  ),
                  
                  SizedBox(height: 8),
                  
                  Text(
                    'Recognized as: "${attempt.recognizedText}"',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                  Text(
                    'Similarity: ${(attempt.phoneticSimilarity * 100).round()}%',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          
          // Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                icon: Icon(Icons.arrow_back),
                label: Text('Previous'),
                onPressed: _currentAttemptIndex > 0 ? _previousAttempt : null,
              ),
              TextButton.icon(
                icon: Icon(Icons.arrow_forward),
                label: Text('Next'),
                onPressed: _currentAttemptIndex < widget.pattern.attemptCount - 1 
                    ? _nextAttempt 
                    : null,
              ),
            ],
          ),
          
          Spacer(),
          
          // Review actions
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'What would you like to do?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: 16),
                
                _buildReviewButton(
                  grade: ReviewGrade.CORRECT_GIVE_CREDIT,
                  icon: Icons.check_circle,
                  label: 'Actually Correct',
                  subtitle: 'Give credit for this word',
                  color: Colors.green,
                ),
                
                _buildReviewButton(
                  grade: ReviewGrade.CLOSE_NEEDS_COACHING,
                  icon: Icons.school,
                  label: 'Close - Needs Coaching',
                  subtitle: 'Add coaching message',
                  color: Colors.orange,
                ),
                
                _buildReviewButton(
                  grade: ReviewGrade.PRACTICE_LATER,
                  icon: Icons.schedule,
                  label: 'Practice Later',
                  subtitle: 'Not ready yet',
                  color: Colors.blue,
                ),
                
                _buildReviewButton(
                  grade: ReviewGrade.WRONG_WORD,
                  icon: Icons.cancel,
                  label: 'Wrong Word',
                  subtitle: 'Different word entirely',
                  color: Colors.red,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _playAttempt(PronunciationAttempt attempt) async {
    if (attempt.audioFileId == null) return;
    
    final audioFile = await _repository.getAudioFile(attempt.audioFileId!);
    await _audioPlayer.play(DeviceFileSource(audioFile.filePath));
  }
  
  Future<void> _playCorrectPronunciation(String word) async {
    // Use existing TTS
    final audioPath = 'assets/audio/words/${word.toLowerCase()}.mp3';
    await _audioPlayer.play(AssetSource(audioPath));
  }
}
```

#### Task 1.4: Coaching Interface

```dart
// lib/screens/coaching_input_screen.dart

class CoachingInputScreen extends StatefulWidget {
  final PronunciationPattern pattern;
  final ReviewGrade grade;
  
  @override
  _CoachingInputScreenState createState() => _CoachingInputScreenState();
}

class _CoachingInputScreenState extends State<CoachingInputScreen> {
  Set<IssueType> _selectedIssues = {};
  TextEditingController _messageController = TextEditingController();
  String? _parentRecordingId;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add Coaching'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What needs work?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 16),
            
            Wrap(
              spacing: 8,
              children: IssueType.values.map((issue) {
                return FilterChip(
                  label: Text(_issueLabel(issue)),
                  selected: _selectedIssues.contains(issue),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedIssues.add(issue);
                      } else {
                        _selectedIssues.remove(issue);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            
            SizedBox(height: 24),
            
            Text(
              'Coaching message for ${childName}:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 8),
            
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g., "Try opening your mouth wider for the \'ah\' sound"',
                border: OutlineInputBorder(),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Quick suggestions
            Text('Suggestions:', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: _generateSuggestions(widget.pattern).map((suggestion) {
                return ActionChip(
                  label: Text(suggestion),
                  onPressed: () {
                    _messageController.text = suggestion;
                  },
                );
              }).toList(),
            ),
            
            SizedBox(height: 24),
            
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Record your pronunciation (Optional):',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 8),
                    Text(
                      '${childName} will hear your voice saying "${widget.pattern.word}"',
                      style: TextStyle(color: Colors.grey),
                    ),
                    SizedBox(height: 16),
                    
                    if (_parentRecordingId == null)
                      ElevatedButton.icon(
                        icon: Icon(Icons.mic),
                        label: Text('Record My Voice'),
                        onPressed: _recordParentVoice,
                      )
                    else
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Recording saved'),
                          Spacer(),
                          IconButton(
                            icon: Icon(Icons.play_arrow),
                            onPressed: _playbackParentRecording,
                          ),
                          IconButton(
                            icon: Icon(Icons.delete),
                            onPressed: () {
                              setState(() => _parentRecordingId = null);
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveReview,
                child: Text('Save Review'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  List<String> _generateSuggestions(PronunciationPattern pattern) {
    // Generate coaching suggestions based on pattern
    // This could be LLM-powered in the future
    
    final suggestions = <String>[];
    
    if (pattern.word == 'all' && pattern.substitution.contains('oh')) {
      suggestions.add('Open your mouth wider and say "aww" like when you see something cute');
      suggestions.add('Say "aww" then add "l" at the end');
      suggestions.add('Think of the word "fall" - it\'s the same sound');
    }
    
    // Generic suggestions
    suggestions.add('Let\'s practice this word together');
    suggestions.add('You\'re very close! Just need a small adjustment');
    suggestions.add('Try saying it slowly first, then faster');
    
    return suggestions;
  }
  
  Future<void> _recordParentVoice() async {
    // Show recording dialog
    final recordingId = await showDialog<String>(
      context: context,
      builder: (context) => ParentRecordingDialog(word: widget.pattern.word),
    );
    
    if (recordingId != null) {
      setState(() => _parentRecordingId = recordingId);
    }
  }
  
  Future<void> _saveReview() async {
    final review = ParentReview(
      id: _uuid.v4(),
      childId: childId,
      word: widget.pattern.word,
      attemptIds: widget.pattern.attempts.map((a) => a.id).toList(),
      grade: widget.grade,
      issues: _selectedIssues.toList(),
      coachingMessage: _messageController.text,
      parentRecordingId: _parentRecordingId,
      timestamp: DateTime.now(),
    );
    
    await _repository.saveReview(review);
    
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Review saved! ${childName} will see your coaching next time.')),
    );
  }
}
```

### Week 5-6: Parent Voice Recording

#### Task 1.5: Recording Interface

```dart
// lib/widgets/parent_recording_dialog.dart

class ParentRecordingDialog extends StatefulWidget {
  final String word;
  
  @override
  _ParentRecordingDialogState createState() => _ParentRecordingDialogState();
}

class _ParentRecordingDialogState extends State<ParentRecordingDialog> {
  RecordingState _state = RecordingState.READY;
  Record _recorder = Record();
  String? _recordingPath;
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Record: ${widget.word}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Say the word "${widget.word}" clearly'),
          SizedBox(height: 24),
          
          if (_state == RecordingState.READY)
            ElevatedButton.icon(
              icon: Icon(Icons.mic, size: 32),
              label: Text('Start Recording'),
              onPressed: _startRecording,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          
          if (_state == RecordingState.RECORDING)
            Column(
              children: [
                Icon(Icons.fiber_manual_record, color: Colors.red, size: 48),
                SizedBox(height: 8),
                Text('Recording...', style: TextStyle(color: Colors.red)),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _stopRecording,
                  child: Text('Stop'),
                ),
              ],
            ),
          
          if (_state == RecordingState.COMPLETE)
            Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 48),
                SizedBox(height: 8),
                Text('Recording complete!'),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.play_arrow),
                      onPressed: _playback,
                    ),
                    IconButton(
                      icon: Icon(Icons.replay),
                      onPressed: _reset,
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        if (_state == RecordingState.COMPLETE)
          ElevatedButton(
            onPressed: _save,
            child: Text('Use This Recording'),
          ),
      ],
    );
  }
  
  Future<void> _startRecording() async {
    final path = await getTemporaryDirectory();
    _recordingPath = '${path.path}/${_uuid.v4()}.wav';
    
    await _recorder.start(
      path: _recordingPath!,
      encoder: AudioEncoder.wav,
      samplingRate: 16000,
    );
    
    setState(() => _state = RecordingState.RECORDING);
  }
  
  Future<void> _stopRecording() async {
    await _recorder.stop();
    setState(() => _state = RecordingState.COMPLETE);
  }
  
  Future<void> _save() async {
    // Save to permanent storage
    final recordingId = await _repository.saveParentRecording(
      parentId: currentParentId,
      word: widget.word,
      audioPath: _recordingPath!,
    );
    
    Navigator.pop(context, recordingId);
  }
}

enum RecordingState {
  READY,
  RECORDING,
  COMPLETE,
}
```

### Week 7: Coaching Moments in Game

#### Task 1.6: Integrate Coaching into Game Flow

```dart
// lib/services/game_controller.dart (additions)

class GameController {
  Future<void> onWrongWord(String word, String recognized) async {
    // Check if parent has reviewed this word
    final review = await _repository.getReview(currentChild, word);
    
    if (review != null && review.grade == ReviewGrade.CLOSE_NEEDS_COACHING) {
      // Show coaching moment!
      await _showCoachingMoment(review);
    } else {
      // Standard wrong word flow
      await _playMissSound();
    }
  }
  
  Future<void> _showCoachingMoment(ParentReview review) async {
    AppLogger.game.i('🎓 Showing coaching moment for: ${review.word}');
    
    // 1. Pause game
    setState(GameState.coaching);
    
    // 2. Show dialog with parent's coaching
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CoachingMomentDialog(review: review),
    );
    
    // 3. Resume game
    setState(GameState.playing);
  }
}

// lib/widgets/coaching_moment_dialog.dart

class CoachingMomentDialog extends StatelessWidget {
  final ParentReview review;
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '💡 Coaching Tip',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            
            Text(
              review.coachingMessage,
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            
            if (review.parentRecordingId != null) ...[
              SizedBox(height: 24),
              Text('Listen to your parent say it:'),
              SizedBox(height: 8),
              ElevatedButton.icon(
                icon: Icon(Icons.volume_up),
                label: Text('Play'),
                onPressed: () => _playParentRecording(review.parentRecordingId!),
              ),
            ],
            
            SizedBox(height: 24),
            
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Got it!'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Week 8: Testing & Polish

- User testing with 5-10 families
- Iterate based on feedback
- Performance optimization
- Bug fixes

### Phase 1 Deliverables
- [ ] Parent dashboard with word list
- [ ] Pattern detection and urgency scoring
- [ ] Audio playback interface
- [ ] Review/grading interface
- [ ] Coaching message input
- [ ] Parent voice recording
- [ ] Coaching moments in game
- [ ] User testing complete

---

## Phase 2: Voice Morphing Integration (8-12 weeks, parallel)

**Contingent on Phase 0A Research Results**

If research shows voice morphing is feasible:

### Week 1-2: TTS Engine Integration
- Select model based on research
- Create Flutter plugin or FFI bridge
- Test on iOS and Android

### Week 3-4: Voice Profile Creation
- UI for recording 10 words
- Embedding extraction
- Profile storage

### Week 5-7: Speech Generation
- Generate all 61 sight words
- Background generation pipeline
- Caching strategy

### Week 8-10: Cloud TTS (Optional)
- Build API
- Zero-retention infrastructure
- Privacy compliance

### Week 11-12: A/B Testing
- Compare parent voice vs standard TTS
- Measure engagement impact
- Refine quality

---

## Success Metrics

### Phase 0 (Research)
- [ ] Voice cloning quality ≥ 4/5
- [ ] Generation time ≤ 20s/word
- [ ] Go/No-Go decision made

### Phase 1 (Parent Review MVP)
- [ ] 80% of patterns flagged correctly
- [ ] Parents review at least 2 words/week
- [ ] 50% of parents record at least 1 word
- [ ] Coaching moments shown to child
- [ ] Storage usage < 20 MB per child

### Phase 2 (Voice Morphing)
- [ ] Parent voice profile creation rate ≥ 30%
- [ ] Generated speech quality ≥ 4/5
- [ ] Child engagement increase (measure session length)
- [ ] Premium conversion rate ≥ 10%

---

## Next Immediate Steps

### This Week:
1. ✅ Complete vision document (DONE)
2. ✅ Create implementation plan (DONE)
3. 🔲 **Add 'oh' → 'all' homophone mapping** (user mentioned this specifically)
4. 🔲 **Investigate audio stall issue** (user reported app stopped listening)
5. 🔲 Start Phase 0A research:
   - Survey voice cloning models
   - Build Python PoC

### Priority Actions:
1. **Fix immediate issues** (homophone, audio stall)
2. **Research voice morphing feasibility** (2-3 weeks)
3. **Build foundation** (data models, storage, phonetic analyzer)
4. **Start parent review MVP** (after research complete)

---

## Questions / Decisions Needed

1. **Privacy Policy Legal Review**: Do you want me to draft a full privacy policy, or should this be reviewed by a lawyer before finalizing?

2. **Premium Pricing**: What price points are you considering?
   - Tier 1 (Parent Review): $?/month
   - Tier 2 (Voice Morphing): $?/month
   
3. **Child Profiles**: Should the app support multiple children per family? (Sibling voice models?)

4. **Age Range**: What age range are we targeting? (affects UI complexity and coaching style)

5. **Platform Priority**: iOS first, Android first, or simultaneous?

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Voice morphing not feasible | High | Phase 0A research to validate early; fallback to parent recordings only |
| Storage too large | Medium | Aggressive cleanup policy; cloud storage option |
| Privacy concerns | High | Local-first architecture; embedding-only cloud; transparent policy |
| Parent adoption low | High | Clear value proposition; free trial; excellent UX |
| ASR still missing patterns | Medium | Parent reviews train the system over time; manual homophone additions |
| Audio stalls (current issue) | High | Investigate diagnostic logs; add heartbeat monitoring |

---

*This is a living document. Update as decisions are made and progress occurs.*

