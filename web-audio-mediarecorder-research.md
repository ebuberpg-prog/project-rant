# Web Audio API & MediaRecorder API Research Report
## For Browser-Based Voice-to-Text (OpenAI-Compatible API)

---

## 1. Capturing Audio from Microphone (getUserMedia + MediaRecorder)

### Core Flow
1. Request microphone access via `navigator.mediaDevices.getUserMedia()`
2. Pass the resulting `MediaStream` to `new MediaRecorder(stream, options)`
3. Collect data chunks via the `dataavailable` event
4. Combine chunks into a `Blob` on `stop`

### Basic Implementation

```javascript
class AudioRecorder {
  constructor() {
    this.mediaRecorder = null;
    this.audioChunks = [];
    this.stream = null;
    this.mimeType = this._getSupportedMimeType();
  }

  _getSupportedMimeType() {
    const types = [
      'audio/webm;codecs=opus',
      'audio/mp4;codecs=mp4a.40.2',
      'audio/webm',
      'audio/mp4',
    ];
    for (const type of types) {
      if (MediaRecorder.isTypeSupported(type)) {
        return type;
      }
    }
    return '';
  }

  async start() {
    try {
      // Request microphone with echo cancellation and noise suppression
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          sampleRate: 16000, // Optimal for speech-to-text
          channelCount: 1,   // Mono is sufficient for voice
        },
      });

      const options = {
        mimeType: this.mimeType,
        audioBitsPerSecond: 32000, // 32 kbps is plenty for speech
      };

      this.mediaRecorder = new MediaRecorder(this.stream, options);
      this.audioChunks = [];

      this.mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          this.audioChunks.push(event.data);
        }
      };

      this.mediaRecorder.onstop = () => {
        const audioBlob = new Blob(this.audioChunks, { type: this.mimeType });
        this._cleanup();
        // Handle the blob (see Section 3)
        this.onRecordingComplete?.(audioBlob);
      };

      this.mediaRecorder.onerror = (event) => {
        console.error('MediaRecorder error:', event.error);
        this._cleanup();
      };

      this.mediaRecorder.start(1000); // Emit data every 1s (optional)
      return true;
    } catch (err) {
      console.error('Failed to start recording:', err);
      // Common errors: NotAllowedError (permission denied), NotFoundError (no mic)
      return false;
    }
  }

  stop() {
    if (this.mediaRecorder?.state === 'recording') {
      this.mediaRecorder.stop();
      // Note: stream tracks are stopped in _cleanup after onstop fires
    }
  }

  _cleanup() {
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
      this.stream = null;
    }
    this.mediaRecorder = null;
  }
}

// Usage
const recorder = new AudioRecorder();
recorder.onRecordingComplete = (blob) => {
  console.log('Recording complete:', blob.size, 'bytes');
};

await recorder.start();
// ... later ...
recorder.stop();
```

### Key Configuration for Speech-to-Text

| Constraint | Recommended Value | Why |
|---|---|---|
| `sampleRate` | `16000` | Standard for acoustic models; captures full voice range |
| `channelCount` | `1` (mono) | Stereo doubles file size with no benefit for transcription |
| `echoCancellation` | `true` | Reduces feedback in speaker environments |
| `noiseSuppression` | `true` | Filters ambient noise |
| `autoGainControl` | `true` | Normalizes volume levels |

---

## 2. Best Practices for Real-Time Recording (Start/Stop/Pause)

### State Management

