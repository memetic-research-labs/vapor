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

function normalizeHost(urlString) {
  try {
    return new URL(urlString).hostname.toLowerCase().replace(/^www\./, '');
  } catch {
    return '';
  }
}

function inferPlatform(urlString) {
  const host = normalizeHost(urlString);
  if (host.includes('chatgpt') || host.includes('openai')) return 'chatgpt';
  if (host.includes('claude')) return 'claude';
  if (host.includes('gemini')) return 'gemini';
  if (host.includes('grok') || host === 'x.com') return 'grok';
  if (host.includes('perplexity')) return 'perplexity';
  return 'browser';
}

function isCandidateTab(tab) {
  const url = tab.url || '';
  if (!url) return false;
  if (url.startsWith('chrome://')) return false;
  if (url.startsWith('chrome-extension://')) return false;
  if (url.startsWith('about:')) return false;
  if (url.startsWith('edge://')) return false;
  return true;
}

function serializeTab(tab) {
  return {
    tab_id: tab.id,
    title: tab.title || '',
    url: tab.url || '',
    platform: inferPlatform(tab.url || '')
  };
}

async function listCandidateTabs() {
  const tabs = await chrome.tabs.query({ windowType: 'normal' });
  return tabs.filter(isCandidateTab).map(serializeTab);
}

async function focusTab(tab) {
  if (!tab || !tab.id) return;
  if (typeof tab.windowId === 'number') {
    await chrome.windows.update(tab.windowId, { focused: true });
  }
  await chrome.tabs.update(tab.id, { active: true });
}

async function resolvePromptTab(tabIdRaw) {
  if (typeof tabIdRaw === 'number') {
    try {
      return await chrome.tabs.get(tabIdRaw);
    } catch {
      return null;
    }
  }

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab || null;
}

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
        } else if (data.type === 'QUERY_TABS') {
          await handleQueryTabs();
        } else if (data.type === 'VERIFY_TARGET') {
          await handleVerifyTarget(data);
        } else if (data.type === 'OPEN_TAB') {
          await handleOpenTab(data);
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
  const requestedTabId = typeof data.tab_id === 'number' ? data.tab_id : null;

  const tab = await resolvePromptTab(requestedTabId);
  if (!tab) {
    await postResponse({ type: 'PROMPT_INJECTED', success: false, error: 'Target tab unavailable', tabId: requestedTabId });
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

    await focusTab(tab);

    await postResponse({
      type: 'PROMPT_INJECTED',
      success: result?.success ?? false,
      platform: result?.platform ?? 'unknown',
      tabUrl: tab.url || '',
      tabId: tab.id
    });
  } catch (err) {
    await postResponse({
      type: 'PROMPT_INJECTED',
      success: false,
      error: err.message || String(err),
      tabId: tab.id
    });
  }
}

async function handleQueryTabs() {
  try {
    const tabs = await listCandidateTabs();
    await postResponse({ type: 'TABS_RESULT', tabs });
  } catch (err) {
    await postResponse({ type: 'TABS_RESULT', tabs: [], error: err.message || String(err) });
  }
}

async function handleVerifyTarget(data) {
  const host = (data.host || '').toLowerCase();
  const url = data.url || '';

  try {
    const tabs = await listCandidateTabs();
    const match = tabs.find((tab) => {
      const tabHost = normalizeHost(tab.url);
      if (host && tabHost === host) return true;
      if (url && tab.url === url) return true;
      return false;
    });

    await postResponse(match
      ? { type: 'TARGET_VERIFY_RESULT', found: true, ...match }
      : { type: 'TARGET_VERIFY_RESULT', found: false, host, url });
  } catch (err) {
    await postResponse({ type: 'TARGET_VERIFY_RESULT', found: false, host, url, error: err.message || String(err) });
  }
}

async function handleOpenTab(data) {
  const url = data.url || '';
  if (!url) {
    await postResponse({ type: 'TAB_OPENED', success: false, error: 'Missing URL' });
    return;
  }

  try {
    const tab = await chrome.tabs.create({ url, active: true });
    await focusTab(tab);
    await postResponse({ type: 'TAB_OPENED', success: true, ...serializeTab(tab) });
  } catch (err) {
    await postResponse({ type: 'TAB_OPENED', success: false, url, error: err.message || String(err) });
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
      return { ok: true };
    }
    let errorText = '';
    try { errorText = await response.text(); } catch (_) {}
    const hint = response.status === 401 || response.status === 403
      ? 'Auth token missing or invalid'
      : errorText || `HTTP ${response.status}`;
    console.error('[Vapor] Context capture rejected:', response.status, hint);
    return { ok: false, status: response.status, error: hint };
  } catch (err) {
    console.error('[Vapor] Failed to post context capture:', err);
    return { ok: false, error: err.message || String(err) };
  }
}

async function handleCaptureRequest(captureType) {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) return { success: false, error: 'No active tab' };

  if (!isConnected) return { success: false, error: 'Not connected to Vapor' };

  try {
    const scriptsToInject = ['libs/readability.js', 'content-scripts/context-capture.js'];
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: scriptsToInject
    });

    const msgType = captureType === 'selection' ? 'CAPTURE_SELECTION' : 'CAPTURE_PAGE';

    const result = await chrome.tabs.sendMessage(tab.id, { type: msgType });

    if (!result || !result.success) {
      return { success: false, error: result?.error || 'Capture failed' };
    }

    const postResult = await postContextCapture(result.payload);
    if (!postResult.ok) {
      return { success: false, error: postResult.error || `HTTP ${postResult.status}` };
    }
    return { success: true, jobId: result.payload.jobId, payload: result.payload };
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

  if (message.type === 'CAPTURE_PAGE') {
    handleCaptureRequest('page')
      .then(sendResponse)
      .catch(err => sendResponse({ success: false, error: err?.message ?? String(err) }));
    return true;
  }

  if (message.type === 'CAPTURE_SELECTION') {
    handleCaptureRequest('selection')
      .then(sendResponse)
      .catch(err => sendResponse({ success: false, error: err?.message ?? String(err) }));
    return true;
  }

  // Legacy support for old sidepanel versions
  if (message.type === 'CAPTURE_ARTICLE') {
    handleCaptureRequest('page')
      .then(sendResponse)
      .catch(err => sendResponse({ success: false, error: err?.message ?? String(err) }));
    return true;
  }

  if (message.type === 'CAPTURE_PAGE_SNAPSHOT') {
    handleCaptureRequest('page')
      .then(sendResponse)
      .catch(err => sendResponse({ success: false, error: err?.message ?? String(err) }));
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

chrome.commands.onCommand.addListener((command) => {
  if (command !== 'capture-page') return;

  handleCaptureRequest('page').catch((err) => {
    console.error('[Vapor] Keyboard capture failed:', err);
  });
});

// Start
connect();

chrome.runtime.onInstalled.addListener(() => {
  updateBadge('disconnected');
  if (DEBUG) console.log('[Vapor] Extension installed');
});
