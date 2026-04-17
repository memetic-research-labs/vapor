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
  const platformConfigPromise = loadPlatformConfig();

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

  const SVG_ARROW_PATHS = [
    'M12 4l-1.41 1.41L16.17 11H4v2h12.17l-5.58 5.59L12 20l8-8z',
    'M4 12l1.41 1.41L11 7.83V20h2V7.83l5.58 5.59L20 12l-8-8z',
    'M12 16l-6-6h12z',
    'M7 14l5-5 5 5z',
    'M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6z',
    'M12 8v8m0 0l3-3m-3 3l-3-3',
  ];

  const SVG_PAPER_PLANE_PATHS = [
    'M2 21l21-9L2 3v7l15 2-15 2z',
    'M22 2L11 13M22 2l-7 20-4-9-9-4z',
  ];

  function hasSubmitIcon(button) {
    const svg = button.querySelector('svg');
    if (!svg) return false;
    const paths = svg.querySelectorAll('path');
    for (const path of paths) {
      const d = (path.getAttribute('d') || '').trim();
      if (d && (SVG_ARROW_PATHS.some(p => d === p) || SVG_PAPER_PLANE_PATHS.some(p => d === p))) {
        return true;
      }
      if (d && (d.includes('M12') && (d.includes('L12') || d.includes('l-') || d.includes('20l'))) && d.includes('8')) {
        return true;
      }
      if (d && d.includes('21l') && d.includes('2 3v7')) {
        return true;
      }
    }
    return false;
  }

  function findContainer(el) {
    const form = el.closest('form');
    if (form) return form;
    const roleForm = el.closest('[role="form"]');
    if (roleForm) return roleForm;
    const parent = el.parentElement;
    if (parent) return parent;
    return document.body;
  }

  function distanceBetween(a, b) {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    const ax = ar.left + ar.width / 2;
    const ay = ar.top + ar.height / 2;
    const bx = br.left + br.width / 2;
    const by = br.top + br.height / 2;
    return Math.hypot(ax - bx, ay - by);
  }

  function findSubmitButton(inputEl, container) {
    const candidates = [];

    const typeSubmit = container.querySelectorAll('button[type="submit"], input[type="submit"]');
    for (const btn of typeSubmit) {
      if (isElementVisible(btn)) {
        candidates.push({ element: btn, score: 100, reason: 'type=submit' });
      }
    }

    const ariaPatterns = /send|submit|go/i;
    const ariaButtons = container.querySelectorAll('button[aria-label], button[aria-labelledby]');
    for (const btn of ariaButtons) {
      if (!isElementVisible(btn)) continue;
      const label = btn.getAttribute('aria-label') || '';
      const labelledBy = btn.getAttribute('aria-labelledby') || '';
      if (ariaPatterns.test(label) || ariaPatterns.test(labelledBy)) {
        candidates.push({ element: btn, score: 95, reason: 'aria-label' });
      }
    }

    const testidButtons = container.querySelectorAll('button[data-testid]');
    for (const btn of testidButtons) {
      if (!isElementVisible(btn)) continue;
      const testid = btn.getAttribute('data-testid') || '';
      if (/send|submit/i.test(testid)) {
        candidates.push({ element: btn, score: 90, reason: 'data-testid' });
      }
    }

    const allButtons = container.querySelectorAll('button:not([disabled]), [role="button"]:not([disabled])');
    for (const btn of allButtons) {
      if (!isElementVisible(btn)) continue;
      if (candidates.some(c => c.element === btn)) continue;
      if (hasSubmitIcon(btn)) {
        candidates.push({ element: btn, score: 85, reason: 'svg-icon' });
      }
    }

    if (candidates.length === 0) return null;
    if (candidates.length === 1) return candidates[0];

    candidates.sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return distanceBetween(inputEl, a.element) - distanceBetween(inputEl, b.element);
    });

    return candidates[0];
  }

  function detectSubmitMechanism(inputEl) {
    if (platformConfig?.submitSelectors?.length) {
      for (const sel of platformConfig.submitSelectors) {
        try {
          const btn = document.querySelector(sel);
          if (btn && isElementVisible(btn)) {
            return { method: 'config_override', element: btn, confidence: 'high' };
          }
        } catch (e) { /* skip */ }
      }
      if (platformConfig.submitMode === 'enter') {
        return { method: 'config_override', element: null, confidence: 'high' };
      }
    }

    const container = findContainer(inputEl);

    const buttonResult = findSubmitButton(inputEl, container);
    if (buttonResult) {
      return {
        method: 'button',
        element: buttonResult.element,
        confidence: buttonResult.score >= 95 ? 'high' : 'medium',
        reason: buttonResult.reason
      };
    }

    const form = inputEl.closest('form');
    if (form) {
      return { method: 'form', element: form, confidence: 'medium' };
    }

    return { method: 'enter', element: null, confidence: 'low' };
  }

  function executeSubmit(mechanism, inputEl) {
    if (!mechanism) return false;

    switch (mechanism.method) {
      case 'config_override':
      case 'button':
        if (mechanism.element) {
          mechanism.element.click();
          return true;
        }
        break;
      case 'form':
        if (mechanism.element && typeof mechanism.element.requestSubmit === 'function') {
          mechanism.element.requestSubmit();
          return true;
        }
        break;
      case 'enter':
        break;
    }

    const el = inputEl || document.activeElement || document.body;
    if (inputEl && document.activeElement !== inputEl) {
      try { inputEl.focus(); } catch (_) {}
    }
    el.dispatchEvent(new KeyboardEvent('keydown', {
      key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true
    }));
    el.dispatchEvent(new KeyboardEvent('keypress', {
      key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true
    }));
    el.dispatchEvent(new KeyboardEvent('keyup', {
      key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true
    }));
    return true;
  }

  /**
   * Activate the DOM picker overlay (placeholder — Phase 3).
   */
  function activatePicker() {
    console.log('[Vapor] Picker activation requested (not yet implemented — Phase 3)');
  }

  // Register the listener immediately so fresh injections can receive messages.
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || !message.type) return;

    if (message.type === 'SET_PROMPT') {
      (async () => {
        try {
          await platformConfigPromise;
          const target = await resolveTarget(window.location.hostname);
          if (!target) {
            sendResponse({ success: false, platform: 'unknown', error: 'No prompt input found' });
            return;
          }
          setValue(target.element, message.text);

          const mechanism = detectSubmitMechanism(target.element);
          let didSubmit = false;

          if (message.autoSubmit) {
            didSubmit = executeSubmit(mechanism, target.element);
          }

          sendResponse({
            success: true,
            platform: target.platform,
            selector: getSelectorForElement(target.element),
            tag: target.element.tagName.toLowerCase(),
            submitMethod: mechanism.method,
            submitConfidence: mechanism.confidence,
            autoSubmitted: didSubmit
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
