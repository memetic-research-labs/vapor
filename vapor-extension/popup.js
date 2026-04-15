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

  let isTokenSaved = false;

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
        tokenField.placeholder = 'Token saved ✓';
        tokenField.disabled = true;
        isTokenSaved = true;
      } else if (!hasToken && isTokenSaved) {
        tokenField.placeholder = 'Paste token from Vapor Settings';
        tokenField.disabled = false;
        isTokenSaved = false;
      }

      captureCountEl.textContent = response.capturedThisSession ?? 0;
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
    tokenField.placeholder = 'Saved ✓';
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

  function showCaptureResult(success, message) {
    captureResultEl.textContent = message;
    captureResultEl.className = 'capture-result ' + (success ? 'success' : 'error');
    captureResultEl.style.display = 'block';
    setTimeout(() => { captureResultEl.style.display = 'none'; }, 3000);
  }

  captureArticleBtn.addEventListener('click', async () => {
    captureArticleBtn.disabled = true;
    captureArticleBtn.textContent = 'Capturing...';
    const result = await chrome.runtime.sendMessage({ type: 'CAPTURE_ARTICLE' });
    captureArticleBtn.disabled = false;
    captureArticleBtn.textContent = 'Capture Article';
    if (result?.success) {
      showCaptureResult(true, 'Article captured and sent to Vapor');
      captureCountEl.textContent = parseInt(captureCountEl.textContent || '0') + 1;
    } else {
      showCaptureResult(false, result?.error || 'Capture failed');
    }
  });

  captureSelectionBtn.addEventListener('click', async () => {
    captureSelectionBtn.disabled = true;
    captureSelectionBtn.textContent = 'Capturing...';
    const result = await chrome.runtime.sendMessage({ type: 'CAPTURE_SELECTION' });
    captureSelectionBtn.disabled = false;
    captureSelectionBtn.textContent = 'Capture Selection';
    if (result?.success) {
      showCaptureResult(true, 'Selection captured and sent to Vapor');
      captureCountEl.textContent = parseInt(captureCountEl.textContent || '0') + 1;
    } else {
      showCaptureResult(false, result?.error || 'Capture failed');
    }
  });

  captureSnapshotBtn.addEventListener('click', async () => {
    captureSnapshotBtn.disabled = true;
    captureSnapshotBtn.textContent = 'Capturing...';
    const result = await chrome.runtime.sendMessage({ type: 'CAPTURE_PAGE_SNAPSHOT' });
    captureSnapshotBtn.disabled = false;
    captureSnapshotBtn.textContent = 'Capture Page Text';
    if (result?.success) {
      showCaptureResult(true, 'Page text captured and sent to Vapor');
      captureCountEl.textContent = parseInt(captureCountEl.textContent || '0') + 1;
    } else {
      showCaptureResult(false, result?.error || 'Capture failed');
    }
  });
});
