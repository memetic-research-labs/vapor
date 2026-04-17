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

function stripNoiseElements(root) {
  if (!root) return;

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
    for (const el of root.querySelectorAll(sel)) {
      el.remove();
    }
  }
}

function normalizeMarkdown(markdown) {
  return (markdown || '')
    .replace(/\r\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/[ \t]+\n/g, '\n')
    .trim();
}

function escapeMarkdownText(text) {
  return (text || '').replace(/([\\`*_\[\]])/g, '\\$1');
}

function inlineMarkdown(node) {
  if (!node) return '';

  if (node.nodeType === Node.TEXT_NODE) {
    return escapeMarkdownText((node.textContent || '').replace(/\s+/g, ' '));
  }

  if (node.nodeType !== Node.ELEMENT_NODE) {
    return '';
  }

  const tag = node.tagName.toLowerCase();
  const text = Array.from(node.childNodes).map(inlineMarkdown).join('');
  const collapsed = text.replace(/\s+/g, ' ').trim();

  switch (tag) {
    case 'br':
      return '  \n';
    case 'strong':
    case 'b':
      return collapsed ? `**${collapsed}**` : '';
    case 'em':
    case 'i':
      return collapsed ? `*${collapsed}*` : '';
    case 'code':
      return node.parentElement && node.parentElement.tagName.toLowerCase() === 'pre'
        ? node.textContent || ''
        : collapsed ? `\`${collapsed.replace(/`/g, '\\`')}\`` : '';
    case 'a': {
      const href = node.getAttribute('href') || '';
      if (!collapsed) return href;
      return href ? `[${collapsed}](${href})` : collapsed;
    }
    case 'img': {
      const alt = (node.getAttribute('alt') || '').trim();
      const src = node.getAttribute('src') || '';
      return src ? `![${alt}](${src})` : alt;
    }
    default:
      return text;
  }
}

function languageFromNode(node) {
  const className = node.getAttribute('class') || '';
  const matches = className.match(/language-([A-Za-z0-9_+-]+)/) || className.match(/lang(?:uage)?-([A-Za-z0-9_+-]+)/);
  return matches ? matches[1] : '';
}

function blockMarkdown(node, depth = 0) {
  if (!node) return '';

  if (node.nodeType === Node.TEXT_NODE) {
    const text = (node.textContent || '').replace(/\s+/g, ' ').trim();
    return text ? `${text}\n\n` : '';
  }

  if (node.nodeType !== Node.ELEMENT_NODE) {
    return '';
  }

  const tag = node.tagName.toLowerCase();
  const children = () => Array.from(node.childNodes).map((child) => blockMarkdown(child, depth)).join('');
  const inline = () => Array.from(node.childNodes).map(inlineMarkdown).join('').replace(/\s+/g, ' ').trim();

  switch (tag) {
    case 'article':
    case 'section':
    case 'main':
    case 'div':
      return children();
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6': {
      const level = Number(tag.slice(1));
      const text = inline();
      return text ? `${'#'.repeat(level)} ${text}\n\n` : '';
    }
    case 'p': {
      const text = inline();
      return text ? `${text}\n\n` : '';
    }
    case 'blockquote': {
      const text = normalizeMarkdown(children());
      if (!text) return '';
      const quoted = text.split('\n').map((line) => line ? `> ${line}` : '>').join('\n');
      return `${quoted}\n\n`;
    }
    case 'pre': {
      const codeNode = node.querySelector('code');
      const lang = codeNode ? languageFromNode(codeNode) : languageFromNode(node);
      const code = (codeNode ? codeNode.textContent : node.textContent || '').replace(/\n+$/, '');
      return code ? `\n\n\`\`\`${lang}\n${code}\n\`\`\`\n\n` : '';
    }
    case 'ul':
    case 'ol': {
      const ordered = tag === 'ol';
      const items = Array.from(node.children)
        .filter((child) => child.tagName && child.tagName.toLowerCase() === 'li')
        .map((child, index) => listItemMarkdown(child, ordered ? `${index + 1}. ` : '- ', depth));
      return items.length ? `${items.join('\n')}\n\n` : '';
    }
    case 'hr':
      return '---\n\n';
    case 'table': {
      const rows = Array.from(node.querySelectorAll('tr'));
      const rendered = rows.map((row) => {
        const cells = Array.from(row.children).map((cell) => inlineMarkdown(cell).replace(/\|/g, '\\|').trim());
        return cells.length ? `| ${cells.join(' | ')} |` : '';
      }).filter(Boolean);
      if (!rendered.length) return '';
      if (rows[0] && rows[0].querySelector('th')) {
        const thCount = rows[0].querySelectorAll('th').length;
        rendered.splice(1, 0, `| ${Array(thCount).fill('---').join(' | ')} |`);
      }
      return `${rendered.join('\n')}\n\n`;
    }
    default: {
      const text = inline();
      return text ? `${text}\n\n` : '';
    }
  }
}