```javascript
class RecordingController {
  constructor() {
    this.state = 'inactive'; // 'inactive' | 'recording' | 'paused'
    this.mediaRecorder = null;
    this.chunks = [];
    this.startTime = 0;
    this.pausedDuration = 0;
  }

  async start() {
    if (this.state === 'recording') return;

    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    this.mediaRecorder = new MediaRecorder(stream, {
      mimeType: this._getMimeType(),
    });

    this.chunks = [];
    this.mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) this.chunks.push(e.data);
    };

    this.mediaRecorder.onstart = () => {
      this.state = 'recording';
      this.startTime = Date.now();
      this.onStateChange?.('recording');
    };

    this.mediaRecorder.onpause = () => {
      this.state = 'paused';
      this.pausedDuration += Date.now() - this.pauseStartTime;
      this.onStateChange?.('paused');
    };

    this.mediaRecorder.onresume = () => {
      this.state = 'recording';
      this.onStateChange?.('recording');
    };

    this.mediaRecorder.onstop = () => {
      this.state = 'inactive';
      const blob = new Blob(this.chunks, { type: this.mediaRecorder.mimeType });
      this._stopTracks();
      this.onStateChange?.('inactive');
      this.onComplete?.(blob, this.getDuration());
    };

    this.mediaRecorder.start();
  }

  pause() {
    if (this.mediaRecorder?.state === 'recording') {
      this.pauseStartTime = Date.now();
      this.mediaRecorder.pause();
    }
  }

  resume() {
    if (this.mediaRecorder?.state === 'paused') {
      this.mediaRecorder.resume();
    }
  }

  stop() {
    if (this.mediaRecorder?.state !== 'inactive') {
      this.mediaRecorder.stop();
    }
  }

  getDuration() {
    if (!this.startTime) return 0;
    return Date.now() - this.startTime - this.pausedDuration;
  }

  _stopTracks() {
    this.mediaRecorder?.stream?.getTracks().forEach(t => t.stop());
  }

  _getMimeType() {
    const types = ['audio/webm;codecs=opus', 'audio/mp4'];
    return types.find(t => MediaRecorder.isTypeSupported(t)) || '';
  }
}
```

### Critical Best Practices

1. **Always stop tracks after recording**: `stream.getTracks().forEach(t => t.stop())` — the red recording indicator in the browser tab stays on until all tracks are stopped.

2. **Handle the `inactive` state**: Calling `stop()` when already `inactive` throws `InvalidStateError`. Always check `mediaRecorder.state` first.

3. **Use `timeslice` for long recordings**: `start(1000)` emits a `dataavailable` event every 1000ms. This prevents memory buildup and enables partial uploads.

4. **Don't trust `isTypeSupported()` alone on iOS Safari**: Even when it returns `true`, `start()` can throw `NotSupportedError`. Wrap `start()` in `try/catch`.

5. **Request permissions early**: Browsers may deny autoplay-style mic access. Trigger `getUserMedia()` from a user gesture (button click).

6. **Single-chunk optimization**: If recordings are short (< 25MB for OpenAI), omit `timeslice` and let `stop()` emit one final blob:
   ```javascript
   this.mediaRecorder.start(); // No timeslice = one blob on stop
   ```

---

## 3. Converting Recorded Blob to Base64 for API Transmission

### Method 1: FileReader (Standard, All Browsers)

```javascript
function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => {
      // reader.result is "data:audio/webm;codecs=opus;base64,GkXfo..."
      const base64 = reader.result.split(',')[1];
      resolve(base64);
    };
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

// Usage
const base64Audio = await blobToBase64(audioBlob);
```

### Method 2: Response + btoa (Modern Browsers)

```javascript
async function blobToBase64Modern(blob) {
  const bytes = await blob.arrayBuffer();
  const binary = new Uint8Array(bytes);
  let base64 = '';
  // Process in chunks to avoid "Maximum call stack size exceeded"
  const chunkSize = 0x8000; // 32KB
  for (let i = 0; i < binary.length; i += chunkSize) {
    const chunk = binary.subarray(i, i + chunkSize);
    base64 += String.fromCharCode.apply(null, chunk);
  }
  return btoa(base64);
}
```

### Sending to OpenAI-Compatible API

```javascript
async function transcribeAudio(audioBlob, apiKey, endpoint) {
  // OpenAI accepts multipart/form-data, not base64, for /v1/audio/transcriptions
  const formData = new FormData();

  // Derive filename extension from MIME type
  const ext = audioBlob.type.includes('mp4') ? 'm4a'
    : audioBlob.type.includes('webm') ? 'webm'
    : audioBlob.type.includes('wav') ? 'wav'
    : 'webm';

  formData.append('file', audioBlob, `recording.${ext}`);
  formData.append('model', 'whisper-1');
  formData.append('language', 'en'); // Optional
  formData.append('response_format', 'json'); // or 'text', 'verbose_json'

  const response = await fetch(`${endpoint}/v1/audio/transcriptions`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      // Do NOT set Content-Type manually; browser sets it with boundary
    },
    body: formData,
  });

  if (!response.ok) {
    throw new Error(`Transcription failed: ${response.status} ${await response.text()}`);
  }

  return response.json(); // { text: "..." }
}

// If your API truly requires base64 (some custom endpoints):
async function sendBase64Audio(audioBlob, apiKey, endpoint) {
  const base64 = await blobToBase64(audioBlob);
  const mimeType = audioBlob.type || 'audio/webm';

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      audio: `data:${mimeType};base64,${base64}`,
      model: 'whisper-1',
    }),
  });

  return response.json();
}
```

