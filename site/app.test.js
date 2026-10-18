// Set up minimal DOM / fetch stubs for Node tests.
function noopElement() {
  return {
    className: '',
    textContent: '',
    href: '',
    appendChild: function () {},
    removeChild: function () {},
    setAttribute: function () {},
    firstChild: null
  };
}

global.document = {
  getElementById: function () { return noopElement(); },
  querySelector: function () { return noopElement(); },
  createElement: function () { return noopElement(); },
  createTextNode: function (text) { return { textContent: text }; }
};

global.fetch = function () {
  return Promise.resolve({
    ok: true,
    headers: { get: function () { return null; } },
    json: function () { return Promise.resolve([]); }
  });
};

const assert = require('assert');
const app = require('./app.js');

function test(name, fn) {
  try {
    fn();
    console.log('PASS: ' + name);
  } catch (error) {
    console.error('FAIL: ' + name + ' - ' + error.message);
    process.exitCode = 1;
  }
}

test('isAllowedDownloadURL allows github.com', function () {
  assert.strictEqual(
    app.isAllowedDownloadURL('https://github.com/T3pp31/Transnote/releases/download/v0.1.0/Transnote.dmg'),
    true
  );
});

test('isAllowedDownloadURL rejects http', function () {
  assert.strictEqual(app.isAllowedDownloadURL('http://github.com/x'), false);
});

test('isAllowedDownloadURL rejects other host', function () {
  assert.strictEqual(app.isAllowedDownloadURL('https://evil.example.com/x'), false);
});

test('formatDate formats ISO date', function () {
  assert.strictEqual(app.formatDate('2026-01-15T00:00:00Z'), '2026年1月15日');
});

test('findDmgAsset matches versioned dmg', function () {
  const assets = [
    { name: 'Transnote-0.2.0.dmg' },
    { name: 'notes.txt' }
  ];
  assert.strictEqual(app.findDmgAsset(assets).name, 'Transnote-0.2.0.dmg');
});

test('findSha256Asset matches expected name', function () {
  const dmg = { name: 'Transnote-0.2.0.dmg' };
  const assets = [
    { name: 'Transnote-0.2.0.dmg.sha256' },
    { name: 'other.txt' }
  ];
  assert.strictEqual(app.findSha256Asset(assets, dmg).name, 'Transnote-0.2.0.dmg.sha256');
});
