/**
 * VoiceRecorder - Browser-based voice recording using getUserMedia + MediaRecorder
 * Outputs WAV format at 16kHz mono for optimal LLM API compatibility
 */
class VoiceRecorder {
  constructor() {
    this.stream = null;
    this.mediaRecorder = null;
    this.chunks = [];
    this.isRecording = false;
    this.startTime = 0;
    this.audioContext = null;
    this.analyser = null;
    this.dataArray = null;
    this.animationId = null;
    this.onDataAvailable = null;
    this.onVisualizerData = null;
  }

  /**
   * Request microphone permission and set up recording
   */
  async start() {
    if (this.isRecording) return;

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate: 16000,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      });
    } catch (err) {
      if (err.name === 'NotAllowedError' || err.name === 'PermissionDeniedError') {
        throw new Error('Microphone permission denied. Please allow microphone access in your browser settings.');
      }
      if (err.name === 'NotFoundError') {
        throw new Error('No microphone found. Please connect a microphone and try again.');
      }
      throw new Error(`Microphone error: ${err.message}`);
    }

    // Set up Web Audio API for visualization
    this.audioContext = new AudioContext({ sampleRate: 16000 });
    const source = this.audioContext.createMediaStreamSource(this.stream);
    this.analyser = this.audioContext.createAnalyser();
    this.analyser.fftSize = 256;
    this.analyser.smoothingTimeConstant = 0.8;
    source.connect(this.analyser);
    this.dataArray = new Uint8Array(this.analyser.frequencyBinCount);

    // Determine best MIME type
    const mimeType = this._getSupportedMimeType();
    
    try {
      this.mediaRecorder = new MediaRecorder(this.stream, {
        mimeType,
        audioBitsPerSecond: 128000
      });
    } catch (err) {
      // Fallback to default
      this.mediaRecorder = new MediaRecorder(this.stream);
    }

    this.chunks = [];
    this.mediaRecorder.ondataavailable = (event) => {
      if (event.data.size > 0) {
        this.chunks.push(event.data);
      }
      if (this.onDataAvailable) {
        this.onDataAvailable(event.data);
      }
    };

    this.mediaRecorder.start(100); // Emit chunks every 100ms for visualization
    this.isRecording = true;
    this.startTime = Date.now();

    // Start visualization loop
    this._visualize();

    return true;
  }

  /**
   * Stop recording and return the audio blob
   */
  async stop() {
    if (!this.isRecording || !this.mediaRecorder) {
      return null;
    }

    return new Promise((resolve) => {
      this.mediaRecorder.onstop = () => {
        const blob = new Blob(this.chunks, { type: this.mediaRecorder.mimeType || 'audio/webm' });
        this._cleanup();
        resolve(blob);
      };

      this.mediaRecorder.stop();
      this.isRecording = false;
    });
  }

  /**
   * Get current recording duration in seconds
   */
  getDuration() {
    if (!this.isRecording) return 0;
    return Math.floor((Date.now() - this.startTime) / 1000);
  }

  /**
   * Format seconds as MM:SS
   */
  static formatTime(seconds) {
    const mins = Math.floor(seconds / 60).toString().padStart(2, '0');
    const secs = (seconds % 60).toString().padStart(2, '0');
    return `${mins}:${secs}`;
  }

  /**
   * Convert Blob to base64 string (with data URL prefix stripped)
   */
  static blobToBase64(blob) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => {
        const base64 = reader.result.split(',')[1];
        resolve(base64);
      };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }

  static async convertToWav(blob) {
    if (blob.type.includes('wav')) return blob;

    const arrayBuffer = await blob.arrayBuffer();
    const audioCtx = new AudioContext({ sampleRate: 16000 });
    const audioBuffer = await audioCtx.decodeAudioData(arrayBuffer);
    const wavBuffer = VoiceRecorder._encodeWav(audioBuffer, 16000);
    await audioCtx.close();
    return new Blob([wavBuffer], { type: 'audio/wav' });
  }

  static _encodeWav(audioBuffer, targetSampleRate) {
    const numChannels = 1;
    const sampleRate = targetSampleRate;
    const format = 1;
    const bitsPerSample = 16;

    // Resample to mono + target sample rate
    const originalData = audioBuffer.getChannelData(0);
    const ratio = audioBuffer.sampleRate / sampleRate;
    const length = Math.floor(originalData.length / ratio);
    const samples = new Float32Array(length);

    for (let i = 0; i < length; i++) {
      samples[i] = originalData[Math.floor(i * ratio)];
    }

    const bytesPerSample = bitsPerSample / 8;
    const blockAlign = numChannels * bytesPerSample;
    const byteRate = sampleRate * blockAlign;
    const dataSize = samples.length * bytesPerSample;
    const buffer = new ArrayBuffer(44 + dataSize);
    const view = new DataView(buffer);

    function writeString(offset, string) {
      for (let i = 0; i < string.length; i++) {
        view.setUint8(offset + i, string.charCodeAt(i));
      }
    }

    writeString(0, 'RIFF');
    view.setUint32(4, 36 + dataSize, true);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, format, true);
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, byteRate, true);
    view.setUint16(32, blockAlign, true);
    view.setUint16(34, bitsPerSample, true);
    writeString(36, 'data');
    view.setUint32(40, dataSize, true);

    let offset = 44;
    for (let i = 0; i < samples.length; i++) {
      const s = Math.max(-1, Math.min(1, samples[i]));
      view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7FFF, true);
      offset += 2;
    }

    return buffer;
  }

  static getAudioFormat(blob) {
    const type = blob.type.toLowerCase();
    if (type.includes('wav')) return 'wav';
    if (type.includes('mp3') || type.includes('mpeg')) return 'mp3';
    return 'wav';
  }

  /* Private methods */

  _getSupportedMimeType() {
    const types = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/mp4',
      'audio/mp3',
      'audio/wav'
    ];
    for (const type of types) {
      if (MediaRecorder.isTypeSupported(type)) {
        return type;
      }
    }
    return '';
  }

  _visualize() {
    if (!this.analyser || !this.isRecording) return;

    this.analyser.getByteFrequencyData(this.dataArray);

    if (this.onVisualizerData) {
      this.onVisualizerData(new Uint8Array(this.dataArray));
    }

    this.animationId = requestAnimationFrame(() => this._visualize());
  }

  _cleanup() {
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }

    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
      this.stream = null;
    }

    if (this.audioContext) {
      this.audioContext.close();
      this.audioContext = null;
    }

    this.analyser = null;
    this.dataArray = null;
    this.mediaRecorder = null;
    this.chunks = [];
    this.isRecording = false;
  }
}
