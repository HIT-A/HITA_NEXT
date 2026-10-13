const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const root = path.resolve(__dirname, '../entry/src/main/ets');
function files(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(item => {
    const full = path.join(dir, item.name);
    return item.isDirectory() ? files(full) : full.endsWith('.ets') ? [full] : [];
  });
}

test('every bottom-sheet entry uses the shared content boundary, including newly added sheets', () => {
  let count = 0;
  for (const file of files(root)) {
    const source = fs.readFileSync(file, 'utf8');
    const bindings = [...source.matchAll(/\.bindSheet\([^,]+,\s*this\.(\w+)\(\)/g)];
    assert.equal(bindings.length, (source.match(/\.bindSheet\(/g) || []).length,
      path.relative(root, file) + ': bindSheet must name a reviewable content builder');
    for (const [, name] of bindings) {
      const entry = new RegExp('\\b'+name+'\\(\\)\\s*\\{\\s*SheetContent\\(');
      assert.match(source, entry, path.relative(root, file)+': '+name+' must own shared top spacing');
      count++;
    }
  }
  assert.ok(count >= 4);
});

test('shared inset leaves at least 24 vp below the system drag bar, with bounded fit-content sizing', () => {
  const source = fs.readFileSync(path.join(root, 'common/components/SheetContent.ets'), 'utf8');
  const value = Number(source.match(/SHEET_CONTENT_TOP_INSET:\s*number\s*=\s*(\d+)/)?.[1]);
  assert.ok(value >= 24 && value <= 32, 'changing the spacing range needs visual review and a new product decision');
  assert.match(source, /\.padding\(\{ top: SHEET_CONTENT_TOP_INSET \}\)/);
  assert.match(source, /\.height\(this.fillHeight \? '100%' : undefined\)/);
});
