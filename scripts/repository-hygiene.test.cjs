const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const removedNotes = [
  'DEVICE-FIRST-RUN-CHECKLIST.md',
  'arkts-compile-checklist.md',
  'eas-api-capture.md',
  'eas-cookie-finish-notes.md',
  'eas-page-predicate-notes.md',
  'eas-timetable-view-notes.md',
  'mapping-hitax-to-arkts.md',
  'project-state.md'
];
const files = execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8' })
  .split('\0').filter(file => file && fs.existsSync(path.join(root, file)));

test('the repository contains no downloaded Android implementation or temporary reference files', () => {
  for (const file of files) {
    assert.doesNotMatch(file, /^(scratch|\.analysis|HITA_Android_src)\//, file);
    assert.doesNotMatch(file, /\.(kt|java|apk|dex|aar)$/i, file);
  }
  for (const name of removedNotes) {
    assert.equal(fs.existsSync(path.join(root, 'docs', name)), false, name);
  }
});

test('reference directories are ignored to prevent accidental reintroduction', () => {
  const probes = ['scratch/reference.kt', '.analysis/reference.java', 'HITA_Android_src/reference.kt'];
  const ignored = execFileSync('git', ['check-ignore', '--no-index', ...probes], {
    cwd: root, encoding: 'utf8'
  }).trim().split(/\r?\n/);
  assert.deepEqual(ignored, probes);
});

test('remaining documentation and runtime comments do not point at deleted migration notes', () => {
  for (const file of files.filter(name => /\.(md|ets)$/.test(name))) {
    const text = fs.readFileSync(path.join(root, file), 'utf8');
    for (const name of removedNotes) assert.equal(text.includes(name), false, `${file}: ${name}`);
    assert.equal(text.includes('.analysis/decomp/'), false, file);
  }
});
