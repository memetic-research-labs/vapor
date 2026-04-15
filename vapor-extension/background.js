/**
 * Vapor – Prompt Injector
 * Background Service Worker
 *
 * Connects to the Vapor Mac app via SSE and injects compressed prompts
 * into AI chat interfaces.
 *
 * Architecture (adapted from prompt-audit/extension-minimal):
 *   Vapor Mac App → SSE → This Extension → Chrome APIs → Content Scripts
 *   Content Scripts → This Extension → HTTP POST → Vapor Mac App
 */

const DEBUG = true;
const SERVER_URL = 'http://127.0.0.1:8766';
const RECONNECT_DELAY_BASE = 1000;
const RECONNECT_DELAY_MAX = 8000;

let eventSource = null;
let reconnectAttempts = 0;
let isConnected = false;
let authToken = null;
let capturedThisSession = 0;

let authTokenLoadPromise = null;

function ensureAuthTokenLoaded() {
  if (authTokenLoadPromise) return authTokenLoadPromise;

  authTokenLoadPromise = new Promise((resolve) => {
    chrome.storage.local.get(['vaporAuthToken'], (items) => {
      if (chrome.runtime.lastError) {
        console.error('[Vapor] Failed to load token:', chrome.runtime.lastError);
        authToken = null;
      } else {
        authToken = items.vaporAuthToken || null;
        if (DEBUG) console.log('[Vapor] Loaded token:', authToken ? '***' : 'none');
      }
      resolve(authToken);
    });
  });

  return authTokenLoadPromise;
}

async function connect() {
  if (eventSource) {
    eventSource.close();
  }

  await ensureAuthTokenLoaded();

  try {
    const url = authToken
      ? `${SERVER_URL}/api/stream?token=${encodeURIComponent(authToken)}`
      : `${SERVER_URL}/api/stream`;

    if (DEBUG) console.log('[Vapor] Connecting to', url);

    eventSource = new EventSource(url);

    eventSource.onopen = () => {
      isConnected = true;
      reconnectAttempts = 0;
      updateBadge('connected');
      if (DEBUG) console.log('[Vapor] SSE connected');
    };

    eventSource.addEventListener('prompt', async (e) => {
      try {
        const data = JSON.parse(e.data);
        if (data.type === 'PROMPT_INJECT') {
          await handlePromptInject(data);
        } else if (data.type === 'ACTIVATE_PICKER') {
          await handleActivatePicker();
        }
      } catch (err) {
        console.error('[Vapor] Error parsing prompt event:', err);
      }
    });

    eventSource.addEventListener('heartbeat', () => {
      // Heartbeat keeps the SSE connection alive; no action needed
    });

    eventSource.onerror = () => {
      isConnected = false;
      updateBadge('disconnected');
      if (DEBUG) console.log('[Vapor] SSE error, reconnecting...');
      eventSource.close();
      reconnect();
    };
  } catch (error) {
    console.error('[Vapor] Failed to connect:', error);
    reconnect();
  }
}

let reconnectTimer = null;

function reconnect() {
  if (reconnectTimer) clearTimeout(reconnectTimer);
  const delay = Math.min(
    RECONNECT_DELAY_BASE * Math.pow(2, reconnectAttempts),
    RECONNECT_DELAY_MAX
  );
  reconnectAttempts++;
  if (DEBUG) console.log(`[Vapor] Reconnecting in ${delay}ms (attempt ${reconnectAttempts})`);
  reconnectTimer = setTimeout(connect, delay);
}

function updateBadge(status) {
  try {
    const api = chrome.action || chrome.browserAction;
    if (!api || typeof api.setBadgeText !== 'function') return;

    if (status === 'connected') {
      api.setBadgeText({ text: '' });
      api.setBadgeBackgroundColor({ color: '#22c55e' });
      api.setTitle({ title: 'Vapor – Connected' });
    } else {
      api.setBadgeText({ text: '!' });
      api.setBadgeBackgroundColor({ color: '#ef4444' });
      api.setTitle({ title: 'Vapor – Disconnected' });
    }
  } catch (err) {
    // Badge API not available in this environment
  }
}