### Important Notes
- **OpenAI's official API uses `multipart/form-data`**, not base64. Use `FormData` + `Blob` directly.
- If you must send base64 to a custom endpoint, the data URL prefix (`data:audio/webm;base64,`) is often required.
- Base64 increases payload size by ~33%. For large files, send binary directly.

---

## 4. Browser Compatibility Concerns

### Support Matrix

| Browser | Desktop | Mobile | Minimum Version |
|---|---|---|---|
| Chrome | ✅ | ✅ Android | 49 |
| Edge | ✅ | ✅ Android | 79 (Chromium) |
| Firefox | ✅ | ✅ Android | 29 |
| Safari | ✅ macOS | ✅ iOS | 14.1 / 14.5 |
| Opera | ✅ | ✅ Android | 36 / 80 |
| Samsung Internet | — | ✅ | 5+ |
| IE | ❌ | ❌ | — |
| Legacy Android Browser | ❌ | ❌ | — |

### MIME Type Compatibility (CRITICAL)

**Before Safari 18.4 (released ~April 2025):**
- Chrome/Firefox/Edge: `audio/webm;codecs=opus`
- Safari: `audio/mp4;codecs=mp4a.40.2` (AAC)
- **No single format worked everywhere.**

**Safari 18.4+ (Current):**
- All major browsers now support `audio/webm;codecs=opus`
- This is the first truly cross-browser compatible format

### Defensive Detection Code

```javascript
function getBestAudioMimeType() {
  const candidates = [
    'audio/webm;codecs=opus',   // Best: cross-browser since Safari 18.4
    'audio/mp4;codecs=mp4a.40.2', // Safari fallback (AAC)
    'audio/webm',               // Generic WebM
    'audio/mp4',                // Generic MP4
  ];

  for (const type of candidates) {
    if (MediaRecorder.isTypeSupported(type)) {
      return type;
    }
  }

  // Last resort: let browser choose (usually webm on Chrome, mp4 on Safari)
  return '';
}

function checkRecordingSupport() {
  const checks = {
    getUserMedia: !!(navigator.mediaDevices?.getUserMedia),
    mediaRecorder: 'MediaRecorder' in window,
    webmOpus: MediaRecorder.isTypeSupported('audio/webm;codecs=opus'),
    mp4Aac: MediaRecorder.isTypeSupported('audio/mp4;codecs=mp4a.40.2'),
  };

  const supported = checks.getUserMedia && checks.mediaRecorder;
  const hasKnownFormat = checks.webmOpus || checks.mp4Aac;

  return { supported, hasKnownFormat, checks };
}
```

### Known Issues & Workarounds

| Issue | Workaround |
|---|---|
| iOS Safari throws `NotSupportedError` even when `isTypeSupported()` is `true` | Wrap `start()` in `try/catch`; fallback to `audio/mp4` |
| Safari produces MP4/AAC, Chrome produces WebM/Opus | Server-side transcoding, or accept both formats |
| Firefox `start(timeslice)` chunks exceed requested size | Use `requestData()` manually or accept larger chunks |
| Chrome <90 resets encoder on `track.applyConstraints()` | Pause recorder before applying constraints |
| WebM files from Chrome/Firefox are technically invalid per mkvalidator | They still play everywhere; don't validate with mkvalidator |

---

## 5. Visualizing Audio Levels During Recording

### Volume Meter Using Web Audio API + AnalyserNode

