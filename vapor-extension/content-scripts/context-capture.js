/**
 * Vapor – Context Capture
 * Content script for capturing text, articles, and images from web pages.
 */

const VAPOR_CAPTURE = 'VAPOR_CONTEXT_CAPTURE';

function generateJobId() {
  return 'ctx-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
}

async function captureSelection() {
  const selection = window.getSelection();
  const text = selection ? selection.toString().trim() : '';
  if (!text) return { success: false, error: 'No text selected' };

  return {
    success: true,
    payload: {
      type: 'CONTEXT_CAPTURE',
      kind: 'selectedText',
      jobId: generateJobId(),
      url: window.location.href,
      title: document.title,
      textContent: text,
      capturedAt: new Date().toISOString()
    }
  };
}

async function captureArticle() {
  if (typeof Readability === 'undefined') {
    return { success: false, error: 'Readability not available — ensure the extension is up to date' };
  }

  const clone = document.cloneNode(true);
  const reader = new Readability(clone);
  const article = reader.parse();

  if (!article || !article.textContent || !article.textContent.trim()) {
    return { success: false, error: 'Could not extract article content' };
  }

  return {
    success: true,
    payload: {
      type: 'CONTEXT_CAPTURE',
      kind: 'articleText',
      jobId: generateJobId(),
      url: window.location.href,
      title: article.title || document.title,
      textContent: article.textContent.trim(),
      capturedAt: new Date().toISOString()
    }
  };
}

async function capturePageSnapshot() {
  const text = document.body ? document.body.innerText.trim() : '';
  if (!text) return { success: false, error: 'Page has no text content' };

  return {
    success: true,
    payload: {
      type: 'CONTEXT_CAPTURE',
      kind: 'pageSnapshot',
      jobId: generateJobId(),
      url: window.location.href,
      title: document.title,
      textContent: text,
      capturedAt: new Date().toISOString()
    }
  };
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || !message.type) return false;

  if (message.type === 'CAPTURE_SELECTION') {
    captureSelection().then(sendResponse);
    return true;
  }

  if (message.type === 'CAPTURE_ARTICLE') {
    captureArticle().then(sendResponse);
    return true;
  }

  if (message.type === 'CAPTURE_PAGE_SNAPSHOT') {
    capturePageSnapshot().then(sendResponse);
    return true;
  }

  return false;
});
