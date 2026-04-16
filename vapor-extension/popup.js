class VaporPopupApp extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    this.state = {
      connected: false,
      hasToken: false,
      isSettingsOpen: false,
      isSavingToken: false,
      isCapturing: null,
      capturedThisSession: 0,
      message: null,
      tokenInputValue: ''
    };
    this.statusTimer = null;
    this.messageTimer = null;
  }

  connectedCallback() {
    this.render();
    this.bindEvents();
    this.refreshStatus();
    this.statusTimer = window.setInterval(() => this.refreshStatus(), 5000);
  }

  disconnectedCallback() {
    if (this.statusTimer) window.clearInterval(this.statusTimer);
    if (this.messageTimer) window.clearTimeout(this.messageTimer);
  }

  bindEvents() {
    const root = this.shadowRoot;
    root.addEventListener('click', async (event) => {
      const action = event.target.closest('[data-action]')?.dataset.action;
      if (!action) return;

      if (action === 'open-settings') {
        this.setState({ isSettingsOpen: true, message: null });
        return;
      }

      if (action === 'close-settings') {
        this.setState({ isSettingsOpen: false, message: null });
        return;
      }

      if (action === 'capture-page') {
        await this.capture('page', 'CAPTURE_PAGE');
        return;
      }

      if (action === 'capture-selection') {
        await this.capture('selection', 'CAPTURE_SELECTION');
        return;
      }

      if (action === 'save-token') {
        await this.saveToken();
        return;
      }

      if (action === 'clear-token') {
        await this.clearToken();
      }
    });

    root.addEventListener('input', (event) => {
      if (event.target.id === 'tokenField') {
        this.state.tokenInputValue = event.target.value;
      }
    });
  }

  setState(partial) {
    this.state = { ...this.state, ...partial };
    this.render();
  }

  async refreshStatus() {
    try {
      const response = await chrome.runtime.sendMessage({ type: 'GET_STATUS' });
      this.setState({
        connected: response?.connected ?? false,
        hasToken: response?.hasToken ?? false,
        capturedThisSession: response?.capturedThisSession ?? 0
      });
    } catch (error) {
      this.setState({ connected: false });
    }
  }

  async capture(kind, messageType) {
    this.setState({ isCapturing: kind });
    try {
      const result = await chrome.runtime.sendMessage({ type: messageType });
      if (result?.success) {
        await this.refreshStatus();
        this.showMessage('success', kind === 'page' ? 'Page captured' : 'Selection captured');
      } else {
        this.showMessage('error', result?.error || 'Capture failed');
      }
    } catch (error) {
      this.showMessage('error', error.message || 'Capture failed');
    }
    this.setState({ isCapturing: null });
  }

  async saveToken() {
    const token = (this.state.tokenInputValue || '').trim();
    if (!token) return;

    this.setState({ isSavingToken: true });
    try {
      await chrome.runtime.sendMessage({ type: 'SET_TOKEN', token });
      this.setState({ tokenInputValue: '' });
      await this.refreshStatus();
      this.showMessage('success', 'Token saved');
    } catch (error) {
      this.showMessage('error', error.message || 'Failed to save token');
    }
    this.setState({ isSavingToken: false });
  }

  async clearToken() {
    try {
      await chrome.runtime.sendMessage({ type: 'SET_TOKEN', token: null });
      this.setState({ tokenInputValue: '' });
      await this.refreshStatus();
      this.showMessage('success', 'Token cleared');
    } catch (error) {
      this.showMessage('error', error.message || 'Failed to clear token');
    }
  }

  showMessage(kind, text) {
    if (this.messageTimer) window.clearTimeout(this.messageTimer);
    this.setState({ message: { kind, text } });
    this.messageTimer = window.setTimeout(() => {
      this.setState({ message: null });
    }, 3000);
  }

  statusLabel() {
    if (this.state.connected && this.state.hasToken) return 'Connected';
    if (this.state.connected) return 'Connected, token needed';
    if (this.state.hasToken) return 'Waiting for Vapor';
    return 'Not connected';
  }

  render() {
    const {
      connected,
      hasToken,
      isSettingsOpen,
      isSavingToken,
      isCapturing,
      capturedThisSession,
      message,
      tokenInputValue
    } = this.state;

    const captureCountText = capturedThisSession === 1
      ? '1 captured this session'
      : `${capturedThisSession} captured this session`;

    this.shadowRoot.innerHTML = `
      <style>
        :host {
          color-scheme: light;
          display: block;
          width: 288px;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
          color: #111827;
        }

        * { box-sizing: border-box; }

        .shell {
          padding: 12px;
          background: #f8fafc;
        }

        .card {
          background: rgba(255, 255, 255, 0.96);
          border: 1px solid #dbe4ee;
          border-radius: 14px;
          box-shadow: 0 14px 30px rgba(15, 23, 42, 0.12);
          overflow: hidden;
        }

        .view {
          padding: 14px;
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
        }

        .brand {
          display: flex;
          align-items: center;
          gap: 10px;
          min-width: 0;
        }

        .dot {
          width: 10px;
          height: 10px;
          border-radius: 999px;
          background: ${connected ? '#16a34a' : '#94a3b8'};
          box-shadow: 0 0 0 3px ${connected ? 'rgba(34, 197, 94, 0.18)' : 'rgba(148, 163, 184, 0.18)'};
          flex: none;
        }

        .title-wrap {
          display: flex;
          flex-direction: column;
          gap: 1px;
          min-width: 0;
        }

        .title {
          font-size: 14px;
          font-weight: 700;
          letter-spacing: -0.01em;
        }

        .subtitle {
          font-size: 11px;
          color: #64748b;
        }

        .icon-button {
          border: 1px solid #dbe4ee;
          background: #ffffff;
          color: #334155;
          width: 32px;
          height: 32px;
          border-radius: 10px;
          cursor: pointer;
          font-size: 15px;
        }

        .icon-button:hover,
        .capture-button:hover,
        .secondary-button:hover,
        .primary-button:hover {
          filter: brightness(0.98);
        }

        .capture-stack {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }

        .capture-button {
          width: 100%;
          border: 0;
          border-radius: 12px;
          padding: 12px 14px;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 10px;
          cursor: pointer;
          text-align: left;
          transition: transform 120ms ease;
        }

        .capture-button:disabled,
        .primary-button:disabled,
        .secondary-button:disabled,
        .icon-button:disabled {
          cursor: default;
          opacity: 0.6;
        }

        .capture-button.page {
          background: linear-gradient(135deg, #eff6ff 0%, #e0f2fe 100%);
          color: #0f172a;
          border: 1px solid #bfdbfe;
        }

        .capture-button.selection {
          background: linear-gradient(135deg, #f8fafc 0%, #eef2ff 100%);
          color: #0f172a;
          border: 1px solid #dbe4ee;
        }

        .button-copy {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        .button-title {
          font-size: 13px;
          font-weight: 600;
        }

        .button-hint {
          font-size: 11px;
          color: #64748b;
        }

        .button-icon {
          font-size: 16px;
        }

        .session-row {
          min-height: 18px;
          font-size: 11px;
          color: #64748b;
        }

        .message {
          border-radius: 10px;
          padding: 9px 10px;
          font-size: 11px;
          line-height: 1.35;
        }

        .message.success {
          background: #ecfdf5;
          color: #166534;
          border: 1px solid #bbf7d0;
        }

        .message.error {
          background: #fef2f2;
          color: #b91c1c;
          border: 1px solid #fecaca;
        }

        .settings-title {
          font-size: 13px;
          font-weight: 700;
        }

        .status-pill {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          align-self: flex-start;
          padding: 6px 9px;
          border-radius: 999px;
          background: ${connected ? '#ecfdf5' : '#f8fafc'};
          border: 1px solid ${connected ? '#bbf7d0' : '#dbe4ee'};
          color: ${connected ? '#166534' : '#475569'};
          font-size: 11px;
          font-weight: 600;
        }

        .field-group {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }

        .field-label {
          font-size: 11px;
          font-weight: 600;
          color: #475569;
        }

        .field-input {
          width: 100%;
          border: 1px solid #cbd5e1;
          border-radius: 10px;
          padding: 10px 11px;
          font-size: 12px;
          color: #0f172a;
          background: #ffffff;
          outline: none;
        }

        .field-input:focus {
          border-color: #60a5fa;
          box-shadow: 0 0 0 3px rgba(96, 165, 250, 0.2);
        }

        .token-note {
          font-size: 11px;
          color: #64748b;
          line-height: 1.4;
        }

        .button-row {
          display: flex;
          gap: 8px;
        }

        .primary-button,
        .secondary-button {
          border-radius: 10px;
          padding: 10px 12px;
          font-size: 12px;
          font-weight: 600;
          cursor: pointer;
          flex: 1;
        }

        .primary-button {
          border: 1px solid #3b82f6;
          background: #3b82f6;
          color: #ffffff;
        }

        .secondary-button {
          border: 1px solid #dbe4ee;
          background: #ffffff;
          color: #334155;
        }
      </style>

      <div class="shell">
        <div class="card">
          ${isSettingsOpen ? `
            <div class="view">
              <div class="header">
                <div class="brand">
                  <button class="icon-button" data-action="close-settings" aria-label="Back">←</button>
                  <div class="title-wrap">
                    <div class="settings-title">Settings</div>
                    <div class="subtitle">Manage browser connection</div>
                  </div>
                </div>
              </div>

              <div class="status-pill">
                <span class="dot"></span>
                <span>${this.statusLabel()}</span>
              </div>

              <div class="field-group">
                <label class="field-label" for="tokenField">Auth token</label>
                <input
                  id="tokenField"
                  class="field-input"
                  type="password"
                  autocomplete="off"
                  value="${tokenInputValue.replace(/"/g, '&quot;')}"
                  placeholder="${hasToken ? 'Token saved' : 'Paste token from Vapor Settings'}"
                />
                <div class="token-note">Capture works once Vapor is running and the browser token matches Settings.</div>
              </div>

              <div class="button-row">
                <button class="primary-button" data-action="save-token" ${isSavingToken ? 'disabled' : ''}>
                  ${isSavingToken ? 'Saving…' : 'Save'}
                </button>
                <button class="secondary-button" data-action="clear-token" ${!hasToken ? 'disabled' : ''}>Clear</button>
              </div>

              ${message ? `<div class="message ${message.kind}">${message.text}</div>` : ''}
            </div>
          ` : `
            <div class="view">
              <div class="header">
                <div class="brand">
                  <span class="dot"></span>
                  <div class="title-wrap">
                    <div class="title">Vapor</div>
                    <div class="subtitle">${this.statusLabel()}</div>
                  </div>
                </div>
                <button class="icon-button" data-action="open-settings" aria-label="Settings">⚙</button>
              </div>

              <div class="capture-stack">
                <button class="capture-button page" data-action="capture-page" ${isCapturing ? 'disabled' : ''}>
                  <span class="button-copy">
                    <span class="button-title">Capture Page</span>
                    <span class="button-hint">${navigator.platform.includes('Mac') ? '⌘⇧C' : 'Alt+Shift+C'} · Readability first</span>
                  </span>
                  <span class="button-icon">${isCapturing === 'page' ? '…' : '▣'}</span>
                </button>

                <button class="capture-button selection" data-action="capture-selection" ${isCapturing ? 'disabled' : ''}>
                  <span class="button-copy">
                    <span class="button-title">Capture Selection</span>
                    <span class="button-hint">Only the highlighted text</span>
                  </span>
                  <span class="button-icon">${isCapturing === 'selection' ? '…' : '✂'}</span>
                </button>
              </div>

              <div class="session-row">${captureCountText}</div>

              ${message ? `<div class="message ${message.kind}">${message.text}</div>` : ''}
            </div>
          `}
        </div>
      </div>
    `;
  }
}

customElements.define('vapor-popup-app', VaporPopupApp);
