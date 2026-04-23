/**
 * Vapor – Page Inspector
 * Content Script
 *
 * Discovers data sources on the current page:
 * - Structured JSON (JSON-LD, embedded script blobs)
 * - HTML tables
 * - Page metadata and content summary
 * - XHR/fetch network traffic (after injection)
 */

(function() {
  'use strict';

  if (window.__VAPOR_INSPECTOR_LOADED__) return;
  window.__VAPOR_INSPECTOR_LOADED__ = true;

  const DEBUG = false;
  const MAX_XHR_ENTRIES = 200;

  let capturedXHRs = [];
  let xhrIdCounter = 0;

  function log(...args) {
    if (DEBUG) console.log('[Vapor Inspector]', ...args);
  }

  function shortId() {
    return 'src-' + (++xhrIdCounter);
  }

  function formatBytes(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  // --- Discovery: Structured JSON ---

  function discoverStructuredJSON() {
    const sources = [];

    // JSON-LD blocks
    const ldBlocks = document.querySelectorAll('script[type="application/ld+json"]');
    ldBlocks.forEach((el, idx) => {
      try {
        const data = JSON.parse(el.textContent);
        const isArray = Array.isArray(data);
        const topLevel = isArray ? data : [data];
        const types = topLevel
          .map(item => item['@type'] || item.type || '')
          .filter(Boolean)
          .join(', ');

        sources.push({
          id: shortId(),
          sourceKind: 'structuredJSON',
          label: types ? `JSON-LD: ${types}` : `JSON-LD block ${idx + 1}`,
          detail: isArray ? `${data.length} items` : (types || 'Single object'),
          recordEstimate: isArray ? data.length : 1,
          sizeHint: formatBytes(new Blob([el.textContent]).size),
          _element: el,
          _data: data
        });
      } catch (e) {
        log('Failed to parse JSON-LD block', idx, e);
      }
    });

    // Common embedded JSON blobs
    const jsonBlobSelectors = [
      'script#__NEXT_DATA__',
      'script#__NUXT__',
      'script[id^="__APP_DATA"]',
      'script[data-testid="NEXT_DATA"]'
    ];

    jsonBlobSelectors.forEach(selector => {
      const el = document.querySelector(selector);
      if (!el) return;
      try {
        const data = JSON.parse(el.textContent);
        const keys = Object.keys(data).slice(0, 5).join(', ');
        const id = el.id || selector;
        sources.push({
          id: shortId(),
          sourceKind: 'structuredJSON',
          label: `Embedded: ${id}`,
          detail: keys ? `Keys: ${keys}` : 'Object',
          recordEstimate: null,
          sizeHint: formatBytes(new Blob([el.textContent]).size),
          _element: el,
          _data: data
        });
      } catch (e) {
        log('Failed to parse JSON blob', selector, e);
      }
    });

    // Other script[type="application/json"] blocks
    const appJsonBlocks = document.querySelectorAll('script[type="application/json"]');
    appJsonBlocks.forEach((el, idx) => {
      if (ldBlocks.length > 0 && [...ldBlocks].includes(el)) return;
      if (jsonBlobSelectors.some(s => document.querySelector(s) === el)) return;
      try {
        const data = JSON.parse(el.textContent);
        const isArray = Array.isArray(data);
        const id = el.id || el.getAttribute('data-attribute') || `block-${idx + 1}`;
        sources.push({
          id: shortId(),
          sourceKind: 'structuredJSON',
          label: `JSON: ${id}`,
          detail: isArray ? `${data.length} items` : `${Object.keys(data).length} keys`,
          recordEstimate: isArray ? data.length : null,
          sizeHint: formatBytes(new Blob([el.textContent]).size),
          _element: el,
          _data: data
        });
      } catch (e) {}
    });

    return sources;
  }

  // --- Discovery: Tables ---

  function discoverTables() {
    const sources = [];
    const tables = document.querySelectorAll('table');

    tables.forEach((table, idx) => {
      // Skip tiny/layout tables
      const rows = table.querySelectorAll('tr');
      if (rows.length < 2) return;

      const headerCells = table.querySelectorAll('thead th, tr:first-child th');
      const hasHeaders = headerCells.length > 0;
      const bodyRows = table.querySelectorAll('tbody tr');
      const rowCount = bodyRows.length > 0 ? bodyRows.length : rows.length - (hasHeaders ? 1 : 0);
      const colCount = headerCells.length > 0 ? headerCells.length : (rows[1]?.children?.length || 0);

      // Skip if looks like a layout table (no headers, very small)
      if (!hasHeaders && rowCount < 3 && colCount < 3) return;

      const headerText = hasHeaders
        ? [...headerCells].slice(0, 4).map(c => c.textContent.trim()).filter(Boolean).join(', ')
        : '';

      const caption = table.querySelector('caption')?.textContent?.trim();

      let label = caption || (headerText ? `Table: ${headerText}` : `Table ${idx + 1}`);
      if (label.length > 60) label = label.substring(0, 57) + '...';

      sources.push({
        id: shortId(),
        sourceKind: 'table',
        label: label,
        detail: `${rowCount} rows × ${colCount} cols`,
        recordEstimate: rowCount,
        sizeHint: null,
        _element: table
      });
    });

    return sources;
  }

  // --- Discovery: DOM Summary ---

  function discoverDOMSummary() {
    const title = document.title || '';
    const metaDesc = document.querySelector('meta[name="description"]')?.content || '';
    const bodyText = document.body?.innerText || '';
    const wordCount = bodyText.split(/\s+/).filter(Boolean).length;
    const links = document.querySelectorAll('a[href]').length;
    const images = document.querySelectorAll('img').length;
    const headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6').length;

    let detail = `${wordCount} words`;
    if (links > 0) detail += `, ${links} links`;
    if (images > 0) detail += `, ${images} images`;
    if (headings > 0) detail += `, ${headings} headings`;

    return {
      id: shortId(),
      sourceKind: 'domSummary',
      label: title || document.location.hostname,
      detail: detail,
      recordEstimate: null,
      sizeHint: formatBytes(new Blob([bodyText]).size)
    };
  }

  // --- Network Observation ---

  function startNetworkObservation() {
    capturedXHRs = [];

    // Hook fetch
    const originalFetch = window.fetch;
    window.fetch = function(...args) {
      const [input, init] = args;
      const url = typeof input === 'string' ? input : (input instanceof Request ? input.url : String(input));
      const method = init?.method || (input instanceof Request ? input.method : 'GET');

      return originalFetch.apply(this, args).then(async response => {
        const entry = buildNetworkEntry('fetch', method, url, response);
        // Try to clone and read body for JSON responses
        if (response.ok && (response.headers.get('content-type') || '').includes('json')) {
          try {
            const clone = response.clone();
            const text = await clone.text();
            entry._responseBody = text;
            entry._isJSON = true;
            try { entry._parsedJSON = JSON.parse(text); } catch {}
          } catch {}
        }
        capturedXHRs.push(entry);
        if (capturedXHRs.length > MAX_XHR_ENTRIES) capturedXHRs.shift();
        return response;
      }).catch(err => {
        capturedXHRs.push(buildNetworkEntry('fetch', method, url, null, err.message));
        if (capturedXHRs.length > MAX_XHR_ENTRIES) capturedXHRs.shift();
        throw err;
      });
    };

    // Hook XMLHttpRequest
    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
      this.__vaporMethod = method;
      this.__vaporURL = url;
      return originalOpen.call(this, method, url, ...rest);
    };

    XMLHttpRequest.prototype.send = function(...args) {
      this.addEventListener('load', function() {
        const entry = buildNetworkEntry('xhr', this.__vaporMethod, this.__vaporURL, {
          status: this.status,
          statusText: this.statusText,
          contentType: this.getResponseHeader('content-type'),
          contentLength: parseInt(this.getResponseHeader('content-length')) || null
        });
        // Try to read response body
        if (this.responseText) {
          entry._responseBody = this.responseText;
          const ct = this.getResponseHeader('content-type') || '';
          if (ct.includes('json')) {
            entry._isJSON = true;
            try { entry._parsedJSON = JSON.parse(this.responseText); } catch {}
          }
        }
        capturedXHRs.push(entry);
        if (capturedXHRs.length > MAX_XHR_ENTRIES) capturedXHRs.shift();
      });

      this.addEventListener('error', function() {
        const entry = buildNetworkEntry('xhr', this.__vaporMethod, this.__vaporURL, null, 'Network error');
        capturedXHRs.push(entry);
        if (capturedXHRs.length > MAX_XHR_ENTRIES) capturedXHRs.shift();
      });

      return originalSend.apply(this, args);
    };
  }

  function buildNetworkEntry(type, method, url, response, error) {
    const urlObj = (() => {
      try { return new URL(url, document.baseURI); } catch { return null; }
    })();

    return {
      id: shortId(),
      type: type,
      method: method || 'GET',
      url: urlObj?.href || url,
      path: urlObj?.pathname || url,
      host: urlObj?.host || '',
      status: response?.status || null,
      contentType: response?.contentType || response?.headers?.get?.('content-type') || null,
      contentLength: response?.contentLength || null,
      error: error || null,
      timestamp: Date.now(),
      _responseBody: null,
      _isJSON: false,
      _parsedJSON: null
    };
  }

  function discoverXHRSources() {
    if (capturedXHRs.length === 0) return [];

    // Group by unique endpoint pattern (path)
    const groups = new Map();
    for (const entry of capturedXHRs) {
      if (!entry.path || entry.path.startsWith('blob:')) continue;
      const key = entry.method + ' ' + entry.path;
      if (!groups.has(key)) {
        groups.set(key, { entry, count: 0 });
      }
      groups.get(key).count++;
    }

    return [...groups.values()].map(({ entry, count }) => {
      const statusHint = entry.status ? `${entry.status}` : 'pending';
      const sizeHint = entry.contentLength ? formatBytes(entry.contentLength) : null;
      const isJSON = entry._isJSON;
      const bodyHint = isJSON ? 'JSON' : (entry.contentType ? entry.contentType.split(';')[0] : '');
      const countHint = count > 1 ? ` (${count} calls)` : '';

      let detail = `${entry.method} ${statusHint}`;
      if (bodyHint) detail += ` · ${bodyHint}`;
      if (sizeHint) detail += ` · ${sizeHint}`;
      detail += countHint;

      let recordEstimate = null;
      if (isJSON && entry._parsedJSON) {
        if (Array.isArray(entry._parsedJSON)) recordEstimate = entry._parsedJSON.length;
      }

      return {
        id: entry.id,
        sourceKind: 'xhrFeed',
        label: entry.path,
        detail: detail,
        recordEstimate: recordEstimate,
        sizeHint: sizeHint,
        _entry: entry
      };
    });
  }

  // --- Preview ---

  function previewSource(sourceId) {
    // Check DOM sources
    const allDOMSources = [..._discoveredDOMSources];
    const domSource = allDOMSources.find(s => s.id === sourceId);
    if (domSource) return previewDOMSource(domSource);

    // Check XHR sources
    const xhrSource = capturedXHRs.find(e => e.id === sourceId);
    if (xhrSource) return previewXHREntry(xhrSource);

    return { error: 'Source not found' };
  }

  function previewDOMSource(source) {
    switch (source.sourceKind) {
      case 'structuredJSON': {
        const data = source._data;
        if (data === undefined) return { error: 'Data not available' };
        const jsonStr = JSON.stringify(data, null, 2);
        return {
          sourceId: source.id,
          content: jsonStr,
          mimeType: 'application/json',
          truncated: false,
          sizeBytes: new Blob([jsonStr]).size
        };
      }
      case 'table': {
        const table = source._element;
        if (!table) return { error: 'Element not available' };
        return previewTable(table, source.id);
      }
      case 'domSummary': {
        const title = document.title || '';
        const metaDesc = document.querySelector('meta[name="description"]')?.content || '';
        const headings = [...document.querySelectorAll('h1, h2, h3')].map(h => `${h.tagName}: ${h.textContent.trim()}`).join('\n');
        const bodyText = document.body?.innerText || '';
        const text = [title, metaDesc, headings ? '\n--- Headings ---\n' + headings : '', '\n--- Body ---\n', bodyText].filter(Boolean).join('\n\n');
        return {
          sourceId: source.id,
          content: text,
          mimeType: 'text/plain',
          truncated: false,
          sizeBytes: new Blob([bodyText]).size
        };
      }
      default:
        return { error: 'Unknown source kind' };
    }
  }

  function previewTable(table, sourceId) {
    const rows = table.querySelectorAll('tr');
    const lines = [];

    for (let i = 0; i < rows.length; i++) {
      const cells = rows[i].querySelectorAll('th, td');
      const vals = [...cells].map(c => c.textContent.trim().replace(/\s+/g, ' '));
      lines.push(vals.join('\t'));
    }

    const content = lines.join('\n');

    return {
      sourceId: sourceId,
      content: content,
      mimeType: 'text/tab-separated-values',
      truncated: false,
      sizeBytes: new Blob([content]).size
    };
  }

  function previewXHREntry(entry) {
    if (entry.error) {
      return {
        sourceId: entry.id,
        content: `Error: ${entry.error}\n${entry.method} ${entry.url}`,
        mimeType: 'text/plain',
        truncated: false,
        sizeBytes: 0
      };
    }

    if (entry._responseBody) {
      const body = entry._responseBody;
      let content = `${entry.method} ${entry.url}\nStatus: ${entry.status || 'unknown'}\nContent-Type: ${entry.contentType || 'unknown'}\n\n`;
      content += body;

      return {
        sourceId: entry.id,
        content: content,
        mimeType: entry._isJSON ? 'application/json' : (entry.contentType || 'text/plain'),
        truncated: false,
        sizeBytes: new Blob([body]).size
      };
    }

    return {
      sourceId: entry.id,
      content: `${entry.method} ${entry.url}\nStatus: ${entry.status || 'unknown'}\nContent-Type: ${entry.contentType || 'unknown'}\n\n(No response body captured)`,
      mimeType: 'text/plain',
      truncated: false,
      sizeBytes: 0
    };
  }

  // --- Main Discovery ---

  let _discoveredDOMSources = [];

  function discoverAll() {
    _discoveredDOMSources = [
      discoverDOMSummary(),
      ...discoverStructuredJSON(),
      ...discoverTables()
    ].filter(Boolean);

    const xhrSources = discoverXHRSources();

    const allSources = [..._discoveredDOMSources, ...xhrSources];
    log('Discovered', allSources.length, 'sources');

    return allSources.map(s => ({
      id: s.id,
      sourceKind: s.sourceKind,
      label: s.label,
      detail: s.detail,
      recordEstimate: s.recordEstimate,
      sizeHint: s.sizeHint
    }));
  }

  function refreshXHRSources() {
    return discoverXHRSources().map(s => ({
      id: s.id,
      sourceKind: s.sourceKind,
      label: s.label,
      detail: s.detail,
      recordEstimate: s.recordEstimate,
      sizeHint: s.sizeHint
    }));
  }

  // --- Message Handling ---

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (!message || !message.type) return;

    if (message.type === 'INSPECT_PAGE') {
      try {
        const sources = discoverAll();
        sendResponse({ success: true, sources });
      } catch (err) {
        sendResponse({ success: false, error: err.message });
      }
      return true;
    }

    if (message.type === 'PREVIEW_SOURCE') {
      try {
        const preview = previewSource(message.sourceId);
        sendResponse({ success: true, preview });
      } catch (err) {
        sendResponse({ success: false, error: err.message });
      }
      return true;
    }

    if (message.type === 'REFRESH_XHR_SOURCES') {
      try {
        const sources = refreshXHRSources();
        sendResponse({ success: true, sources });
      } catch (err) {
        sendResponse({ success: false, error: err.message });
      }
      return true;
    }
  });

  // Start network hooks immediately
  startNetworkObservation();
  log('Page inspector loaded');
})();
