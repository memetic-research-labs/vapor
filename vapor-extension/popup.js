document.addEventListener('DOMContentLoaded', () => {
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  const tokenField = document.getElementById('tokenField');
  const saveTokenBtn = document.getElementById('saveTokenBtn');
  const clearTokenBtn = document.getElementById('clearTokenBtn');
  const testBtn = document.getElementById('testBtn');

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
});
