const ICONS = {
  settings: '<svg viewBox="0 0 24 24"><path d="M14 17H5"/><path d="M19 7h-9"/><circle cx="17" cy="17" r="3"/><circle cx="7" cy="7" r="3"/></svg>',
  trash: '<svg viewBox="0 0 24 24"><path d="M10 11v6"/><path d="M14 11v6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>',
  image: '<svg viewBox="0 0 24 24"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>',
  imagePlus: '<svg viewBox="0 0 24 24"><path d="M16 5h6"/><path d="M19 2v6"/><path d="M21 11.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h7.5"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/><circle cx="9" cy="9" r="2"/></svg>',
  globe: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/></svg>',
  scissors: '<svg viewBox="0 0 24 24"><circle cx="6" cy="6" r="3"/><path d="M8.12 8.12 12 12"/><path d="M20 4 8.12 15.88"/><circle cx="6" cy="18" r="3"/><path d="M14.8 14.8 20 20"/></svg>',
  alertTriangle: '<svg viewBox="0 0 24 24"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>',
  activity: '<svg viewBox="0 0 24 24"><path d="M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2"/></svg>',
  check: '<svg viewBox="0 0 24 24"><path d="M20 6 9 17l-5-5"/></svg>',
  terminal: '<svg viewBox="0 0 24 24"><path d="M12 19h8"/><path d="m4 17 6-6-6-6"/></svg>',
  chevronDown: '<svg viewBox="0 0 24 24"><path d="m6 9 6 6 6-6"/></svg>',
  chevronUp: '<svg viewBox="0 0 24 24"><path d="m18 15-6-6-6 6"/></svg>',
  monitor: '<svg viewBox="0 0 24 24"><rect width="20" height="14" x="2" y="3" rx="2"/><line x1="8" x2="16" y1="21" y2="21"/><line x1="12" x2="12" y1="17" y2="21"/></svg>'
};

function icon(name) {
  return ICONS[name] || '';
}

function iconEl(name, sizeClass) {
  return `<span class="icon ${sizeClass || ''}">${icon(name)}</span>`;
}

