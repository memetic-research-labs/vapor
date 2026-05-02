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

  let DEBUG = false;
  let platformConfig = null;
  const platformConfigPromise = loadPlatformConfig();

  chrome.storage.local.get(['vaporVerboseLogging'], (items) => {
    DEBUG = !!items.vaporVerboseLogging;
  });

  function log(level, msg) {
    const prefix = '[Vapor:injector]';
    if (level === 'error') console.error(`${prefix} ${msg}`);
    else if (level === 'warn') console.warn(`${prefix} ${msg}`);
    else if (DEBUG) console.log(`${prefix} ${msg}`);
    try { chrome.runtime.sendMessage({ type: 'INJECTION_LOG', level, message: msg }); } catch (_) {}
  }

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

  function decodeBase64Image(imgData) {
    const binary = atob(imgData);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  function findFileInput() {
    const config = platformConfig || {};
    if (config.imageUploadSelector) {
      const explicit = document.querySelector(config.imageUploadSelector);
      if (explicit) {
        log('ok', `Found file input via config selector: ${config.imageUploadSelector}`);
        return explicit;
      }
    }
    const imageInputs = document.querySelectorAll('input[type="file"][accept*="image"], input[type="file"]');
    for (const input of imageInputs) {
      if (isElementVisible(input)) {
        log('ok', `Found visible file input: ${input.accept || '*'} (accept)`);
        return input;
      }
    }
    for (const input of imageInputs) {
      log('warn', `Found hidden file input: ${input.accept || '*'}`);
      return input;
    }
    return null;
  }

  function findDropTarget() {
    const config = platformConfig || {};
    if (config.imageDropTarget) {
      const explicit = document.querySelector(config.imageDropTarget);
      if (explicit) {
        log('ok', `Found drop target via config selector: ${config.imageDropTarget}`);
        return explicit;
      }
    }
    const dropZones = document.querySelectorAll(
      '[data-dropzone], [data-drop-zone], [data-droppable], [class*="dropzone"], [class*="drop-zone"]'
    );
    for (const zone of dropZones) {
      if (isElementVisible(zone)) {
        log('ok', `Found drop zone: ${zone.className || zone.tagName}`);
        return zone;
      }
    }
    return null;
  }

  function countUploadPreviews(container) {
    return container.querySelectorAll(
      'img, canvas, [data-testid*="image"], [class*="attachment"], [class*="upload-preview"], [class*="preview-img"], [role="img"]'
    ).length;
  }

  async function injectViaDragDrop(targetEl, file) {
    const container = targetEl.closest('form, [role="form"], [class*="prompt"], [class*="composer"]') || targetEl.parentElement || document.body;
    const before = countUploadPreviews(container);

    const dt = new DataTransfer();
    dt.items.add(file);
    dt.setData('text/uri-list', '');

    const dragEnter = new DragEvent('dragenter', { bubbles: true, cancelable: true, dataTransfer: dt });
    const dragOver = new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: dt });
    const drop = new DragEvent('drop', {
      bubbles: true,
      cancelable: true,
      dataTransfer: dt
    });

    targetEl.dispatchEvent(dragEnter);
    targetEl.dispatchEvent(dragOver);
    targetEl.dispatchEvent(drop);

    log('ok', `Drag-drop dispatched to ${targetEl.tagName}#${targetEl.id || ''}`);

    await new Promise(r => setTimeout(r, 500));

    const after = countUploadPreviews(container);
    const worked = after > before;
    log(worked ? 'ok' : 'warn', `Drag-drop ${worked ? 'detected' : 'not detected'} (previews: ${before} → ${after})`);
    return worked;
  }

  async function injectViaFileInput(fileInput, file) {
    return new Promise((resolve) => {
      try {
        const dt = new DataTransfer();
        dt.items.add(file);
        fileInput.files = dt.files;
        fileInput.dispatchEvent(new Event('change', { bubbles: true }));
        fileInput.dispatchEvent(new Event('input', { bubbles: true }));
        log('ok', `File input set with ${(file.size / 1024).toFixed(0)}KB, events dispatched`);
      } catch (err) {
        log('error', `File input injection failed: ${err.message}`);
      }
      setTimeout(resolve, 300);
    });
  }

  async function injectImages(images, targetEl) {
    if (!images || images.length === 0) {
      log('warn', 'injectImages called with no images');
      return;
    }

    log('ok', `injectImages: ${images.length} image(s) to inject`);

    const config = platformConfig || {};
    const delay = config.imageInjectionDelay || 300;

    for (let i = 0; i < images.length; i++) {
      const img = images[i];
      log('ok', `Processing image ${i + 1}/${images.length}: ${img.mimeType}, ~${(img.data.length * 0.75 / 1024).toFixed(0)}KB (base64)`);

      try {
        const bytes = decodeBase64Image(img.data);
        const blob = new Blob([bytes], { type: img.mimeType });
        const filename = `screenshot_${i + 1}.webp`;
        const file = new File([blob], filename, { type: img.mimeType });

        const dropTarget = findDropTarget();
        let dragDropWorked = false;
        if (dropTarget) {
          log('ok', `Attempting drag-drop on ${dropTarget.tagName}#${dropTarget.id || ''}`);
          dragDropWorked = await injectViaDragDrop(dropTarget, file);
        } else {
          log('warn', 'No drop target found');
        }

        if (!dragDropWorked) {
          const fileInput = findFileInput();
          if (fileInput) {
            log('ok', `Drag-drop failed, attempting file input injection on ${fileInput.accept || '*'}`);
            await injectViaFileInput(fileInput, file);
          } else {
            log('warn', 'No file input found — image may not be attached');
          }
        } else {
          log('ok', `Drag-drop succeeded, skipping file input fallback`);
        }

        await new Promise(r => setTimeout(r, delay));
      } catch (err) {
        log('error', `Image ${i + 1} injection failed: ${err.message}`);
      }
    }
  }

  // Register the listener immediately so fresh injections can receive messages.
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || !message.type) return;

    if (message.type === 'SET_PROMPT') {
      (async () => {
        try {
          await platformConfigPromise;
          log('ok', `SET_PROMPT received: ${message.text?.length || 0} chars, ${message.images?.length || 0} images, autoSubmit=${message.autoSubmit}`);

          const target = await resolveTarget(window.location.hostname);
          if (!target) {
            log('error', 'No prompt input found on page');
            sendResponse({ success: false, platform: 'unknown', error: 'No prompt input found' });
            return;
          }

          log('ok', `Target resolved: ${target.element.tagName}#${target.element.id || ''} (${target.platform})`);

          if (message.images && message.images.length > 0) {
            log('ok', `${message.images.length} image(s) available in sidebar — user will drag to attach`);
          }

          setValue(target.element, message.text);
          log('ok', 'Text injected successfully');

          const mechanism = detectSubmitMechanism(target.element);
          let didSubmit = false;

          if (message.autoSubmit) {
            didSubmit = executeSubmit(mechanism, target.element);
            log('ok', `Auto-submit: ${didSubmit ? 'sent' : 'failed'} (${mechanism.method})`);
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

          try {
            chrome.runtime.sendMessage({
              type: 'INJECTION_RESULT',
              success: true,
              platform: target.platform,
              autoSubmitted: didSubmit
            });
          } catch (_) {}
        } catch (err) {
          log('error', `SET_PROMPT failed: ${err.message}`);
          sendResponse({ success: false, error: err.message || String(err) });
          try {
            chrome.runtime.sendMessage({
              type: 'INJECTION_RESULT',
              success: false,
              platform: 'unknown',
              error: err.message || String(err)
            });
          } catch (_) {}
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