```javascript
class AudioLevelMeter {
  constructor() {
    this.audioContext = null;
    this.analyser = null;
    this.source = null;
    this.rafId = null;
    this.onLevel = null; // callback(level) where level is 0-1
  }

  async start(stream) {
    this.audioContext = new AudioContext();
    this.analyser = this.audioContext.createAnalyser();
    // Smoothing: 0.8 = heavy smoothing, 0.1 = responsive
    this.analyser.smoothingTimeConstant = 0.8;
    this.analyser.fftSize = 256; // Small = fast, Large = detailed

    this.source = this.audioContext.createMediaStreamSource(stream);
    this.source.connect(this.analyser);
    // Do NOT connect to audioContext.destination — we don't want to hear the mic

    this._measure();
  }

  _measure() {
    const dataArray = new Uint8Array(this.analyser.frequencyBinCount);
    this.analyser.getByteFrequencyData(dataArray);

    // Calculate average volume (0-255)
    let sum = 0;
    for (let i = 0; i < dataArray.length; i++) {
      sum += dataArray[i];
    }
    const average = sum / dataArray.length;
    const normalized = average / 255; // 0 to 1

    this.onLevel?.(normalized);
    this.rafId = requestAnimationFrame(() => this._measure());
  }

  stop() {
    if (this.rafId) cancelAnimationFrame(this.rafId);
    this.source?.disconnect();
    this.audioContext?.close();
    this.audioContext = null;
    this.analyser = null;
    this.source = null;
  }
}

// Integration with AudioRecorder
class AudioRecorderWithMeter extends AudioRecorder {
  constructor() {
    super();
    this.meter = new AudioLevelMeter();
  }

  async start() {
    const success = await super.start();
    if (success && this.stream) {
      await this.meter.start(this.stream);
      this.meter.onLevel = (level) => {
        // Update UI: level is 0.0 (silent) to 1.0 (max)
        this.onLevelChange?.(level);
      };
    }
    return success;
  }

  stop() {
    this.meter.stop();
    super.stop();
  }
}
```

### Canvas Waveform Visualization

```javascript
function drawWaveform(canvas, analyser) {
  const ctx = canvas.getContext('2d');
  const bufferLength = analyser.frequencyBinCount;
  const dataArray = new Uint8Array(bufferLength);

  function draw() {
    requestAnimationFrame(draw);
    analyser.getByteTimeDomainData(dataArray);

    ctx.fillStyle = '#1a1a2e';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.lineWidth = 2;
    ctx.strokeStyle = '#00ff88';
    ctx.beginPath();

    const sliceWidth = canvas.width / bufferLength;
    let x = 0;

    for (let i = 0; i < bufferLength; i++) {
      const v = dataArray[i] / 128.0; // 128 is the zero-crossing point
      const y = (v * canvas.height) / 2;

      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);

      x += sliceWidth;
    }

    ctx.lineTo(canvas.width, canvas.height / 2);
    ctx.stroke();
  }

  draw();
}
```

### Alternative: Simple Bar Meter (No Canvas)

```html
<!-- HTML -->
<div class="meter">
  <div class="meter-fill" id="meterFill"></div>
</div>

<style>
  .meter { width: 200px; height: 20px; background: #333; border-radius: 10px; overflow: hidden; }
  .meter-fill { height: 100%; width: 0%; background: linear-gradient(90deg, #4ade80, #facc15, #ef4444); transition: width 50ms linear; }
</style>
```

```javascript
// In your onLevel callback:
meterFill.style.width = `${level * 100}%`;
```

---

## 6. Recommended Audio Format for LLM APIs

### OpenAI Audio API Supported Formats

