const PLATFORM_CONFIGS = {
  'chatgpt.com': {
    name: 'ChatGPT',
    promptSelectors: ['#prompt-textarea', 'div[contenteditable="true"]', 'textarea#prompt-textarea'],
  },
  'chat.openai.com': {
    name: 'ChatGPT (legacy)',
    promptSelectors: ['#prompt-textarea', 'textarea[data-id="root"]'],
  },
  'claude.ai': {
    name: 'Claude',
    promptSelectors: ['div[contenteditable="true"][data-placeholder]', 'div[contenteditable="true"]', 'textarea'],
  },
  'gemini.google.com': {
    name: 'Gemini',
    promptSelectors: ['div.ql-editor textarea[aria-label*="Enter a prompt"]', 'div[contenteditable="true"]', 'textarea.ql-textarea'],
  },
  'perplexity.ai': {
    name: 'Perplexity',
    promptSelectors: ['textarea'],
  },
  'grok.com': {
    name: 'Grok',
    promptSelectors: ['div[class*="textarea"] textarea', 'textarea'],
  },
  'x.com': {
    name: 'Grok',
    promptSelectors: ['div[class*="textarea"] textarea', 'textarea'],
  },
  '_default': {
    name: 'Generic',
    promptSelectors: ['textarea', 'input[type="text"]', 'input:not([type])', '[contenteditable="true"]', '[role="textbox"]'],
    promptKeywords: ['prompt', 'message', 'ask', 'chat', 'input'],
  }
};

export function getPlatformConfig(hostname) {
  if (PLATFORM_CONFIGS[hostname]) {
    return PLATFORM_CONFIGS[hostname];
  }
  return PLATFORM_CONFIGS._default;
}
