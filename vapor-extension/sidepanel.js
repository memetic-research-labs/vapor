document.addEventListener('DOMContentLoaded', () => {
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  const tokenField = document.getElementById('tokenField');
  const saveTokenBtn = document.getElementById('saveTokenBtn');
  const clearTokenBtn = document.getElementById('clearTokenBtn');
  const testBtn = document.getElementById('testBtn');
  const captureArticleBtn = document.getElementById('captureArticleBtn');
  const captureSelectionBtn = document.getElementById('captureSelectionBtn');
  const captureSnapshotBtn = document.getElementById('captureSnapshotBtn');
  const captureCountEl = document.getElementById('captureCount');
  const captureResultEl = document.getElementById('captureResult');
  const captureListEl = document.getElementById('captureList');

  let isTokenSaved = false;
  let capturedItems = [];

  async function refreshStatus() {
    try {
      const response = await chrome.runtime.sendMessage({ type: 'GET_STATUS' });
      const connected = response?.connected ?? false;
      const hasToken = response?.hasToken ?? false;

      statusDot.className = connected ? 'dot connected' : 'dot disconnected';
      statusText.className = 'status-value' + (connected ? ' connected' : '');
      statusText.textContent = connected ? 'Connected to Vapor' : 'Not connected';

      if (!connected && !hasToken) {
        statusText.textContent = 'No connection';
      } else if (connected && !hasToken) {
        statusText.textContent = 'Connected — set token';
      }

      if (hasToken && !isTokenSaved) {
        tokenField.value = '';
        tokenField.placeholder = 'Token saved';
        tokenField.disabled = true;
        isTokenSaved = true;
      } else if (!hasToken && isTokenSaved) {
        tokenField.placeholder = 'Paste token from Vapor Settings';
        tokenField.disabled = false;
        isTokenSaved = false;
      }

      captureCountEl.textContent = capturedItems.length;
    } catch (err) {
      statusText.textContent = 'Error checking status';
    }
  }

  refreshStatus();
  setInterval(refreshStatus, 3000);

  tokenField.addEventListener('input', () => {
    tokenField.disabled = false;
    tokenField.placeholder = 'Paste token from Vapor Settings';
  });

  saveTokenBtn.addEventListener('click', async () => {
    const token = tokenField.value.trim();
    if (!token) return;
    await chrome.runtime.sendMessage({ type: 'SET_TOKEN', token });
    tokenField.value = '';
    tokenField.placeholder = 'Saved';
    tokenField.disabled = true;
    isTokenSaved = true;
    refreshStatus();
  });

  clearTokenBtn.addEventListener('click', async () => {
    await chrome.runtime.sendMessage({ type: 'SET_TOKEN', token: null });
    tokenField.value = '';
    tokenField.placeholder = 'Paste token from Vapor Settings';
    tokenField.disabled = false;
    isTokenSaved = false;
    refreshStatus();
  });

  testBtn.addEventListener('click', async () => {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab) return;
    try {
      await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        files: ['content-scripts/prompt-injector.js']
      });
      await chrome.tabs.sendMessage(tab.id, {
        type: 'SET_PROMPT',
        text: 'Hello from Vapor!',
        autoSubmit: false
      });
    } catch (err) {
      console.error('[Vapor] Test inject failed:', err);
    }
  });

  const kindIcons = {
    articleText: '\uD83D\uDCC4',
    selectedText: '\u2702\uFE0F',
    pageSnapshot: '\uD83C\uDF10'
  };

  function addCapturedItem(result) {
    const kind = result.payload?.kind || 'unknown';
    const title = result.payload?.title || 'Untitled';
    capturedItems.unshift({ kind, title, jobId: result.jobId });
    captureCountEl.textContent = capturedItems.length;
    renderCapturedItems();
  }

  function renderCapturedItems() {
    captureListEl.innerHTML = '';
    for (const item of capturedItems) {
      const div = document.createElement('div');
      div.className = 'capture-item';
      div.innerHTML = `
        <span class="kind-icon">${kindIcons[item.kind] || '\uD83D\uDCCB'}</span>
        <span class="item-title" title="${item.title}">${item.title}</span>
        <span class="item-status">sent</span>
      `;
      captureListEl.appendChild(div);
    }
  }

  function showCaptureResult(success, message) {
    captureResultEl.textContent = message;
    captureResultEl.className = 'capture-result ' + (success ? 'success' : 'error');
    captureResultEl.style.display = 'block';
    setTimeout(() => { captureResultEl.style.display = 'none'; }, 5000);
  }

  function doCapture(type, msgType, btn) {
    btn.disabled = true;
    const origText = btn.textContent;
    btn.textContent = 'Capturing...';
    chrome.runtime.sendMessage({ type: msgType }).then(result => {
      btn.disabled = false;
      btn.textContent = origText;
      if (result?.success) {
        addCapturedItem(result);
        showCaptureResult(true, 'Captured and sent to Vapor');
      } else {
        console.error('[Vapor] Capture failed:', JSON.stringify(result));
        showCaptureResult(false, result?.error || 'Capture failed');
      }
    }).catch(err => {
      btn.disabled = false;
      btn.textContent = origText;
      console.error('[Vapor] Capture error:', err);
      showCaptureResult(false, err.message || 'Capture failed');
    });
  }

  captureArticleBtn.addEventListener('click', () => {
    doCapture('article', 'CAPTURE_ARTICLE', captureArticleBtn);
  });

  captureSelectionBtn.addEventListener('click', () => {
    doCapture('selection', 'CAPTURE_SELECTION', captureSelectionBtn);
  });

  captureSnapshotBtn.addEventListener('click', () => {
    doCapture('snapshot', 'CAPTURE_PAGE_SNAPSHOT', captureSnapshotBtn);
  });
});
