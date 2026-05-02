const PLATFORM_CONFIGS = {
  'chatgpt.com': {
    name: 'ChatGPT',
    promptSelectors: ['#prompt-textarea', 'div[contenteditable="true"]', 'textarea#prompt-textarea'],
    imageDropTarget: '#prompt-textarea, div[contenteditable="true"]',
    imageUploadSelector: 'input[type="file"][accept*="image"]',
    pasteSupport: true,
    imageInjectionDelay: 500,
  },
  'chat.openai.com': {
    name: 'ChatGPT (legacy)',
    promptSelectors: ['#prompt-textarea', 'textarea[data-id="root"]'],
    imageDropTarget: '#prompt-textarea, textarea[data-id="root"]',
    imageUploadSelector: 'input[type="file"][accept*="image"]',
    pasteSupport: true,
    imageInjectionDelay: 500,
  },
  'claude.ai': {
    name: 'Claude',
    promptSelectors: ['div[contenteditable="true"][data-placeholder]', 'div[contenteditable="true"]', 'textarea'],
    imageDropTarget: 'div[contenteditable="true"][data-placeholder], div[contenteditable="true"]',
    imageUploadSelector: 'input[type="file"]',
    pasteSupport: true,
    imageInjectionDelay: 300,
  },
  'gemini.google.com': {
    name: 'Gemini',
    promptSelectors: ['div.ql-editor textarea[aria-label*="Enter a prompt"]', 'div[contenteditable="true"]', 'textarea.ql-textarea'],
    imageDropTarget: 'div.ql-editor textarea, div[contenteditable="true"]',
    imageUploadSelector: 'input[type="file"]',
    pasteSupport: true,
    imageInjectionDelay: 400,
  },
  'perplexity.ai': {
    name: 'Perplexity',
    promptSelectors: ['textarea'],
    imageDropTarget: 'textarea',
    imageUploadSelector: 'input[type="file"]',
    pasteSupport: true,
    imageInjectionDelay: 300,
  },
  'grok.com': {
    name: 'Grok',
    promptSelectors: ['div[class*="textarea"] textarea', 'textarea'],
    imageDropTarget: 'div[class*="textarea"] textarea, textarea',
    imageUploadSelector: 'input[type="file"]',
    pasteSupport: true,
    imageInjectionDelay: 300,
  },
  'x.com': {
    name: 'Grok',
    promptSelectors: ['div[class*="textarea"] textarea', 'textarea'],
    imageDropTarget: 'div[class*="textarea"] textarea, textarea',
    imageUploadSelector: 'input[type="file"]',
    pasteSupport: true,
    imageInjectionDelay: 300,
  },
  '_default': {
    name: 'Generic',
    promptSelectors: ['textarea', 'input[type="text"]', 'input:not([type])', '[contenteditable="true"]', '[role="textbox"]'],
    promptKeywords: ['prompt', 'message', 'ask', 'chat', 'input'],
    imageDropTarget: 'textarea, [contenteditable="true"], [role="textbox"]',
    imageUploadSelector: 'input[type="file"]',
    pasteSupport: true,
    imageInjectionDelay: 300,
  }
};

export function getPlatformConfig(hostname) {
  if (PLATFORM_CONFIGS[hostname]) {
    return PLATFORM_CONFIGS[hostname];
  }
  return PLATFORM_CONFIGS._default;
}