async function handlePromptInject(data) {
  const text = data.text || '';
  const autoSubmit = data.autoSubmit || false;

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) {
    await postResponse({ type: 'PROMPT_INJECTED', success: false, error: 'No active tab' });
    return;
  }

  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ['content-scripts/prompt-injector.js']
    });

    const result = await chrome.tabs.sendMessage(tab.id, {
      type: 'SET_PROMPT',
      text,
      autoSubmit
    });

    await postResponse({
      type: 'PROMPT_INJECTED',
      success: result?.success ?? false,
      platform: result?.platform ?? 'unknown',
      tabUrl: tab.url || ''
    });
  } catch (err) {
    await postResponse({
      type: 'PROMPT_INJECTED',
      success: false,
      error: err.message || String(err)
    });
  }
}

async function handleActivatePicker() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) return;

  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ['content-scripts/prompt-injector.js']
    });
    await chrome.tabs.sendMessage(tab.id, { type: 'ACTIVATE_PICKER' });
  } catch (err) {
    console.error('[Vapor] Failed to activate picker:', err);
  }
}

async function postResponse(body) {
  try {
    const headers = { 'Content-Type': 'application/json' };
    if (authToken) {
      headers['Authorization'] = `Bearer ${authToken}`;
    }
    await fetch(`${SERVER_URL}/api/response`, {
      method: 'POST',
      headers,
      body: JSON.stringify(body)
    });
  } catch (err) {
    console.error('[Vapor] Failed to post response:', err);
  }
}

async function postContextCapture(payload) {
  try {
    const headers = { 'Content-Type': 'application/json' };
    if (authToken) {
      headers['Authorization'] = `Bearer ${authToken}`;
    }
    const response = await fetch(`${SERVER_URL}/api/context`, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload)
    });
    if (response.ok) {
      capturedThisSession++;
    }
    return response.ok;
  } catch (err) {
    console.error('[Vapor] Failed to post context capture:', err);
    return false;
  }
}

async function handleCaptureRequest(captureType) {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) return { success: false, error: 'No active tab' };

  if (!isConnected) return { success: false, error: 'Not connected to Vapor' };

  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ['content-scripts/context-capture.js']
    });

    const msgType = captureType === 'article' ? 'CAPTURE_ARTICLE'
      : captureType === 'selection' ? 'CAPTURE_SELECTION'
      : 'CAPTURE_PAGE_SNAPSHOT';

    const result = await chrome.tabs.sendMessage(tab.id, { type: msgType });

    if (!result || !result.success) {
      return { success: false, error: result?.error || 'Capture failed' };
    }

    const ok = await postContextCapture(result.payload);
    return { success: ok, jobId: result.payload.jobId };
  } catch (err) {
    return { success: false, error: err.message || String(err) };
  }
}

// Listen for messages from popup (token management)
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || !message.type) return;

  if (message.type === 'SET_TOKEN') {
    authToken = message.token || null;
    chrome.storage.local.set({ vaporAuthToken: authToken });
    connect();
    sendResponse({ success: true });
    return true;
  }

  if (message.type === 'GET_STATUS') {
    sendResponse({ connected: isConnected, hasToken: !!authToken, capturedThisSession });
    return true;
  }

  if (message.type === 'CAPTURE_ARTICLE') {
    handleCaptureRequest('article').then(sendResponse);
    return true;
  }

  if (message.type === 'CAPTURE_SELECTION') {
    handleCaptureRequest('selection').then(sendResponse);
    return true;
  }

  if (message.type === 'CAPTURE_PAGE_SNAPSHOT') {
    handleCaptureRequest('snapshot').then(sendResponse);
    return true;
  }

  // Forward content script messages to Vapor
  if (message.type === 'PROMPT_INJECT_RESULT' ||
      message.type === 'PICKER_CANCELLED' ||
      message.type === 'TARGET_SELECTED') {
    postResponse(message);
  }

  return false;
});

// Start
connect();

chrome.runtime.onInstalled.addListener(() => {
  updateBadge('disconnected');
  if (DEBUG) console.log('[Vapor] Extension installed');
});
