import js from '@eslint/js';

// Stub for inline eslint-disable comments that reference this plugin.
// The full plugin isn't installed; this just prevents "rule not found" errors.
const reactHooksStub = { plugins: { 'react-hooks': { rules: { 'exhaustive-deps': { create: () => ({}) } } } } };

const browserGlobals = {
  window: 'readonly', document: 'readonly', console: 'readonly',
  fetch: 'readonly', URL: 'readonly', URLSearchParams: 'readonly',
  localStorage: 'readonly', location: 'readonly', history: 'readonly',
  setTimeout: 'readonly', clearTimeout: 'readonly', setInterval: 'readonly',
  clearInterval: 'readonly', requestAnimationFrame: 'readonly',
  MutationObserver: 'readonly', ResizeObserver: 'readonly',
  AbortController: 'readonly', AbortSignal: 'readonly',
  alert: 'readonly', confirm: 'readonly', performance: 'readonly',
  globalThis: 'readonly', React: 'readonly', ReactDOM: 'readonly',
};

export default [
  js.configs.recommended,

  // Server — Node.js ES modules
  {
    files: ['server/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        process: 'readonly', console: 'readonly', fetch: 'readonly',
        Buffer: 'readonly', setTimeout: 'readonly', clearTimeout: 'readonly',
        setInterval: 'readonly', clearInterval: 'readonly',
        URL: 'readonly', AbortController: 'readonly', AbortSignal: 'readonly',
      },
    },
    rules: {
      'no-unused-vars': ['error', { argsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' }],
      'no-undef': 'error',
    },
  },

  // Static transform module — pure ES module, no browser globals needed
  {
    files: ['static/transform.js'],
    languageOptions: { ecmaVersion: 2022, sourceType: 'module' },
    rules: {
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      'no-undef': 'error',
    },
  },

  // Static browser scripts — JSX via Babel, all loaded as globals.
  reactHooksStub,
  // no-undef is off: components are defined across sibling <script> tags;
  // ESLint can't see cross-file globals without a bundler.
  {
    files: ['static/**/*.jsx', 'static/**/*.js'],
    ignores: ['static/transform.js', 'static/vendor/**'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'script',
      parserOptions: { ecmaFeatures: { jsx: true } },
      globals: { ...browserGlobals },
    },
    rules: {
      'no-unused-vars': ['warn', { argsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      'no-undef': 'off',
      'no-constant-condition': 'warn',
      'no-unreachable': 'error',
      'no-dupe-keys': 'error',
      'no-duplicate-case': 'error',
    },
  },
];