Per [OpenAI docs](https://developers.openai.com/api/docs/guides/speech-to-text), supported inputs:
- `mp3`, `mp4`, `mpeg`, `mpga`, `m4a`, `wav`, `webm`
- **File size limit: 25 MB**

### Format Recommendations

| Format | Best For | Pros | Cons |
|---|---|---|---|
| **WebM/Opus** | Default choice for web apps | Cross-browser since Safari 18.4; excellent compression; natively produced by MediaRecorder | Not playable in macOS QuickTime |
| **MP3** | Balanced quality/size | Universal compatibility; good compression; OpenAI accepts it | Lossy; slightly lower accuracy than WAV |
| **WAV** | Maximum accuracy | Uncompressed; zero data loss; best transcription accuracy | Large files (~10MB/min at 16kHz/16bit mono) |
| **MP4/M4A (AAC)** | Safari-only workflows | Native Safari output; good compression | Not produced by Chrome/Firefox MediaRecorder |

### Optimal Settings for OpenAI Whisper

Based on [research by mxro](https://dev.to/mxro/optimise-openai-whisper-api-audio-format-sampling-rate-and-quality-29fj) and [AssemblyAI](https://www.assemblyai.com/blog/best-audio-file-formats-for-speech-to-text):

```javascript
const OPTIMAL_RECORDING_CONFIG = {
  // getUserMedia constraints
  audio: {
    sampleRate: 16000,      // 16 kHz is the acoustic model standard
    channelCount: 1,        // Mono
    echoCancellation: true,
    noiseSuppression: true,
    autoGainControl: true,
  },
  // MediaRecorder options
  recorder: {
    mimeType: 'audio/webm;codecs=opus', // Or audio/mp4 for Safari < 18.4
    audioBitsPerSecond: 32000,          // 32 kbps is sufficient for speech
  },
};
```

### Latency vs. Accuracy Trade-off

| Scenario | Recommendation |
|---|---|
| **Fastest upload, good accuracy** | MP3, 16-32 kbps, 12-16 kHz, mono (cuts latency ~50%) |
| **Best accuracy, don't care about size** | WAV, 16 kHz, 16-bit, mono |
| **Default web app** | WebM/Opus, 32 kbps, 16 kHz, mono |
| **Cross-browser without server transcoding** | WebM/Opus (Safari 18.4+) or accept both WebM and MP4 |

### Converting WebM to MP3 (Client-Side, if needed)

If your API only accepts MP3 and you recorded WebM, use a library like **ffmpeg.wasm**:

```javascript
import { FFmpeg } from '@ffmpeg/ffmpeg';
import { fetchFile } from '@ffmpeg/util';

const ffmpeg = new FFmpeg();
await ffmpeg.load();

async function webmToMp3(webmBlob) {
  await ffmpeg.writeFile('input.webm', await fetchFile(webmBlob));
  await ffmpeg.exec(['-i', 'input.webm', '-ar', '16000', '-ac', '1', '-b:a', '32k', 'output.mp3']);
  const data = await ffmpeg.readFile('output.mp3');
  return new Blob([data.buffer], { type: 'audio/mp3' });
}
```

> **Note:** ffmpeg.wasm is ~25MB. Only load it if you truly need client-side transcoding. Prefer server-side conversion or accepting multiple formats.

---

## Complete Working Example: Voice-to-Text Component

```javascript
// voice-recorder.js
export class VoiceRecorder {
  constructor(options = {}) {
    this.onStateChange = options.onStateChange || (() => {});
    this.onLevelChange = options.onLevelChange || (() => {});
    this.onTranscript = options.onTranscript || (() => {});
    this.onError = options.onError || console.error;

    this.apiKey = options.apiKey;
    this.apiEndpoint = options.apiEndpoint || 'https://api.openai.com';

    this.mediaRecorder = null;
    this.audioChunks = [];
    this.stream = null;
    this.audioContext = null;
    this.analyser = null;
    this.rafId = null;
  }

  getSupportedMimeType() {
    const types = [
      'audio/webm;codecs=opus',
      'audio/mp4;codecs=mp4a.40.2',
      'audio/webm',
      'audio/mp4',
    ];
    return types.find(t => MediaRecorder.isTypeSupported(t)) || '';
  }

  async start() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate: 16000,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
      });

      // Start level visualization
      this._startVisualization();

      const mimeType = this.getSupportedMimeType();
      if (!mimeType) throw new Error('No supported audio format found');

      this.mediaRecorder = new MediaRecorder(this.stream, {
        mimeType,
        audioBitsPerSecond: 32000,
      });

      this.audioChunks = [];

      this.mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) this.audioChunks.push(e.data);
      };

      this.mediaRecorder.onstart = () => this.onStateChange('recording');
      this.mediaRecorder.onpause = () => this.onStateChange('paused');
      this.mediaRecorder.onresume = () => this.onStateChange('recording');

      this.mediaRecorder.onstop = async () => {
        this.onStateChange('processing');
        this._stopVisualization();
        this._stopTracks();

        const blob = new Blob(this.audioChunks, { type: mimeType });
        try {
          const transcript = await this._sendToApi(blob);
          this.onTranscript(transcript);
        } catch (err) {
          this.onError(err);
        }
        this.onStateChange('inactive');
      };

      this.mediaRecorder.start();
      return true;
    } catch (err) {
      this.onError(err);
      this._cleanup();
      return false;
    }
  }

  stop() {
    if (this.mediaRecorder?.state === 'recording') {
      this.mediaRecorder.stop();
    }
  }

  pause() {
    if (this.mediaRecorder?.state === 'recording') {
      this.mediaRecorder.pause();
    }
  }

  resume() {
    if (this.mediaRecorder?.state === 'paused') {
      this.mediaRecorder.resume();
    }
  }

  _startVisualization() {
    this.audioContext = new AudioContext();
    this.analyser = this.audioContext.createAnalyser();
    this.analyser.smoothingTimeConstant = 0.8;
    this.analyser.fftSize = 256;

    const source = this.audioContext.createMediaStreamSource(this.stream);
    source.connect(this.analyser);

    const dataArray = new Uint8Array(this.analyser.frequencyBinCount);
    const measure = () => {
      this.analyser.getByteFrequencyData(dataArray);
      const avg = dataArray.reduce((a, b) => a + b, 0) / dataArray.length;
      this.onLevelChange(avg / 255);
      this.rafId = requestAnimationFrame(measure);
    };
    measure();
  }

  _stopVisualization() {
    if (this.rafId) cancelAnimationFrame(this.rafId);
    this.audioContext?.close();
    this.audioContext = null;
    this.analyser = null;
  }

  _stopTracks() {
    this.stream?.getTracks().forEach(t => t.stop());
    this.stream = null;
  }

  _cleanup() {
    this._stopVisualization();
    this._stopTracks();
    this.mediaRecorder = null;
  }

  async _sendToApi(blob) {
    const ext = blob.type.includes('mp4') ? 'm4a'
      : blob.type.includes('webm') ? 'webm'
      : 'audio';

    const formData = new FormData();
    formData.append('file', blob, `recording.${ext}`);
    formData.append('model', 'whisper-1');

    const response = await fetch(`${this.apiEndpoint}/v1/audio/transcriptions`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${this.apiKey}` },
      body: formData,
    });

    if (!response.ok) {
      throw new Error(`API error ${response.status}: ${await response.text()}`);
    }

    const result = await response.json();
    return result.text;
  }
}
```

### React Hook Usage

```javascript
import { useState, useCallback, useRef } from 'react';
import { VoiceRecorder } from './voice-recorder';

