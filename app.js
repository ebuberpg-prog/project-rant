/**
 * Rant — Voice to Structured Spec App
 * Main application logic: recording, API integration, multi-turn conversation, export
 */

(function() {
  'use strict';

  // DOM Elements
  const els = {
    views: {
      recording: document.getElementById('recordingView'),
      processing: document.getElementById('processingView'),
      conversation: document.getElementById('conversationView'),
      spec: document.getElementById('specView')
    },
    recordBtn: document.getElementById('recordBtn'),
    mobileBackBtn: document.getElementById('mobileBackBtn'),
    statusText: document.getElementById('statusText'),
    timer: document.getElementById('timer'),
    waveform: document.getElementById('waveform'),
    apiKey: document.getElementById('apiKey'),
    modelSelect: document.getElementById('modelSelect'),
    processingTitle: document.getElementById('processingTitle'),
    processingSubtitle: document.getElementById('processingSubtitle'),
    chatMessages: document.getElementById('chatMessages'),
    chatInput: document.getElementById('chatInput'),
    sendBtn: document.getElementById('sendBtn'),
    chatRecordBtn: document.getElementById('chatRecordBtn'),
    chatRecordingIndicator: document.getElementById('chatRecordingIndicator'),
    chatTimer: document.getElementById('chatTimer'),
    specPreview: document.getElementById('specPreview'),
    copyBtn: document.getElementById('copyBtn'),
    downloadBtn: document.getElementById('downloadBtn'),
    newRantBtn: document.getElementById('newRantBtn'),
    toast: document.getElementById('toast'),
    toastMessage: document.getElementById('toastMessage')
  };

  // State
  const state = {
    recorder: null,
    api: null,
    conversation: [],
    currentSpec: '',
    isGenerating: false,
    timerInterval: null,
    chatRecorder: null,
    chatTimerInterval: null,
    audioBlob: null,
    needsClarification: false,
    transcribedText: '',
    mode: 'prd'
  };

  const MODE_HINTS = {
    prd: '<p><strong>PRD mode:</strong> Describe a feature or product idea. The AI will ask about users, scope, and tech stack, then build a full PRD.</p>',
    fix: '<p><strong>Fix mode:</strong> Describe a bug or issue. The AI will ask about repro steps and expected behavior, then build a structured fix prompt.</p>',
    rant: '<p><strong>Rant mode:</strong> Just talk. The AI structures exactly what you said — no questions asked.</p>'
  };

  const AUDIO_NATIVE_MODELS = ['openai/gpt-audio', 'openai/gpt-audio-mini'];

  function modelSupportsAudioInput(modelId) {
    return AUDIO_NATIVE_MODELS.includes(modelId);
  }

  // Waveform canvas context
  const waveformCtx = els.waveform.getContext('2d');

  // Initialize
  function init() {
    detectFileProtocol();
    bindEvents();
    loadApiKey();
    renderHistory();
    resizeWaveform();
    window.addEventListener('resize', resizeWaveform);
  }

  function detectFileProtocol() {
    if (window.location.protocol === 'file:') {
      showToast('You opened this file directly. Use a local server to avoid CORS errors. See README.', 'warning');
    }
  }

  function resizeWaveform() {
    const rect = els.waveform.parentElement.getBoundingClientRect();
    els.waveform.width = rect.width * window.devicePixelRatio;
    els.waveform.height = rect.height * window.devicePixelRatio;
    waveformCtx.scale(window.devicePixelRatio, window.devicePixelRatio);
  }

  function bindEvents() {
    els.recordBtn.addEventListener('click', toggleRecording);
    if (els.mobileBackBtn) {
      els.mobileBackBtn.addEventListener('click', () => showView('recording'));
    }
    els.sendBtn.addEventListener('click', sendTextMessage);
    els.chatInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendTextMessage();
      }
    });
    els.chatRecordBtn.addEventListener('click', toggleChatRecording);
    els.copyBtn.addEventListener('click', copySpec);
    els.downloadBtn.addEventListener('click', downloadSpec);
    els.newRantBtn.addEventListener('click', resetApp);
    els.apiKey.addEventListener('change', saveApiKey);
    els.modelSelect.addEventListener('change', updateModel);

    const clearHistoryBtn = document.getElementById('clearHistoryBtn');
    if (clearHistoryBtn) {
      clearHistoryBtn.addEventListener('click', clearAllHistory);
    }

    document.querySelectorAll('.mode-btn').forEach(btn => {
      btn.addEventListener('click', () => setMode(btn.dataset.mode));
    });
  }

  function setMode(mode) {
    state.mode = mode;
    document.querySelectorAll('.mode-btn').forEach(btn => {
      btn.classList.toggle('mode-btn--active', btn.dataset.mode === mode);
    });
    const hintEl = document.getElementById('modeHint');
    if (hintEl) hintEl.innerHTML = MODE_HINTS[mode];
  }

  // API Key management
  function loadApiKey() {
    const key = localStorage.getItem('rant_api_key');
    if (key) els.apiKey.value = key;
  }

  function saveApiKey() {
    localStorage.setItem('rant_api_key', els.apiKey.value);
  }

  function updateModel() {
    if (state.api) {
      state.api.setModel(els.modelSelect.value);
    }
  }

  function getApiKey() {
    const key = els.apiKey.value.trim();
    if (!key) {
      showToast('Please enter your Wavespeed.ai API key', 'error');
      return null;
    }
    return key;
  }

  // View switching
  function showView(viewName) {
    Object.values(els.views).forEach(v => {
      v.classList.remove('view--active');
      v.style.display = 'none';
    });
    els.views[viewName].classList.add('view--active');
    els.views[viewName].style.display = 'flex';

    if (els.mobileBackBtn) {
      els.mobileBackBtn.classList.toggle('hidden', viewName === 'recording');
    }
  }

  // Recording
  async function toggleRecording() {
    if (state.recorder && state.recorder.isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  async function startRecording() {
    const key = getApiKey();
    if (!key) return;

    state.recorder = new VoiceRecorder();
    state.recorder.onVisualizerData = drawWaveform;

    try {
      await state.recorder.start();
      els.recordBtn.classList.add('recording');
      els.statusText.textContent = 'Recording... tap to stop';
      els.timer.classList.add('recording');
      startTimer();
      drawIdleWaveform(); // Start animation loop
    } catch (err) {
      showToast(err.message, 'error');
      state.recorder = null;
    }
  }

  async function stopRecording() {
    if (!state.recorder || !state.recorder.isRecording) return;

    const duration = state.recorder.getDuration();
    if (duration < 3) {
      showToast('Recording too short. Rant for at least 3 seconds.', 'warning');
      cleanupRecording();
      return;
    }

    els.recordBtn.classList.remove('recording');
    els.statusText.textContent = 'Processing...';
    stopTimer();

    const blob = await state.recorder.stop();
    cleanupRecording();

    if (!blob || blob.size === 0) {
      showToast('No audio captured. Please try again.', 'error');
      return;
    }

    state.audioBlob = blob;
    await processAudio(blob);
  }

  function cleanupRecording() {
    if (state.recorder) {
      state.recorder.stop().catch(() => {});
      state.recorder = null;
    }
    els.recordBtn.classList.remove('recording');
    els.timer.classList.remove('recording');
    els.statusText.textContent = 'Tap the mic to start ranting';
    stopTimer();
    clearWaveform();
  }

  function startTimer() {
    els.timer.textContent = '00:00';
    state.timerInterval = setInterval(() => {
      if (state.recorder) {
        els.timer.textContent = VoiceRecorder.formatTime(state.recorder.getDuration());
      }
    }, 1000);
  }

  function stopTimer() {
    if (state.timerInterval) {
      clearInterval(state.timerInterval);
      state.timerInterval = null;
    }
  }

  // Waveform visualization
  function drawWaveform(data) {
    const canvas = els.waveform;
    const ctx = waveformCtx;
    const width = canvas.width / window.devicePixelRatio;
    const height = canvas.height / window.devicePixelRatio;

    ctx.clearRect(0, 0, width, height);

    const barWidth = width / data.length;
    const barGap = 1;

    for (let i = 0; i < data.length; i++) {
      const value = data[i];
      const barHeight = (value / 255) * height * 0.8;
      const x = i * barWidth;
      const y = (height - barHeight) / 2;

      const intensity = value / 255;
      const r = Math.floor(41 + intensity * 37);
      const g = Math.floor(37 + intensity * 33);
      const b = Math.floor(36 + intensity * 33);

      ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
      ctx.fillRect(x, y, barWidth - barGap, barHeight);
    }
  }

  function drawIdleWaveform() {
    if (state.recorder && state.recorder.isRecording) {
      requestAnimationFrame(drawIdleWaveform);
    }
  }

  function clearWaveform() {
    const canvas = els.waveform;
    const ctx = waveformCtx;
    const width = canvas.width / window.devicePixelRatio;
    const height = canvas.height / window.devicePixelRatio;
    ctx.clearRect(0, 0, width, height);

    ctx.strokeStyle = '#e7e5e4';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, height / 2);
    ctx.lineTo(width, height / 2);
    ctx.stroke();
  }

  async function processAudio(blob) {
    const key = getApiKey();
    if (!key) return;

    showView('processing');
    els.processingTitle.textContent = 'Converting audio to WAV...';
    els.processingSubtitle.textContent = 'This may take a moment';

    const selectedModel = els.modelSelect.value;
    const mode = state.mode;

    try {
      const wavBlob = await VoiceRecorder.convertToWav(blob);
      const base64Audio = await VoiceRecorder.blobToBase64(wavBlob);
      const format = VoiceRecorder.getAudioFormat(wavBlob);

      let userContent;
      let directAudioSuccess = false;

      state.api = new WavespeedAI(key, selectedModel);

      const modePrompt = Prompts[mode].initial;

      try {
        const directResponse = await state.api.sendAudio(
          modePrompt,
          base64Audio,
          format,
          { temperature: 0.7, max_tokens: 4000 }
        );
        const content = directResponse.choices[0]?.message?.content || '';
        if (content) {
          directAudioSuccess = true;
          userContent = content;
        }
      } catch (directErr) {
        console.log('Direct audio failed, falling back to transcription:', directErr.message);
      }

      if (!directAudioSuccess) {
        els.processingTitle.textContent = 'Transcribing your rant...';
        els.processingSubtitle.textContent = 'Model does not support direct audio, using transcription';

        const transcribeApi = new WavespeedAI(key, 'openai/gpt-audio-mini');
        const transcribePrompt = 'Transcribe this audio exactly as spoken. Output ONLY the transcription, no other text.';
        const txResponse = await transcribeApi.sendAudio(
          transcribePrompt,
          base64Audio,
          format,
          { temperature: 0.3, max_tokens: 2000 }
        );

        const transcription = txResponse.choices[0]?.message?.content || '';
        if (!transcription.trim()) {
          throw new Error('Could not transcribe audio. Please try again or type your rant.');
        }

        state.transcribedText = transcription.trim();
        const textPrompt = modePrompt + '\n\nUSER TRANSCRIPT:\n' + transcription.trim();

        els.processingTitle.textContent = 'Generating your output...';
        els.processingSubtitle.textContent = 'This may take 10-30 seconds';

        const textResponse = await state.api.chatCompletion(
          modePrompt,
          [{ role: 'user', content: textPrompt }],
          { temperature: 0.7, max_tokens: 4000 }
        );

        userContent = textResponse.choices[0]?.message?.content || '';
      }

      handleModeResponse(userContent, selectedModel);
    } catch (err) {
      showToast(err.message, 'error');
      showView('recording');
    }
  }

  function handleModeResponse(content, selectedModel) {
    const mode = state.mode;

    if (mode === 'rant') {
      state.currentSpec = content;
      addToHistory(content, selectedModel);
      displaySpec(content);
      showView('spec');
      showToast('Structured output ready!', 'success');
      return;
    }

    if (looksLikeDeliverable(content, mode)) {
      state.currentSpec = content;
      state.needsClarification = false;
      addToHistory(content, selectedModel);
      displaySpec(content);
      showView('spec');
      showToast('Output generated successfully!', 'success');
    } else {
      state.needsClarification = true;
      state.conversation.push({ role: 'assistant', content: content });
      showView('conversation');
      renderChat();
      addSystemMessage('The AI needs a bit more info. Answer the questions below.');
    }
  }

  function looksLikeDeliverable(text, mode) {
    if (mode === 'prd') {
      return text.includes('# PRD:') || text.includes('## 1. Overview');
    }
    if (mode === 'fix') {
      return text.includes('# Fix:') || text.includes('## Problem Definition');
    }
    return text.includes('# ');
  }

  async function sendTextMessage() {
    const text = els.chatInput.value.trim();
    if (!text) return;

    state.conversation.push({ role: 'user', content: text });
    renderChat();
    els.chatInput.value = '';
    els.chatInput.style.height = 'auto';

    addSystemMessage('AI is thinking...');
    els.sendBtn.disabled = true;

    try {
      const key = getApiKey();
      if (!key) return;

      if (!state.api) {
        state.api = new WavespeedAI(key, els.modelSelect.value);
      }

      const mode = state.mode;
      const systemPrompt = state.needsClarification
        ? Prompts[mode].final
        : Prompts[mode].clarification;

      const response = await state.api.sendConversation(
        systemPrompt,
        state.conversation,
        { temperature: 0.7, max_tokens: 4000 }
      );

      const content = response.choices[0]?.message?.content || '';
      removeLastSystemMessage();

      if (state.needsClarification) {
        if (looksLikeDeliverable(content, mode)) {
          state.currentSpec = content;
          state.needsClarification = false;
          addToHistory(content, els.modelSelect.value);
          displaySpec(content);
          showView('spec');
          showToast('Output finalized!', 'success');
        } else {
          state.conversation.push({ role: 'assistant', content: content });
          renderChat();
        }
      } else {
        state.conversation.push({ role: 'assistant', content: content });

        if (looksLikeDeliverable(content, mode)) {
          state.currentSpec = content;
          state.needsClarification = false;
          addToHistory(content, els.modelSelect.value);
          displaySpec(content);
          showView('spec');
          showToast('Output generated!', 'success');
        } else {
          state.conversation.push({ role: 'assistant', content: content });
          renderChat();
        }
      }
    } catch (err) {
      removeLastSystemMessage();
      showToast(err.message, 'error');
    } finally {
      els.sendBtn.disabled = false;
    }
  }

  // Chat recording (for voice responses to clarification questions)
  async function toggleChatRecording() {
    if (state.chatRecorder && state.chatRecorder.isRecording) {
      await stopChatRecording();
    } else {
      await startChatRecording();
    }
  }

  async function startChatRecording() {
    const key = getApiKey();
    if (!key) return;

    state.chatRecorder = new VoiceRecorder();

    try {
      await state.chatRecorder.start();
      els.chatRecordBtn.classList.add('recording');
      els.chatRecordingIndicator.classList.remove('hidden');

      state.chatTimerInterval = setInterval(() => {
        if (state.chatRecorder) {
          els.chatTimer.textContent = VoiceRecorder.formatTime(state.chatRecorder.getDuration());
        }
      }, 1000);
    } catch (err) {
      showToast(err.message, 'error');
      state.chatRecorder = null;
    }
  }

  async function stopChatRecording() {
    if (!state.chatRecorder || !state.chatRecorder.isRecording) return;

    els.chatRecordBtn.classList.remove('recording');
    els.chatRecordingIndicator.classList.add('hidden');
    clearInterval(state.chatTimerInterval);
    els.chatTimer.textContent = '00:00';

    const blob = await state.chatRecorder.stop();
    state.chatRecorder = null;

    if (!blob || blob.size === 0) {
      showToast('No audio captured', 'warning');
      return;
    }

    try {
      addSystemMessage('Converting audio to WAV...');
      const wavBlob = await VoiceRecorder.convertToWav(blob);
      const base64Audio = await VoiceRecorder.blobToBase64(wavBlob);
      const format = VoiceRecorder.getAudioFormat(wavBlob);

      const key = getApiKey();
      if (!key) return;

      if (!state.api) {
        state.api = new WavespeedAI(key, els.modelSelect.value);
      }

      addSystemMessage('Transcribing your voice response...');
      els.sendBtn.disabled = true;

      const transcribePrompt = 'Transcribe this audio exactly as spoken. Output ONLY the transcription, no other text.';
      const transcribeResponse = await state.api.sendAudio(
        transcribePrompt,
        base64Audio,
        format,
        { temperature: 0.3, max_tokens: 1000 }
      );

      const transcription = transcribeResponse.choices[0]?.message?.content || '';
      removeLastSystemMessage();

      if (transcription.trim()) {
        // Add transcription as user text message
        state.conversation.push({ role: 'user', content: transcription.trim() });
        renderChat();

        // Now process this as a regular text message
        await sendTextMessage();
      } else {
        showToast('Could not transcribe audio. Please type your response.', 'warning');
      }
    } catch (err) {
      removeLastSystemMessage();
      showToast(err.message, 'error');
      els.sendBtn.disabled = false;
    }
  }

  // Chat UI
  function renderChat() {
    els.chatMessages.innerHTML = '';

    for (const msg of state.conversation) {
      const div = document.createElement('div');
      div.className = `message message--${msg.role}`;

      // Convert markdown-ish formatting to HTML
      let html = escapeHtml(msg.content)
        .replace(/\n/g, '<br>')
        .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
        .replace(/\*(.+?)\*/g, '<em>$1</em>')
        .replace(/`([^`]+)`/g, '<code>$1</code>');

      div.innerHTML = html;
      els.chatMessages.appendChild(div);
    }

    // Scroll to bottom
    els.chatMessages.scrollTop = els.chatMessages.scrollHeight;
  }

  function addSystemMessage(text) {
    const div = document.createElement('div');
    div.className = 'message message--system';
    div.textContent = text;
    div.dataset.system = 'true';
    els.chatMessages.appendChild(div);
    els.chatMessages.scrollTop = els.chatMessages.scrollHeight;
  }

  function removeLastSystemMessage() {
    const messages = els.chatMessages.querySelectorAll('[data-system="true"]');
    if (messages.length > 0) {
      messages[messages.length - 1].remove();
    }
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // Spec display
  function displaySpec(spec) {
    // Simple markdown-like rendering
    let html = escapeHtml(spec)
      // Code blocks first (they may contain other markdown chars)
      .replace(/```(?:\w+)?\n([\s\S]*?)\n```/g, '<pre><code>$1</code></pre>')
      // Headings
      .replace(/^# (.+)$/gm, '<h1>$1</h1>')
      .replace(/^## (.+)$/gm, '<h2>$1</h2>')
      .replace(/^### (.+)$/gm, '<h3>$1</h3>')
      .replace(/^#### (.+)$/gm, '<h4>$1</h4>')
      // Inline formatting
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      // Lists
      .replace(/^- (.+)$/gm, '<li>$1</li>')
      .replace(/(<li>.+<\/li>\s*)+/g, '<ul>$&</ul>')
      // Tables
      .replace(/^\|(.+)\|$/gm, (match) => {
        const cells = match.split('|').filter(c => c.trim() !== '');
        return `<tr>${cells.map(c => `<td>${c.trim()}</td>`).join('')}</tr>`;
      })
      .replace(/(<tr>.+<\/tr>\s*){2,}/g, '<table>$&</table>');

    // Convert remaining newlines to <br>, then clean up around block elements
    html = html.replace(/\n/g, '<br>');

    // Remove <br> between list items and around block elements
    html = html
      .replace(/<\/li>\s*<br>\s*<li>/g, '</li><li>')
      .replace(/<ul>\s*<br>/g, '<ul>')
      .replace(/<br>\s*<\/ul>/g, '</ul>')
      .replace(/<br>\s*<(h[123456]|pre|table|ul)/g, '<$1')
      .replace(/<\/(h[123456]|pre|table|ul)>\s*<br>/g, '</$1>');

    els.specPreview.innerHTML = html;
  }

  // Export actions
  async function copySpec() {
    const success = await ExportModule.copyToClipboard(state.currentSpec);
    showToast(success ? 'Copied to clipboard!' : 'Failed to copy', success ? 'success' : 'error');
  }

  function downloadSpec() {
    const titleMatch = state.currentSpec.match(/^# PRD:\s*(.+)/m);
    const filename = titleMatch
      ? `${titleMatch[1].trim().toLowerCase().replace(/\s+/g, '-')}.md`
      : 'spec.md';
    ExportModule.downloadAsMarkdown(state.currentSpec, filename);
    showToast('Downloaded!', 'success');
  }

  // History management
  function loadHistory() {
    try {
      const raw = localStorage.getItem('rant_history');
      return raw ? JSON.parse(raw) : [];
    } catch {
      return [];
    }
  }

  function saveHistory(history) {
    localStorage.setItem('rant_history', JSON.stringify(history.slice(0, 50)));
  }

  function addToHistory(spec, model) {
    if (!spec || !spec.trim()) return;
    const history = loadHistory();
    const titleMatch = spec.match(/^# PRD:\s*(.+)/m);
    const title = titleMatch ? titleMatch[1].trim() : 'Untitled Rant';
    const item = {
      id: Date.now().toString(),
      title: title.substring(0, 60),
      spec: spec,
      model: model || 'unknown',
      createdAt: new Date().toISOString()
    };
    history.unshift(item);
    saveHistory(history);
    renderHistory();
  }

  function renderHistory() {
    const history = loadHistory();
    const list = document.getElementById('historyList');
    if (!list) return;

    if (history.length === 0) {
      list.innerHTML = '<p class="history-empty">No rants yet. Record your first!</p>';
      return;
    }

    list.innerHTML = '';
    for (const item of history) {
      const div = document.createElement('div');
      div.className = 'history-item';
      div.dataset.id = item.id;

      const date = new Date(item.createdAt);
      const dateStr = date.toLocaleDateString() + ' ' + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

      div.innerHTML = `
        <div class="history-item-title">${escapeHtml(item.title)}</div>
        <div class="history-item-date">${dateStr}</div>
        <div class="history-item-model">${escapeHtml(item.model)}</div>
        <button class="history-delete-btn" data-delete-id="${item.id}" title="Delete">×</button>
      `;

      div.addEventListener('click', (e) => {
        if (e.target.closest('.history-delete-btn')) return;
        loadHistoryItem(item.id);
      });

      list.appendChild(div);
    }

    // Bind delete buttons
    list.querySelectorAll('.history-delete-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        deleteHistoryItem(btn.dataset.deleteId);
      });
    });
  }

  function loadHistoryItem(id) {
    const history = loadHistory();
    const item = history.find(h => h.id === id);
    if (!item) return;

    state.currentSpec = item.spec;
    displaySpec(item.spec);
    showView('spec');
  }

  function deleteHistoryItem(id) {
    let history = loadHistory();
    history = history.filter(h => h.id !== id);
    saveHistory(history);
    renderHistory();
  }

  function clearAllHistory() {
    if (!confirm('Clear all rant history? This cannot be undone.')) return;
    localStorage.removeItem('rant_history');
    renderHistory();
    showToast('History cleared', 'success');
  }

  // App reset
  function resetApp() {
    state.conversation = [];
    state.currentSpec = '';
    state.audioBlob = null;
    state.needsClarification = false;
    state.isGenerating = false;
    els.chatMessages.innerHTML = '';
    els.chatInput.value = '';
    els.specPreview.innerHTML = '';
    cleanupRecording();
    showView('recording');
  }

  // Toast notifications
  function showToast(message, type = 'info') {
    els.toastMessage.textContent = message;
    els.toast.className = `toast toast--${type}`;

    setTimeout(() => {
      els.toast.classList.add('hidden');
    }, 4000);
  }

  // Start the app
  init();
})();