function escapeHtml(str) {
  return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

const images = [];
let verboseLogging = false;
let settingsOpen = false;
let state = {
  connected: false,
  hasToken: false,
  authFailed: false,
  isSavingToken: false,
  isTestingConnection: false,
  isCapturing: null,
  capturedThisSession: 0,
  message: null,
  messageTimer: null,
  tokenInputValue: '',
  statusLabel: 'Not connected'
};

let statusTimer = null;

const contentEl = document.getElementById('content');
const statusDot = document.getElementById('statusDot');
const statusLabelEl = document.getElementById('statusLabel');
const clearBtn = document.getElementById('clearBtn');
const logToggle = document.getElementById('logToggle');
const logContainer = document.getElementById('logContainer');
const settingsBtn = document.getElementById('settingsBtn');
const settingsPanel = document.getElementById('settingsPanel');
const settingsContent = document.getElementById('settingsContent');
const screenshotCount = document.getElementById('screenshotCount');

settingsBtn.innerHTML = icon('settings');
clearBtn.innerHTML = icon('trash');

function log(level, msg) {
  const ts = new Date().toLocaleTimeString('en-US', { hour12: false });
  const entry = document.createElement('div');
  entry.className = `log-entry ${level}`;
  entry.textContent = `[${ts}] ${msg}`;
  logContainer.appendChild(entry);
  logContainer.scrollTop = logContainer.scrollHeight;
}

function showMessage(kind, text) {
  if (state.messageTimer) window.clearTimeout(state.messageTimer);
  state.message = { kind, text };
  renderSettings();
  state.messageTimer = window.setTimeout(() => {
    state.message = null;
    renderSettings();
  }, 3000);
}

async function refreshStatus() {
  try {
    const response = await chrome.runtime.sendMessage({ type: 'GET_STATUS' });
    state.connected = response?.connected ?? false;
    state.hasToken = response?.hasToken ?? false;
    state.authFailed = response?.authFailed ?? false;
    state.capturedThisSession = response?.capturedThisSession ?? 0;
    updateStatusDot();
    renderSettings();
  } catch {
    state.connected = false;
    updateStatusDot();
  }
}

function computeStatusLabel() {
  if (state.authFailed) return 'Token mismatch';
  if (!state.hasToken) return 'No token configured';
  if (state.connected) return 'Connected';
  if (state.hasToken) return 'Waiting for Vapor';
  return 'Not connected';
}

function updateStatusDot() {
  state.statusLabel = computeStatusLabel();
  statusLabelEl.textContent = state.statusLabel;
  if (state.authFailed) {
    statusDot.className = 'status-dot auth-error';
  } else if (state.connected) {
    statusDot.className = 'status-dot connected';
  } else {
    statusDot.className = 'status-dot disconnected';
  }
}

function statusPillClass() {
  if (state.authFailed) return 'status-pill auth-error';
  if (state.connected) return 'status-pill connected';
  return 'status-pill';
}

function renderSettings() {
  const needsToken = !state.hasToken || state.authFailed;

  settingsContent.innerHTML = `
    <div class="settings-body">
      <div class="${statusPillClass()}">
        <span class="status-dot ${state.authFailed ? 'auth-error' : state.connected ? 'connected' : ''}"></span>
        <span>${escapeHtml(state.statusLabel)}</span>
      </div>

      ${needsToken ? `
        <div class="warning-box">
          ${state.authFailed
            ? 'Token mismatch. Copy the current token from Vapor Settings and paste it below.'
            : 'No auth token. Copy the token from Vapor Settings and paste it below.'}
        </div>
      ` : ''}

      <div class="field-group">
        <label class="field-label" for="tokenField">Auth token</label>
        <input
          id="tokenField"
          class="field-input"
          type="password"
          autocomplete="off"
          value="${escapeHtml(state.tokenInputValue)}"
          placeholder="${state.hasToken ? 'Paste new token to replace' : 'Paste token from Vapor'}"
        />
        <div class="field-hint">Copy the token from Vapor Settings → Browser.</div>
      </div>

      <div class="btn-row">
        <button class="btn btn-primary btn-full" id="saveTokenBtn" ${state.isSavingToken ? 'disabled' : ''}>
          ${iconEl('check')} ${state.isSavingToken ? 'Saving...' : 'Save'}
        </button>
        <button class="btn btn-secondary" id="clearTokenBtn" ${!state.hasToken ? 'disabled' : ''}>Clear</button>
      </div>

      <button class="btn btn-ghost btn-full" id="testConnBtn" ${state.isTestingConnection ? 'disabled' : ''}>
        ${iconEl('activity')} ${state.isTestingConnection ? 'Testing...' : 'Test Connection'}
      </button>

      <div class="capture-stack">
        <button class="capture-btn page" id="capturePageBtn" ${state.isCapturing || needsToken ? 'disabled' : ''}>
          <span class="capture-btn-icon">${icon('monitor')}</span>
          <span class="capture-btn-copy">
            <span class="capture-btn-title">Capture Page</span>
            <span class="capture-btn-hint">${navigator.platform.includes('Mac') ? 'Cmd+Shift+C' : 'Alt+Shift+C'} · Readability</span>
          </span>
        </button>
        <button class="capture-btn selection" id="captureSelBtn" ${state.isCapturing || needsToken ? 'disabled' : ''}>
          <span class="capture-btn-icon">${icon('scissors')}</span>
          <span class="capture-btn-copy">
            <span class="capture-btn-title">Capture Selection</span>
            <span class="capture-btn-hint">Only the highlighted text</span>
          </span>
        </button>
      </div>

      ${state.message ? `<div class="message ${escapeHtml(state.message.kind)}">${escapeHtml(state.message.text)}</div>` : ''}
    </div>
  `;

  const tokenField = document.getElementById('tokenField');
  if (tokenField) {
    tokenField.addEventListener('input', (e) => { state.tokenInputValue = e.target.value; });
  }

  const saveTokenBtn = document.getElementById('saveTokenBtn');
  if (saveTokenBtn) {
    saveTokenBtn.addEventListener('click', async () => {
      const token = (state.tokenInputValue || '').trim();
      if (!token) return;
      state.isSavingToken = true;
      renderSettings();
      try {
        await chrome.runtime.sendMessage({ type: 'SET_TOKEN', token });
        state.tokenInputValue = '';
        await refreshStatus();
        showMessage('success', 'Token saved');
      } catch (err) {
        showMessage('error', err.message || 'Failed to save token');
      }
      state.isSavingToken = false;
      renderSettings();
    });
  }

  const clearTokenBtn = document.getElementById('clearTokenBtn');
  if (clearTokenBtn) {
    clearTokenBtn.addEventListener('click', async () => {
      try {
        await chrome.runtime.sendMessage({ type: 'SET_TOKEN', token: null });
        state.tokenInputValue = '';
        await refreshStatus();
        showMessage('success', 'Token cleared');
      } catch (err) {
        showMessage('error', err.message || 'Failed to clear token');
      }
    });
  }

  const testConnBtn = document.getElementById('testConnBtn');
  if (testConnBtn) {
    testConnBtn.addEventListener('click', async () => {
      state.isTestingConnection = true;
      renderSettings();
      try {
        const result = await chrome.runtime.sendMessage({ type: 'TEST_CONNECTION' });
        if (result?.success) {
          showMessage('success', `Connected — ${result.clients ?? 0} client(s)`);
        } else {
          showMessage('error', result?.error || 'Connection failed');
        }
      } catch (err) {
        showMessage('error', err.message || 'Test failed');
      }
      state.isTestingConnection = false;
      renderSettings();
    });
  }

  const capturePageBtn = document.getElementById('capturePageBtn');
  if (capturePageBtn) {
    capturePageBtn.addEventListener('click', () => doCapture('page', 'CAPTURE_PAGE'));
  }

  const captureSelBtn = document.getElementById('captureSelBtn');
  if (captureSelBtn) {
    captureSelBtn.addEventListener('click', () => doCapture('selection', 'CAPTURE_SELECTION'));
  }
}

async function doCapture(kind, messageType) {
  state.isCapturing = kind;
  renderSettings();
  try {
    const result = await chrome.runtime.sendMessage({ type: messageType });
    if (result?.success) {
      await refreshStatus();
      showMessage('success', kind === 'page' ? 'Page captured' : 'Selection captured');
    } else {
      showMessage('error', result?.error || 'Capture failed');
    }
  } catch (err) {
    showMessage('error', err.message || 'Capture failed');
  }
  state.isCapturing = null;
  renderSettings();
}

function toggleSettings() {
  settingsOpen = !settingsOpen;
  settingsPanel.style.display = settingsOpen ? 'block' : 'none';
  settingsBtn.innerHTML = settingsOpen ? icon('chevronUp') : icon('settings');
  if (settingsOpen) {
    renderSettings();
  }
}

settingsBtn.addEventListener('click', toggleSettings);

chrome.storage.local.get(['vaporSettingsExpanded', 'vaporVerboseLogging'], (items) => {
  const firstRun = items.vaporSettingsExpanded === undefined;
  if (firstRun) {
    chrome.storage.local.set({ vaporSettingsExpanded: true });
  }
  settingsOpen = firstRun || items.vaporSettingsExpanded;
  settingsPanel.style.display = settingsOpen ? 'block' : 'none';
  settingsBtn.innerHTML = settingsOpen ? icon('chevronUp') : icon('settings');
  if (settingsOpen) renderSettings();

  verboseLogging = !!items.vaporVerboseLogging;
  logToggle.textContent = verboseLogging ? 'Compact' : 'Verbose';
  logContainer.style.display = verboseLogging ? 'block' : 'none';
});

async function loadImagesFromStorage() {
  const data = await chrome.storage.local.get(['vaporScreenshotOrder']);
  const order = data.vaporScreenshotOrder || [];

  for (const shaPrefix of order) {
    const key = `vapor_img_${shaPrefix}`;
    const result = await chrome.storage.local.get(key);
    const entry = result[key];
    if (!entry || !entry.base64) continue;

    const binary = atob(entry.base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    const blob = new Blob([bytes], { type: entry.mimeType });
    const url = URL.createObjectURL(blob);

    const existing = images.findIndex(img => img.shaPrefix === shaPrefix);
    const item = {
      mimeType: entry.mimeType,
      size: blob.size,
      dataUrl: url,
      shaPrefix: shaPrefix
    };

    if (existing >= 0) {
      URL.revokeObjectURL(images[existing].dataUrl);
      images[existing] = item;
    } else {
      images.push(item);
    }
  }

  render();
  if (images.length > 0) {
    log('ok', `Loaded ${images.length} screenshot(s) from storage`);
  }
}

function render() {
  if (images.length === 0) {
    contentEl.innerHTML = '<div class="empty"><div class="empty-icon">' + iconEl('imagePlus', 'icon-2xl') + '</div><div class="empty-text">Drag screenshots to AI chats<br>to attach them as images</div></div>';
    screenshotCount.style.display = 'none';
    return;
  }

  screenshotCount.style.display = 'inline';
  screenshotCount.textContent = images.length;

  let html = '<div class="grid">';
  for (let i = 0; i < images.length; i++) {
    const img = images[i];
    const sizeKB = (img.size / 1024).toFixed(0);
    const hash = img.shaPrefix ? `<span class="thumb-hash">${escapeHtml(img.shaPrefix)}</span>` : '';
    html += `<div class="thumb-card" draggable="true" data-index="${i}" title="${escapeHtml(img.mimeType)}, ${sizeKB}KB — drag to AI chat">
      <img src="${img.dataUrl}" alt="Screenshot" />
      <div class="thumb-info">${hash}<span class="thumb-size">${sizeKB}KB</span></div>
    </div>`;
  }
  html += '</div>';

  contentEl.innerHTML = html;

  document.querySelectorAll('.thumb-card[draggable="true"]').forEach(card => {
    card.addEventListener('dragstart', (e) => {
      const idx = parseInt(card.dataset.index, 10);
      const img = images[idx];
      if (!img) return;

      log('ok', `Dragging screenshot ${img.shaPrefix || idx + 1} (${img.mimeType}, ${(img.size / 1024).toFixed(0)}KB)`);

      e.dataTransfer.effectAllowed = 'copy';
      e.dataTransfer.setData('image/webp', img.dataUrl);
      e.dataTransfer.setData('Files', img.dataUrl);

      const filename = img.shaPrefix ? `screenshot_${img.shaPrefix}.webp` : `screenshot_${idx + 1}.webp`;
      const file = new File(
        [img.dataUrl],
        filename,
        { type: img.mimeType }
      );
      e.dataTransfer.items.add(file);
    });
  });
}

clearBtn.addEventListener('click', () => {
  for (const img of images) {
    URL.revokeObjectURL(img.dataUrl);
  }
  images.length = 0;
  render();
  chrome.runtime.sendMessage({ type: 'CLEAR_IMAGES' });
});

logToggle.addEventListener('click', () => {
  verboseLogging = !verboseLogging;
  logToggle.textContent = verboseLogging ? 'Compact' : 'Verbose';
  logContainer.style.display = verboseLogging ? 'block' : 'none';
  chrome.storage.local.set({ vaporVerboseLogging: verboseLogging });
  if (!verboseLogging) logContainer.innerHTML = '';
});

window.addEventListener('beforeunload', () => {
  chrome.storage.local.set({ vaporSettingsExpanded: settingsOpen });
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || !message.type) return false;

  if (message.type === 'UPDATE_IMAGES') {
    loadImagesFromStorage().then(() => {
      if (sendResponse) sendResponse({ success: true, count: images.length });
    });
    return true;
  }

  if (message.type === 'INJECTION_RESULT') {
    const level = message.success ? 'ok' : 'error';
    const msg = message.success
      ? `Text injected on ${message.platform || 'unknown'}${message.autoSubmitted ? ' (auto-submitted)' : ''}`
      : `Injection failed on ${message.platform || 'unknown'}: ${message.error || 'unknown'}`;
    log(level, msg);
    return true;
  }

  return false;
});

refreshStatus();
statusTimer = window.setInterval(refreshStatus, 5000);
loadImagesFromStorage();