export function useVoiceRecorder(apiKey) {
  const [state, setState] = useState('inactive');
  const [level, setLevel] = useState(0);
  const [transcript, setTranscript] = useState('');
  const [error, setError] = useState(null);
  const recorderRef = useRef(null);

  const start = useCallback(() => {
    setError(null);
    recorderRef.current = new VoiceRecorder({
      apiKey,
      onStateChange: setState,
      onLevelChange: setLevel,
      onTranscript: setTranscript,
      onError: setError,
    });
    recorderRef.current.start();
  }, [apiKey]);

  const stop = useCallback(() => recorderRef.current?.stop(), []);
  const pause = useCallback(() => recorderRef.current?.pause(), []);
  const resume = useCallback(() => recorderRef.current?.resume(), []);

  return { state, level, transcript, error, start, stop, pause, resume };
}
```

---

## Summary Checklist

- [ ] Use `getUserMedia({ audio: { sampleRate: 16000, channelCount: 1 } })` for optimal speech capture
- [ ] Detect supported MIME types with `MediaRecorder.isTypeSupported()`
- [ ] Prefer `audio/webm;codecs=opus` (cross-browser since Safari 18.4)
- [ ] Always stop stream tracks after recording to release the microphone
- [ ] Send audio to OpenAI as `FormData` with a `Blob`, not base64
- [ ] Use `audioBitsPerSecond: 32000` for a good balance of quality and file size
- [ ] Visualize levels with `AnalyserNode` + `getByteFrequencyData`
- [ ] Wrap `MediaRecorder.start()` in `try/catch` for iOS Safari safety
- [ ] Keep recordings under 25MB for OpenAI's API limit
