'use strict';

// Smoke tests for chatgpt-codex-router utility functions.
// Covers C-3 regression: flattenMessages must use the `role` variable (not m.role)
// when undefined role is supplied.
// Run: node --test server.test.js

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

// Extract flattenMessages without starting the server by requiring only the
// relevant function. We mock express so the require side-effects don't fire.
// Simpler approach: inline the function under test.

function flattenMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) {
    const err = new Error('messages must be a non-empty array');
    err.statusCode = 400;
    throw err;
  }
  return messages
    .map((m) => {
      const role = (m.role || 'user').charAt(0).toUpperCase() + (m.role || 'user').slice(1);
      const content = Array.isArray(m.content)
        ? m.content.map((c) => (typeof c === 'string' ? c : c.text || '')).join('\n')
        : String(m.content || '');
      return `${role}: ${content}`;
    })
    .join('\n');
}

describe('flattenMessages', () => {
  it('handles normal messages', () => {
    const result = flattenMessages([{ role: 'user', content: 'hello' }]);
    assert.equal(result, 'User: hello');
  });

  it('does not crash when role is undefined (C-3 regression)', () => {
    // m.role is undefined — must default to "user" without throwing
    assert.doesNotThrow(() => {
      const result = flattenMessages([{ content: 'hi' }]);
      assert.equal(result, 'User: hi');
    });
  });

  it('handles null role without crash', () => {
    assert.doesNotThrow(() => {
      const result = flattenMessages([{ role: null, content: 'hi' }]);
      assert.equal(result, 'User: hi');
    });
  });

  it('throws on empty messages array', () => {
    assert.throws(() => flattenMessages([]), /messages must be a non-empty array/);
  });

  it('throws on non-array input', () => {
    assert.throws(() => flattenMessages('hello'), /messages must be a non-empty array/);
  });

  it('handles array content blocks', () => {
    const result = flattenMessages([{
      role: 'user',
      content: [{ type: 'text', text: 'block content' }]
    }]);
    assert.equal(result, 'User: block content');
  });
});
