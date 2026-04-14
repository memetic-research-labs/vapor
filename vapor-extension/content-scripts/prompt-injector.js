/**
 * Vapor – Prompt Injector Content Script
 *
 * Injects text into AI chat prompt inputs and optionally submits.
 * Adapts patterns from prompt-audit/extension-minimal prompt-watcher.js.
 *
 * Guard: checks window.__VAPOR_INJECTOR_LOADED__ to prevent double-injection.
 * Resolution order:
 *   1. Pinned selector from chrome.storage.local
 *   2. Platform-specific selectors from platform-config.js
 *   3. Generic heuristic (textarea, contenteditable, keyword match)
 */

(() => {
  if (window.__VAPOR_INJECTOR_LOADED__) {
    console.log('[Vapor] Injector already loaded, skipping');
    return;
  }
  window.__VAPOR_INJECTOR_LOADED__ = true;

  const DEBUG = false;
  let platformConfig = null;

  async function loadPlatformConfig() {
    try {
      const moduleUrl = chrome.runtime.getURL('config/platform-config.js');
      const module = await import(moduleUrl);
      if (module && typeof module.getPlatformConfig === 'function') {
        platformConfig = module.getPlatformConfig(window.location.hostname);
        if (platformConfig) {
          console.log('[Vapor] Loaded platform config for', window.location.hostname, '=>', platformConfig.name);
        }
      }
    } catch (err) {
      if (DEBUG) console.warn('[Vapor] Failed to load platform config:', err);
    }
  }

  /**
   * Resolve the best prompt input element on the page.
   */
  async function resolveTarget(hostname) {
    // 1. Check for a pinned selector
    try {
      const stored = await chrome.storage.local.get('pinnedTargets');
      const targets = stored?.pinnedTargets ?? {};
      const pin = targets[hostname];
      if (pin && pin.selector) {
        const el = document.querySelector(pin.selector);
        if (el) {
          console.log('[Vapor] Using pinned target:', pin.selector);
          return { element: el, platform: `${hostname} (pinned)` };
        }
        console.warn('[Vapor] Pinned target not found, falling back to auto-detect');
      }
    } catch (err) {
      // Storage access failed; continue
    }

    // 2. Platform config selectors
    if (platformConfig) {
      const selectors = platformConfig.promptSelectors || [];
      for (const sel of selectors) {
        try {
          const el = document.querySelector(sel);
          if (el && isElementVisible(el)) return { element: el, platform: platformConfig.name };
        } catch (e) { /* bad selector, skip */ }
      }
    }

    // 3. Generic heuristic
    const candidates = document.querySelectorAll(
      'textarea, input[type="text"], input:not([type]), [contenteditable="true"], [role="textbox"]'
    );
    const keywords = ['prompt', 'message', 'ask', 'chat', 'input', 'describe', 'imagine'];

    let best = null;
    let bestScore = -1;

    for (const el of candidates) {
      if (!isElementVisible(el)) continue;
      if (!(el instanceof HTMLElement)) continue;

      const rect = el.getBoundingClientRect();
      let score = 0;

      // Prefer larger inputs
      if (rect.width > 300) score += 0.3;
      if (rect.height > 40) score += 0.1;

      // Keyword match on placeholder, label, aria-label
      const text = [
        el.placeholder || '',
        getLabel(el) || '',
        el.getAttribute('aria-label') || ''
      ].join(' ').toLowerCase();

      for (const kw of keywords) {
        if (text.includes(kw)) score += 0.4;
      }

      // Proximity to viewport center
      const cx = rect.left + rect.width / 2;
      const cy = rect.top + rect.height / 2;
      const dist = Math.hypot(cx - window.innerWidth / 2, cy - window.innerHeight / 2);
      const maxDist = Math.hypot(window.innerWidth / 2, window.innerHeight / 2) || 1;
      score += (1 - Math.min(dist / maxDist, 1)) * 0.2;

      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }

    if (best) {
      const name = platformConfig ? platformConfig.name : 'Generic';
      console.log('[Vapor] Auto-detected prompt input:', best.tagName, 'score:', bestScore, 'platform:', name);
      return { element: best, platform: name };
    }

    return null;
  }

  function isElementVisible(el) {
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  function getLabel(el) {
    if (el.id) {
      const label = document.querySelector(`label[for="${CSS.escape(el.id)}"]`);
      if (label) return label.textContent;
    }
    const ancestor = el.closest('label');
    if (ancestor) return ancestor.textContent;
    return '';
  }

  /**
   * Set value on a prompt input, firing synthetic events for framework bindings.
   */
  function setValue(el, text) {
    const tag = el.tagName.toLowerCase();

    if (tag === 'textarea' || tag === 'input') {
      // Use native setter to bypass React's synthetic event system
      const descriptor = Object.getOwnPropertyDescriptor(
        tag === 'textarea'
          ? HTMLTextAreaElement.prototype
          : HTMLInputElement.prototype,
        'value'
      );
      if (descriptor && descriptor.set) {
        descriptor.set.call(el, text);
      } else {
        el.value = text;
      }
    } else if (el.contentEditable === 'true' || el.isContentEditable) {
      el.innerText = text;
    }

    // Fire synthetic events so React/Vue/Angular detect the change
    ['input', 'change', 'compositionend'].forEach(name => {
      el.dispatchEvent(new Event(name, { bubbles: true }));
    });

    // Dispatch input event on the parent form if applicable
    if (tag !== 'textarea' && tag !== 'input') {
      const form = el.closest('form');
      if (form) {
        form.dispatchEvent(new Event('input', { bubbles: true }));
      }
    }
  }

  /**
   * Simulate a submit (Enter key or button click).
   */
  function simulateSubmit(el, platformConfig) {
    const submitMode = platformConfig?.submitMode || 'enter';

    if (submitMode === 'enter') {
      el.dispatchEvent(new KeyboardEvent('keydown', {
        key: 'Enter',
        code: 'Enter',
        keyCode: 13,
        which: 13,
        bubbles: true
      }));
      el.dispatchEvent(new KeyboardEvent('keyup', {
        key: 'Enter',
        code: 'Enter',
        keyCode: 13,
        which: 13,
        bubbles: true
      }));
      return;
    }

    // Button click fallback
    const selectors = platformConfig?.submitSelectors || [];
    for (const sel of selectors) {
      try {
        const btn = document.querySelector(sel);
        if (btn && isElementVisible(btn)) {
          btn.click();
          return;
        }
      } catch (e) { /* skip */ }
    }

    // Last resort: dispatch Enter on the active element
    document.activeElement?.dispatchEvent(new KeyboardEvent('keydown', {
      key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true
    }));
  }

  /**
   * Activate the DOM picker overlay (placeholder — Phase 3).
   */
  function activatePicker() {
    console.log('[Vapor] Picker activation requested (not yet implemented — Phase 3)');
  }

  // Load config and set up message listener
  loadPlatformConfig().then(() => {
    chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
      if (!message || !message.type) return;

      if (message.type === 'SET_PROMPT') {
        (async () => {
          try {
            const target = await resolveTarget(window.location.hostname);
            if (!target) {
              sendResponse({ success: false, platform: 'unknown', error: 'No prompt input found' });
              return;
            }
            setValue(target.element, message.text);

            if (message.autoSubmit) {
              simulateSubmit(target.element, platformConfig);
            }

            sendResponse({
              success: true,
              platform: target.platform,
              selector: getSelectorForElement(target.element),
              tag: target.element.tagName.toLowerCase()
            });
          } catch (err) {
            sendResponse({ success: false, error: err.message || String(err) });
          }
        })();
        return true;
      }

      if (message.type === 'ACTIVATE_PICKER') {
        activatePicker();
        sendResponse({ success: false, error: 'Not yet implemented' });
        return false;
      }
    });
  });

  function getSelectorForElement(el) {
    if (el.id) {
      const candidate = `#${CSS.escape(el.id)}`;
      if (document.querySelectorAll(candidate).length === 1) return candidate;
    }
    const attrs = ['data-testid', 'data-id', 'aria-label', 'name', 'placeholder'];
    for (const attr of attrs) {
      const val = el.getAttribute(attr);
      if (val) {
        const candidate = `${el.tagName.toLowerCase()}[${attr}="${CSS.escape(val)}"]`;
        if (document.querySelectorAll(candidate).length === 1) return candidate;
      }
    }
    return el.tagName.toLowerCase();
  }
})();
