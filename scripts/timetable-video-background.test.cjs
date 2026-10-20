const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/feature/timetable/data/TimetableBackgroundStore.ets'), 'utf8');
function setup(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hita-wallpaper-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const state = { selected: [], fail: '', released: [], open: new Set() };
  const open = (name, mode) => {
    const fd = fs.openSync(name, mode ? 'w+' : 'r'); state.open.add(fd); return { fd };
  };
  const close = file => { fs.closeSync(file.fd); state.open.delete(file.fd); };
  const io = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
    accessSync: fs.existsSync, readTextSync: name => fs.readFileSync(name, 'utf8'),
    openSync: open, open: async (...args) => open(...args), closeSync: close, close: async file => close(file),
    statSync: fs.fstatSync, writeSync: fs.writeSync, unlinkSync: fs.unlinkSync,
    renameSync: (...args) => { if (state.fail === 'publish') throw Error('publish'); fs.renameSync(...args); },
    copyFile: async (src, dest) => { if (state.fail === 'copy') throw Error('disk full'); fs.writeFileSync(dest, fs.readFileSync(src)); }
  };
  const mocks = {
    '@kit.AbilityKit': {},
    '@kit.CoreFileKit': { fileIo: io, picker: {
      PhotoSelectOptions: class {}, PhotoViewMIMETypes: { IMAGE_TYPE: 'image', VIDEO_TYPE: 'video' },
      PhotoViewPicker: class { async select(options) { state.options = options; return { photoUris: state.selected }; } }
    } },
    '@kit.MediaKit': { media: { AVImageQueryOptions: { AV_IMAGE_QUERY_NEXT_SYNC: 0 },
      createAVImageGenerator: async () => ({
        fetchFrameByTime: async () => { if (state.fail === 'decode') throw Error('unsupported');
          return { release: async () => state.released.push('pixels') }; },
        release: async () => state.released.push('generator')
      }) } },
    '@kit.ImageKit': { image: { createImagePacker: () => ({
      packToFile: async (_, fd) => { if (state.fail === 'cover') throw Error('cover'); fs.writeFileSync(fd, 'cover'); },
      release: async () => state.released.push('packer')
    }) } }
  };
  const mod = { exports: {} };
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  new Function('require', 'module', 'exports', js)(name => mocks[name], mod, mod.exports);
  const legacy = dir + '/timetable-background.jpg'; fs.writeFileSync(legacy, 'old image');
  const input = path.join(dir, 'input'); fs.writeFileSync(input, 'original video bytes');
  return { store: mod.exports.TimetableBackgroundStore, state, ctx: { filesDir: dir }, legacy, input };
}
test('legacy wallpaper survives picker cancellation', async t => {
  const {store, state, ctx, legacy} = setup(t);
  assert.equal(store.loadPath(ctx), legacy);
  assert.equal(await store.pickAndSave(ctx, true), undefined);
  assert.equal(store.loadPath(ctx), legacy);
  assert.equal(state.open.size, 0);
});
for (const failure of ['copy', 'decode', 'cover', 'publish']) {
  test(`${failure} failure preserves selection and cleans all partial media and handles`, async t => {
    const {store, state, ctx, legacy, input} = setup(t);
    state.selected = [input]; state.fail = failure;
    await assert.rejects(store.pickAndSave(ctx, true));
    assert.equal(store.loadPath(ctx), legacy);
    assert.equal(state.open.size, 0);
    assert.deepEqual(fs.readdirSync(ctx.filesDir).sort(), ['input', 'timetable-background.jpg']);
    if (failure === 'decode') assert.deepEqual(state.released, ['generator']);
    if (failure === 'cover' || failure === 'publish') assert.deepEqual(state.released, ['packer', 'pixels', 'generator']);
  });
}
test('video bytes stay unchanged, cover and selection survive reload, removal clears both', async t => {
  const {store, state, ctx, legacy, input} = setup(t);
  state.selected = [input];
  const selected = await store.pickAndSave(ctx, true);
  assert.equal(state.options.MIMEType, 'video');
  assert.equal(fs.readFileSync(selected.videoPath, 'utf8'), 'original video bytes');
  assert.equal(fs.readFileSync(selected.imagePath, 'utf8'), 'cover');
  assert.deepEqual(JSON.parse(JSON.stringify(store.load(ctx))), JSON.parse(JSON.stringify(selected)));
  assert.equal(fs.existsSync(legacy), false);
  assert.equal(state.open.size, 0);
  store.remove(ctx);
  assert.equal(store.loadPath(ctx), '');
  assert.equal(fs.existsSync(selected.videoPath), false);
  assert.equal(fs.existsSync(selected.imagePath), false);
});
test('ordinary image import remains supported', async t => {
  const {store, state, ctx, input} = setup(t);
  state.selected = [input];
  const selected = await store.pickAndSave(ctx);
  assert.equal(state.options.MIMEType, 'image');
  assert.equal(selected.videoPath, '');
  assert.equal(state.released.length, 0);
  assert.equal(fs.readFileSync(selected.imagePath, 'utf8'), 'original video bytes');
});
test('missing saved video falls back to its existing cover', async t => {
  const {store, state, ctx, input} = setup(t);
  state.selected = [input];
  const selected = await store.pickAndSave(ctx, true);
  fs.unlinkSync(selected.videoPath);
  assert.equal(store.load(ctx).videoPath, '');
  assert.equal(store.load(ctx).imagePath, selected.imagePath);
});
test('playback is silent, scoped to foreground timetable, and keeps cover beneath video and mask', () => {
  const root = path.join(__dirname, '../entry/src/main/ets');
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const video = fs.readFileSync(path.join(root, 'feature/timetable/views/TimetableVideoBackground.ets'), 'utf8');
  const ability = fs.readFileSync(path.join(root, 'entryability/EntryAbility.ets'), 'utf8');
  assert.match(home, /!this\.timetableVideoFailed &&\s*this\.pageVisible && this\.appForeground && this\.currentTab === TAB_TIMETABLE/);
  assert.match(home, /Image\(this\.timetableBgUri\)[\s\S]*TimetableVideoBackground\([\s\S]*backgroundColor\(Color\.Black\)/);
  assert.match(home, /onPlaybackError:[\s\S]*this\.timetableVideoFailed = true/);
  assert.match(ability, /onForeground\(\)[\s\S]*setOrCreate\('hita_app_foreground', true\)/);
  assert.match(ability, /onBackground\(\)[\s\S]*setOrCreate\('hita_app_foreground', false\)/);
  assert.match(video, /muted\(true\)[\s\S]*autoPlay\(true\)[\s\S]*controls\(false\)[\s\S]*loop\(true\)/);
  assert.match(video, /opacity\(this\.ready \? 1 : 0\)[\s\S]*onStart\(/);
});
