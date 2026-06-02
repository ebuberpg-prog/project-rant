/**
 * WavespeedAI - Client for Wavespeed.ai OpenAI-compatible LLM API
 * Handles audio input chat completions
 */
class WavespeedAI {
  constructor(apiKey, model = 'openai/gpt-audio-mini') {
    this.apiKey = apiKey;
    this.model = model;
    const isLocalhost = typeof window !== 'undefined' && (
      window.location.hostname === 'localhost' ||
      window.location.hostname === '127.0.0.1'
    );
    this.baseUrl = isLocalhost ? '/proxy' : 'https://llm.wavespeed.ai/v1';
  }

  /**
   * Set the model to use
   */
  setModel(model) {
    this.model = model;
  }

  /**
   * Send a chat completion with audio input
   * @param {string} systemPrompt - System prompt text
   * @param {Array} messages - Array of message objects (text or audio)
   * @param {Object} options - Additional options (temperature, etc.)
   * @returns {Promise<Object>} - API response
   */
  async chatCompletion(systemPrompt, messages = [], options = {}) {
    const payload = {
      model: this.model,
      messages: [
        { role: 'system', content: systemPrompt },
        ...messages
      ],
      temperature: options.temperature ?? 0.7,
      max_tokens: options.max_tokens ?? 4000,
      stream: options.stream ?? false
    };

    try {
      const response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`
        },
        body: JSON.stringify(payload)
      });

      if (!response.ok) {
        const errorText = await response.text();
        let errorData;
        try {
          errorData = JSON.parse(errorText);
        } catch {
          errorData = { error: errorText };
        }

        const status = response.status;
        if (status === 401) {
          throw new Error('Invalid API key. Please check your Wavespeed.ai API key.');
        }
        if (status === 429) {
          throw new Error('Rate limit exceeded. Please wait a moment and try again.');
        }
        if (status >= 500) {
          throw new Error('Wavespeed.ai server error. Please try again later.');
        }
        throw new Error(errorData.error?.message || errorData.error || `API error: ${status}`);
      }

      return response.json();
    } catch (err) {
      if (err.name === 'TypeError' && err.message.includes('Failed to fetch')) {
        throw new Error('Connection failed. Run "node server.js" to start the proxy server, then open http://localhost:8080');
      }
      throw err;
    }
  }

  /**
   * Send audio to the LLM for transcription/analysis
   * @param {string} systemPrompt - System prompt
   * @param {string} base64Audio - Base64-encoded audio
   * @param {string} format - Audio format (wav or mp3)
   * @param {Object} options - Additional options
   */
  async sendAudio(systemPrompt, base64Audio, format = 'wav', options = {}) {
    const messages = [{
      role: 'user',
      content: [
        {
          type: 'input_audio',
          input_audio: {
            data: base64Audio,
            format: format
          }
        }
      ]
    }];

    return this.chatCompletion(systemPrompt, messages, options);
  }

  /**
   * Send text message to the LLM
   * @param {string} systemPrompt - System prompt
   * @param {string} text - User text message
   * @param {Array} history - Previous messages for context
   * @param {Object} options - Additional options
   */
  async sendText(systemPrompt, text, history = [], options = {}) {
    const messages = [
      ...history,
      { role: 'user', content: text }
    ];

    return this.chatCompletion(systemPrompt, messages, options);
  }

  /**
   * Send a conversation with mixed text and optional audio
   * For multi-turn: pass history array of {role, content} objects
   */
  async sendConversation(systemPrompt, history = [], options = {}) {
    return this.chatCompletion(systemPrompt, history, options);
  }
}
