const PLATFORM_CONFIGS = {
  'chatgpt.com': {
    name: 'ChatGPT',
    promptSelectors: ['#prompt-textarea', 'div[contenteditable="true"]', 'textarea#prompt-textarea'],
    submitSelectors: ['button[data-testid="send-button"]', 'form button[type="submit"]'],
    submitMode: 'enter',
  },
  'chat.openai.com': {
    name: 'ChatGPT (legacy)',
    promptSelectors: ['#prompt-textarea', 'textarea[data-id="root"]'],
    submitSelectors: ['form button[type="submit"]'],
    submitMode: 'enter',
  },
  'claude.ai': {
    name: 'Claude',
    promptSelectors: ['div[contenteditable="true"][data-placeholder]', 'div[contenteditable="true"]', 'textarea'],
    submitSelectors: ['button[aria-label="Send message"]'],
    submitMode: 'enter',
  },
  'gemini.google.com': {
    name: 'Gemini',
    promptSelectors: ['div.ql-editor textarea[aria-label*="Enter a prompt"]', 'div[contenteditable="true"]', 'textarea.ql-textarea'],
    submitSelectors: ['button[aria-label*="Send"]', 'button[aria-label*="Submit"]'],
    submitMode: 'enter',
  },
  'perplexity.ai': {
    name: 'Perplexity',
    promptSelectors: ['textarea'],
    submitSelectors: ['button[aria-label="Submit"]'],
    submitMode: 'enter',
  },
  'grok.com': {
    name: 'Grok',
    promptSelectors: ['div[class*="textarea"] textarea', 'textarea'],
    submitMode: 'enter',
  },
  'x.com': {
    name: 'Grok',
    promptSelectors: ['div[class*="textarea"] textarea', 'textarea'],
    submitMode: 'enter',
  },
  '_default': {
    name: 'Generic',
    promptSelectors: ['textarea', 'input[type="text"]', 'input:not([type])', '[contenteditable="true"]', '[role="textbox"]'],
    submitSelectors: ['button[type="submit"]', 'input[type="submit"]', 'button[aria-label*="Send" i]'],
    promptKeywords: ['prompt', 'message', 'ask', 'chat', 'input'],
    submitMode: 'enter',
  }
};

export function getPlatformConfig(hostname) {
  if (PLATFORM_CONFIGS[hostname]) {
    return PLATFORM_CONFIGS[hostname];
  }
  return PLATFORM_CONFIGS._default;
}