function listItemMarkdown(node, marker, depth) {
  const pieces = [];

  for (const child of node.childNodes) {
    if (child.nodeType === Node.ELEMENT_NODE) {
      const tag = child.tagName.toLowerCase();
      if (tag === 'ul' || tag === 'ol') {
        const nested = blockMarkdown(child, depth + 1).trimEnd();
        if (nested) {
          pieces.push(`\n${nested.split('\n').map((line) => line ? `  ${line}` : '').join('\n')}`);
        }
        continue;
      }
      if (tag === 'pre') {
        const codeBlock = blockMarkdown(child, depth + 1).trimEnd();
        if (codeBlock) {
          pieces.push(`\n${codeBlock.split('\n').map((line) => line ? `  ${line}` : '').join('\n')}`);
        }
        continue;
      }
    }
    const inline = inlineMarkdown(child).replace(/\s+/g, ' ').trim();
    if (inline) pieces.push(inline);
  }

  const text = pieces.join(' ').replace(/ +\n/g, '\n').trim();
  return `${marker}${text}`;
}

function htmlToMarkdown(html) {
  const div = document.createElement('div');
  div.innerHTML = html;
  stripNoiseElements(div);
  return normalizeMarkdown(Array.from(div.childNodes).map((node) => blockMarkdown(node)).join(''));
}

function markdownToPlainText(markdown) {
  return normalizeMarkdown(markdown
    .replace(/^#{1,6}\s+/gm, '')
    .replace(/```[A-Za-z0-9_+-]*\n([\s\S]*?)```/g, '$1')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '$1')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1 ($2)')
    .replace(/^>\s?/gm, '')
    .replace(/^[-*+]\s+/gm, '- ')
    .replace(/^\d+\.\s+/gm, '- ')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\*([^*]+)\*/g, '$1')
    .replace(/---+/g, ''));
}

function htmlToCleanText(html) {
  const markdown = htmlToMarkdown(html);
  return markdownToPlainText(markdown);
}

function tryReadability() {
  if (typeof Readability === 'undefined') return null;

  try {
    const clone = document.cloneNode(true);
    const reader = new Readability(clone);
    const article = reader.parse();

    if (!article || !article.content || !article.content.trim()) return null;

    const markdownContent = htmlToMarkdown(article.content);
    const text = markdownToPlainText(markdownContent);
    if (!text || text.length < 100) return null;

    return {
      title: article.title || document.title,
      textContent: text,
      markdownContent: markdownContent,
      byline: article.byline || null
    };
  } catch (e) {
    console.error('[Vapor] Readability parse error:', e);
    return null;
  }
}

function buildPayload(kind, title, textContent, markdownContent, metadata, byline) {
  return {
    type: 'CONTEXT_CAPTURE',
    kind: kind,
    jobId: generateJobId(),
    url: window.location.href,
    title: title,
    textContent: textContent,
    markdownContent: markdownContent || null,
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
      payload: buildPayload('articleText', article.title, article.textContent, article.markdownContent, metadata, article.byline)
    };
  }

  console.log('[Vapor] Readability failed, falling back to page text');
  const text = document.body ? normalizeMarkdown(document.body.innerText) : '';
  if (!text) return { success: false, error: 'Page has no text content' };
  const markdown = text
    .split(/\n\s*\n/)
    .map((part) => part.trim())
    .filter(Boolean)
    .join('\n\n');

  return {
    success: true,
    payload: buildPayload('pageSnapshot', document.title, text, markdown, metadata, null)
  };
}

async function captureSelection() {
  const selection = window.getSelection();
  const text = selection ? selection.toString().trim() : '';
  if (!text) return { success: false, error: 'No text selected' };

  const metadata = extractMetadata();

  return {
    success: true,
    payload: buildPayload('selectedText', document.title, normalizeMarkdown(text), normalizeMarkdown(text), metadata, null)
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
        payload: buildPayload('articleText', article.title, article.textContent, article.markdownContent, metadata, article.byline)
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
