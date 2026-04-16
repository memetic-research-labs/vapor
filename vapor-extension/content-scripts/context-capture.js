/**
 * Vapor – Context Capture
 * Content script for capturing text, articles, and images from web pages.
 */

const VAPOR_CAPTURE = 'VAPOR_CONTEXT_CAPTURE';

if (window.__VAPOR_CAPTURE_LOADED__) {
  console.log('[Vapor] Context capture already loaded, skipping');
} else {
  window.__VAPOR_CAPTURE_LOADED__ = true;

function extractMetadata() {
  const meta = {};

  const getMeta = (selectors) => {
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el) {
        const val = (el.getAttribute('content') || el.textContent || '').trim();
        if (val) return val;
      }
    }
    return null;
  };

  meta.author = getMeta([
    'meta[name="author"]',
    'meta[property="og:article:author"]',
    'meta[property="article:author"]',
    'meta[name="parsely-author"]',
    '[rel="author"]'
  ]);

  meta.siteName = getMeta([
    'meta[property="og:site_name"]',
    'meta[name="application-name"]'
  ]);

  const publishedDate = getMeta([
    'meta[property="article:published_time"]',
    'meta[name="date"]',
    'meta[name="DC.date.issued"]',
    'meta[property="og:article:published_time"]',
    'time[datetime]'
  ]);
  if (publishedDate) {
    const timeEl = document.querySelector('time[datetime]');
    meta.publishedDate = timeEl ? timeEl.getAttribute('datetime') : publishedDate;
  }

  try {
    const scripts = document.querySelectorAll('script[type="application/ld+json"]');
    for (const script of scripts) {
      const data = JSON.parse(script.textContent);
      const items = Array.isArray(data) ? data : [data];
      for (const item of items) {
        if (item['@type'] === 'Article' || item['@type'] === 'NewsArticle' || item['@type'] === 'BlogPosting') {
          if (!meta.author && item.author) {
            if (typeof item.author === 'string') {
              meta.author = item.author;
            } else if (Array.isArray(item.author)) {
              meta.author = item.author.map(a => typeof a === 'string' ? a : a.name).filter(Boolean).join(', ');
            } else if (item.author.name) {
              meta.author = item.author.name;
            }
          }
          if (!meta.publishedDate && item.datePublished) {
            meta.publishedDate = item.datePublished;
          }
          if (!meta.siteName && item.publisher && item.publisher.name) {
            meta.siteName = item.publisher.name;
          }
        }
      }
    }
  } catch (e) {
    // JSON-LD parse error, ignore
  }

  return meta;
}

function generateJobId() {
  return 'ctx-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
}

function htmlToCleanText(html) {
  const div = document.createElement('div');
  div.innerHTML = html;
  // Remove common noise elements
  const noiseSelectors = [
    'nav', 'header:not(article header)', 'footer:not(article footer)',
    '[role="navigation"]', '[role="banner"]', '[role="contentinfo"]',
    '.sidebar', '.side-bar', '#sidebar', '#side-bar',
    '.nav', '.menu', '.ad', '.advertisement',
    '.newsletter', '.subscribe', '.share', '.social',
    '.related', '.recommended', '.trending',
    '[aria-hidden="true"]'
  ];
  for (const sel of noiseSelectors) {
    for (const el of div.querySelectorAll(sel)) {
      el.remove();
    }
  }
  // Collapse whitespace
  let text = div.textContent || div.innerText || '';
  text = text.replace(/\s+/g, ' ').trim();
  // Remove excessive blank lines (more than 2 consecutive)
  text = text.replace(/\n\s*\n\s*\n/g, '\n\n');
  return text;
}

function tryReadability() {
  if (typeof Readability === 'undefined') return null;

  try {
    const clone = document.cloneNode(true);
    const reader = new Readability(clone);
    const article = reader.parse();

    if (!article || !article.content || !article.content.trim()) return null;

    const text = htmlToCleanText(article.content);
    if (!text || text.length < 100) return null;

    return {
      title: article.title || document.title,
      textContent: text,
      byline: article.byline || null
    };
  } catch (e) {
    console.error('[Vapor] Readability parse error:', e);
    return null;
  }
}

function buildPayload(kind, title, textContent, metadata, byline) {
  return {
    type: 'CONTEXT_CAPTURE',
    kind: kind,
    jobId: generateJobId(),
    url: window.location.href,
    title: title,
    textContent: textContent,
    author: byline || metadata.author || null,
    publishedDate: metadata.publishedDate || null,
    siteName: metadata.siteName || null,
    capturedAt: new Date().toISOString()
  };
}

async function capturePage() {
  const metadata = extractMetadata();

  const article = tryReadability();
  if (article) {
    console.log('[Vapor] Readability extracted article:', article.title);
    return {
      success: true,
      payload: buildPayload('articleText', article.title, article.textContent, metadata, article.byline)
    };
  }

  console.log('[Vapor] Readability failed, falling back to page text');
  const text = document.body ? document.body.innerText.trim() : '';
  if (!text) return { success: false, error: 'Page has no text content' };

  return {
    success: true,
    payload: buildPayload('pageSnapshot', document.title, text, metadata, null)
  };
}

async function captureSelection() {
  const selection = window.getSelection();
  const text = selection ? selection.toString().trim() : '';
  if (!text) return { success: false, error: 'No text selected' };

  const metadata = extractMetadata();

  return {
    success: true,
    payload: buildPayload('selectedText', document.title, text, metadata, null)
  };
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || !message.type) return false;

  if (message.type === 'CAPTURE_SELECTION') {
    captureSelection().then(sendResponse);
    return true;
  }

  if (message.type === 'CAPTURE_PAGE') {
    capturePage().then(sendResponse);
    return true;
  }

  // Legacy: CAPTURE_ARTICLE and CAPTURE_PAGE_SNAPSHOT still supported
  if (message.type === 'CAPTURE_ARTICLE') {
    const metadata = extractMetadata();
    const article = tryReadability();
    if (article) {
      sendResponse({
        success: true,
        payload: buildPayload('articleText', article.title, article.textContent, metadata, article.byline)
      });
    } else {
      sendResponse({ success: false, error: 'Could not extract article content. Try "Capture Page" instead.' });
    }
    return true;
  }

  if (message.type === 'CAPTURE_PAGE_SNAPSHOT') {
    capturePage().then(sendResponse);
    return true;
  }

  return false;
});

} // end double-injection guard
