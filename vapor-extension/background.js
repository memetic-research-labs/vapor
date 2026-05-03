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
let authFailed = false;

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
  return new Promise((resolve) => {
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
}

async function connect() {
  if (eventSource) {
    eventSource.close();
  }

  await ensureAuthTokenLoaded();

  if (!authToken) {
    if (DEBUG) console.log('[Vapor] No auth token — skipping connection');
    isConnected = false;
    authFailed = false;
    updateBadge('disconnected');
    return;
  }

  authFailed = false;

  try {
    const url = `${SERVER_URL}/api/stream?token=${encodeURIComponent(authToken)}`;

    if (DEBUG) console.log('[Vapor] Connecting to', SERVER_URL);

    eventSource = new EventSource(url);

    eventSource.onopen = () => {
      isConnected = true;
      reconnectAttempts = 0;
      authFailed = false;
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
        } else if (data.type === 'INTERROGATE_TAB') {
          await handleInterrogateTab(data);
        } else if (data.type === 'PREVIEW_SOURCE') {
          await handlePreviewSource(data);
        } else if (data.type === 'REFRESH_XHR_SOURCES') {
          await handleRefreshXHRSources(data);
        }
      } catch (err) {
        console.error('[Vapor] Error parsing prompt event:', err);
      }
    });

    eventSource.addEventListener('sidebar_screenshot', async (e) => {
      try {
        const data = JSON.parse(e.data);
        await handleSidebarScreenshot(data);
      } catch (err) {
        console.error('[Vapor] Error parsing sidebar_screenshot event:', err);
      }
    });

    eventSource.addEventListener('sidebar_screenshot_remove', async (e) => {
      try {
        const data = JSON.parse(e.data);
        await handleSidebarScreenshotRemove(data);
      } catch (err) {
        console.error('[Vapor] Error parsing sidebar_screenshot_remove event:', err);
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
    } else if (status === 'auth-error') {
      api.setBadgeText({ text: '!' });
      api.setBadgeBackgroundColor({ color: '#ef4444' });
      api.setTitle({ title: 'Vapor – Token mismatch. Copy token from Vapor Settings.' });
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

function broadcastToSidebar(message) {
  chrome.runtime.sendMessage(message).catch(() => {});
}

const MAX_SIDEBAR_SCREENSHOTS = 64;

async function handleSidebarScreenshot(data) {
  const shaPrefix = data.shaPrefix;
  if (!shaPrefix) return;

  const key = `vapor_img_${shaPrefix}`;
  const entry = {
    shaPrefix: shaPrefix,
    mimeType: data.mimeType || 'image/webp',
    base64: data.data,
    timestamp: data.timestamp || Math.floor(Date.now() / 1000)
  };

  const { vaporScreenshotOrder = [] } = await chrome.storage.local.get('vaporScreenshotOrder');
  const order = vaporScreenshotOrder.filter(s => s !== shaPrefix);
  order.unshift(shaPrefix);

  while (order.length > MAX_SIDEBAR_SCREENSHOTS) {
    const removed = order.pop();
    await chrome.storage.local.remove(`vapor_img_${removed}`);
    if (DEBUG) console.log('[Vapor] Pruned sidebar screenshot:', removed);
  }

  let writeSucceeded = false;
  while (!writeSucceeded) {
    try {
      await chrome.storage.local.set({ [key]: entry, vaporScreenshotOrder: order });
      writeSucceeded = true;
    } catch (err) {
      const removed = [...order].reverse().find(s => s !== shaPrefix);
      if (!removed) {
        console.error('[Vapor] Failed to store sidebar screenshot:', err);
        broadcastToSidebar({
          type: 'SIDEBAR_ERROR',
          message: 'Could not store screenshot. Chrome extension storage is full.'
        });
        return;
      }
      order.splice(order.indexOf(removed), 1);
      await chrome.storage.local.remove(`vapor_img_${removed}`);
      if (DEBUG) console.log('[Vapor] Pruned screenshot after storage failure:', removed);
    }
  }

  broadcastToSidebar({ type: 'UPDATE_IMAGES' });
  if (DEBUG) console.log('[Vapor] Stored sidebar screenshot:', shaPrefix, `(${(entry.base64.length * 0.75 / 1024).toFixed(0)}KB)`);
}

async function handleSidebarScreenshotRemove(data) {
  const shaPrefix = data.shaPrefix;
  if (!shaPrefix) return;

  await chrome.storage.local.remove(`vapor_img_${shaPrefix}`);

  const { vaporScreenshotOrder = [] } = await chrome.storage.local.get('vaporScreenshotOrder');
  await chrome.storage.local.set({ vaporScreenshotOrder: vaporScreenshotOrder.filter(s => s !== shaPrefix) });

  broadcastToSidebar({ type: 'UPDATE_IMAGES' });
  if (DEBUG) console.log('[Vapor] Removed sidebar screenshot:', shaPrefix);
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

async function handleInterrogateTab(data) {
  const tabId = typeof data.tab_id === 'number' ? data.tab_id : null;
  if (!tabId) {
    await postResponse({ type: 'RESEARCH_SOURCES_DISCOVERED', tabId: null, sources: [], error: 'Missing tab_id' });
    return;
  }

  try {
    const tab = await chrome.tabs.get(tabId);
    await focusTab(tab);

    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ['content-scripts/page-inspector.js']
    });

    const result = await chrome.tabs.sendMessage(tab.id, { type: 'INSPECT_PAGE' });

    if (!result || !result.success) {
      await postResponse({
        type: 'RESEARCH_SOURCES_DISCOVERED',
        tabId: tabId,
        sources: [],
        error: result?.error || 'Inspection failed'
      });
      return;
    }

    await postResponse({
      type: 'RESEARCH_SOURCES_DISCOVERED',
      tabId: tabId,
      tabUrl: tab.url,
      tabTitle: tab.title,
      sources: result.sources
    });
  } catch (err) {
    await postResponse({
      type: 'RESEARCH_SOURCES_DISCOVERED',
      tabId: tabId,
      sources: [],
      error: err.message || String(err)
    });
  }
}

async function handlePreviewSource(data) {
  const tabId = typeof data.tab_id === 'number' ? data.tab_id : null;
  const sourceId = data.source_id;
  if (!tabId || !sourceId) {
    await postResponse({ type: 'RESEARCH_SOURCE_PREVIEW', sourceId: sourceId, error: 'Missing tab_id or source_id' });
    return;
  }

  try {
    const result = await chrome.tabs.sendMessage(tabId, { type: 'PREVIEW_SOURCE', sourceId });

    if (!result || !result.success) {
      await postResponse({
        type: 'RESEARCH_SOURCE_PREVIEW',
        sourceId: sourceId,
        error: result?.error || 'Preview failed'
      });
      return;
    }

    await postResponse({
      type: 'RESEARCH_SOURCE_PREVIEW',
      sourceId: sourceId,
      preview: result.preview
    });
  } catch (err) {
    await postResponse({
      type: 'RESEARCH_SOURCE_PREVIEW',
      sourceId: sourceId,
      error: err.message || String(err)
    });
  }
}

async function handleRefreshXHRSources(data) {
  const tabId = typeof data.tab_id === 'number' ? data.tab_id : null;
  if (!tabId) {
    await postResponse({ type: 'XHR_SOURCES_REFRESHED', tabId: null, sources: [], error: 'Missing tab_id' });
    return;
  }

  try {
    const result = await chrome.tabs.sendMessage(tabId, { type: 'REFRESH_XHR_SOURCES' });
    if (!result || !result.success) {
      await postResponse({
        type: 'XHR_SOURCES_REFRESHED',
        tabId: tabId,
        sources: [],
        error: result?.error || 'Refresh failed'
      });
      return;
    }
    await postResponse({
      type: 'XHR_SOURCES_REFRESHED',
      tabId: tabId,
      sources: result.sources
    });
  } catch (err) {
    await postResponse({
      type: 'XHR_SOURCES_REFRESHED',
      tabId: tabId,
      sources: [],
      error: err.message || String(err)
    });
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
      return { success: false, error: postResult.error || (postResult.status ? `HTTP ${postResult.status}` : 'Post failed') };
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
    authFailed = false;
    connect();
    sendResponse({ success: true });
    return true;
  }

  if (message.type === 'GET_STATUS') {
    const actuallyConnected = isConnected && eventSource && eventSource.readyState === EventSource.OPEN;
    sendResponse({ connected: actuallyConnected, hasToken: !!authToken, authFailed, capturedThisSession });
    return true;
  }

  if (message.type === 'CAPTURE_PAGE') {
    handleCaptureRequest('page')
      .then(sendResponse)
      .catch(err => sendResponse({ success: false, error: err?.message ?? String(err) }));
    return true;
  }

  if (message.type === 'TEST_CONNECTION') {
    (async () => {
      try {
        const headers = { 'Content-Type': 'application/json' };
        if (authToken) headers['Authorization'] = `Bearer ${authToken}`;
        const resp = await fetch(`${SERVER_URL}/api/status`, { headers });
        if (resp.ok) {
          const body = await resp.json();
          sendResponse({ success: true, status: body.status, clients: body.connectedClients });
        } else if (resp.status === 401 || resp.status === 403) {
          sendResponse({ success: false, error: 'Token mismatch — copy the current token from Vapor Settings' });
        } else {
          sendResponse({ success: false, error: `HTTP ${resp.status}` });
        }
      } catch (err) {
        sendResponse({ success: false, error: 'Vapor is not running' });
      }
    })();
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

  // Forward injection logs/results to sidebar
  if (message.type === 'INJECTION_RESULT' || message.type === 'INJECTION_LOG') {
    broadcastToSidebar(message);
  }

  // Sidebar messages
  if (message.type === 'CLEAR_IMAGES') {
    (async () => {
      const { vaporScreenshotOrder = [] } = await chrome.storage.local.get('vaporScreenshotOrder');
      const keysToRemove = vaporScreenshotOrder.map(s => `vapor_img_${s}`);
      if (keysToRemove.length > 0) {
        await chrome.storage.local.remove([...keysToRemove, 'vaporScreenshotOrder']);
      }
      broadcastToSidebar({ type: 'UPDATE_IMAGES' });
      sendResponse({ success: true });
    })();
    return true;
  }

  return false;
});

chrome.action.onClicked.addListener(async (tab) => {
  if (tab?.id) {
    chrome.sidePanel.open({ tabId: tab.id }).catch(() => {});
  }
});

chrome.commands.onCommand.addListener(async (command) => {

  if (command !== 'capture-page') return;

  handleCaptureRequest('page').catch((err) => {
    console.error('[Vapor] Keyboard capture failed:', err);
  });
});

const KEEPALIVE_ALARM = 'vapor-keepalive';
const KEEPALIVE_INTERVAL_MINUTES = 0.5;

function startKeepalive() {
  chrome.alarms.create(KEEPALIVE_ALARM, { periodInMinutes: KEEPALIVE_INTERVAL_MINUTES });
  if (DEBUG) console.log('[Vapor] Keepalive alarm registered (every 30s)');
}

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== KEEPALIVE_ALARM) return;
  if (!authToken) return;

  const alive = eventSource && eventSource.readyState === EventSource.OPEN;

  fetch(`${SERVER_URL}/api/status`, { headers: { 'Authorization': `Bearer ${authToken}` } })
    .then(r => {
      if (r.status === 401 || r.status === 403) {
        if (DEBUG) console.log('[Vapor] Keepalive: auth rejected, marking token mismatch');
        authFailed = true;
        isConnected = false;
        updateBadge('auth-error');
        if (eventSource) eventSource.close();
        return;
      }
      if (!r.ok) return;
      return r.json();
    })
    .then(body => {
      if (!body) return;
      if (!alive || body.connectedClients === 0) {
        if (DEBUG) console.log('[Vapor] Keepalive: SSE not alive or 0 clients, reconnecting');
        connect();
      }
    })
    .catch(() => {
      if (isConnected) {
        if (DEBUG) console.log('[Vapor] Keepalive: server unreachable');
        isConnected = false;
        updateBadge('disconnected');
      }
    });
});

// Start
connect();
startKeepalive();

chrome.runtime.onInstalled.addListener(() => {
  updateBadge('disconnected');
  if (DEBUG) console.log('[Vapor] Extension installed');
  startKeepalive();
});
