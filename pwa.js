(() => {
  const API = 'http://127.0.0.1:41739/v1';
  const els = Object.fromEntries(['connection','connectionText','companionHelp','mode','recordButton','recordLabel','signInButton','status','resultSection','resultText','copyButton','speakButton','installButton'].map(id => [id, document.getElementById(id)]));
  let connected = false;
  let recording = false;
  let pollTimer = null;
  let installPrompt = null;
  const safariBlocksCompanion = /Safari\//.test(navigator.userAgent) && !/Chrome|Chromium|Edg|Firefox/.test(navigator.userAgent);

  async function request(path, body) {
    const response = await fetch(`${API}${path}`, {
      method: body ? 'POST' : 'GET',
      headers: body ? { 'Content-Type': 'application/json' } : undefined,
      body: body ? JSON.stringify(body) : undefined,
      cache: 'no-store',
      credentials: 'omit'
    });
    const result = response.status === 204 ? {} : await response.json();
    if (!response.ok) throw new Error(result.error || `Rant companion returned ${response.status}.`);
    return result;
  }

  function setStatus(message) { els.status.textContent = message; }

  function setConnection(isConnected, planEnabled = false) {
    connected = isConnected;
    els.connection.classList.toggle('connection--ready', isConnected);
    els.connection.classList.toggle('connection--offline', !isConnected);
    els.connectionText.textContent = isConnected ? 'Rant for Mac is ready on this computer' : safariBlocksCompanion ? 'This browser cannot connect to the Mac companion' : 'Rant for Mac is not running';
    els.companionHelp.classList.toggle('hidden', isConnected);
    document.getElementById('safariMessage').classList.toggle('hidden', !safariBlocksCompanion);
    document.getElementById('companionMessage').classList.toggle('hidden', safariBlocksCompanion);
    els.recordButton.disabled = !isConnected;
    els.signInButton.disabled = !isConnected || planEnabled;
    els.signInButton.textContent = planEnabled ? 'ChatGPT connected' : 'Connect ChatGPT';
  }

  function showResult(text) {
    if (!text) return;
    els.resultText.textContent = text;
    els.resultSection.classList.remove('hidden');
  }

  async function refreshStatus() {
    try {
      const state = await request('/status');
      setConnection(true, state.connected);
      els.recordButton.disabled = Boolean(state.processing || state.starting && !recording);
      if (state.error) setStatus(state.error);
      else if (state.signingIn) setStatus('Complete ChatGPT sign-in in the browser window that Rant opened…');
      else if (state.processing) setStatus('Finishing up your words…');
      else if (state.recording || state.starting) setStatus('Listening. Select Stop recording when you’re done.');
      else if (state.output) {
        setStatus('Your result is ready.');
        showResult(state.output);
      } else if (state.status) setStatus(state.status);
      if (recording && !state.recording && !state.starting) {
        recording = false;
        els.recordButton.classList.remove('is-recording');
        els.recordLabel.textContent = 'Start recording';
      }
      if (state.processing || state.starting || state.signingIn || recording) pollTimer = setTimeout(refreshStatus, 700);
    } catch {
      setConnection(false);
      if (!recording) setStatus(safariBlocksCompanion ? 'Open this page in Chrome or another Chromium browser to connect with the Mac app.' : 'Open Rant for Mac on this computer, then try again.');
      pollTimer = setTimeout(refreshStatus, 2500);
    }
  }

  els.recordButton.addEventListener('click', async () => {
    if (!connected) return;
    try {
      if (!recording) {
        els.resultSection.classList.add('hidden');
        recording = true;
        els.recordButton.classList.add('is-recording');
        els.recordLabel.textContent = 'Stop recording';
        setStatus('Starting microphone…');
        await request('/record/start', { mode: els.mode.value });
      } else {
        recording = false;
        els.recordButton.classList.remove('is-recording');
        els.recordLabel.textContent = 'Start recording';
        setStatus('Finishing transcript…');
        await request('/record/stop', {});
      }
      clearTimeout(pollTimer);
      pollTimer = setTimeout(refreshStatus, 300);
    } catch (error) {
      recording = false;
      els.recordButton.classList.remove('is-recording');
      els.recordLabel.textContent = 'Start recording';
      setStatus(error.message);
    }
  });

  els.signInButton.addEventListener('click', async () => {
    try {
      await request('/sign-in', {});
      setStatus('Complete ChatGPT sign-in in the Rant for Mac window or browser.');
      clearTimeout(pollTimer);
      pollTimer = setTimeout(refreshStatus, 700);
    } catch (error) { setStatus(error.message); }
  });

  els.copyButton.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(els.resultText.textContent);
      setStatus('Copied to clipboard.');
    } catch { setStatus('Select the text and copy it from the result.'); }
  });

  els.speakButton.addEventListener('click', () => {
    if (!('speechSynthesis' in window)) { setStatus('Read aloud is not available in this browser.'); return; }
    window.speechSynthesis.cancel();
    window.speechSynthesis.speak(new SpeechSynthesisUtterance(els.resultText.textContent));
  });

  window.addEventListener('beforeinstallprompt', event => {
    event.preventDefault();
    installPrompt = event;
    els.installButton.hidden = false;
  });
  els.installButton.addEventListener('click', async () => {
    if (!installPrompt) return;
    installPrompt.prompt();
    await installPrompt.userChoice;
    installPrompt = null;
    els.installButton.hidden = true;
  });

  if ('serviceWorker' in navigator && location.protocol === 'https:') {
    navigator.serviceWorker.register('./service-worker.js').catch(() => {});
  }
  refreshStatus();
})();
