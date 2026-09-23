// Test the generated browser script with controlled, out-of-order image loads.
import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, writeFileSync, rmSync, readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import vm from 'node:vm';

const directory = mkdtempSync(join(tmpdir(), 'bbtex-page-'));
try {
  const binary = resolve('_build/default/bin/main.exe');
  const source = join(directory, 'paper.tex');
  writeFileSync(source, 'saved source');
  const result = spawnSync(binary, ['snippet-begin', source, '3', 'manual'], {
    env: {...process.env, BBTEX_STATE_DIR: directory}, encoding: 'utf8'
  });
  assert.equal(result.status, 0, result.stderr);
  const folder = join(directory, 'snippet-window');
  const page = readFileSync(join(folder, readdirSync(folder).find(p => p.endsWith('.html'))), 'utf8');
  const script = page.match(/<script>([\s\S]*)<\/script>/)[1];
  const elements = new Map();
  function element(name) {
    if (!elements.has(name)) elements.set(name, {
      textContent: '', hidden: false, dataset: {},
      getAttribute(key) { return this[key]; },
      removeAttribute(key) { delete this[key]; },
      remove() {},
      set innerHTML(_) { throw new Error('Content must be inserted as text'); }
    });
    return elements.get(name);
  }
  const pending = [];
  const window = {};
  const context = vm.createContext({window, Date, setInterval() {},
    document: {
      body: {...element('body'), appendChild() {}},
      getElementById: element, querySelector: element, createElement: element
    },
    Image: class { set src(value) { this.value = value; pending.push(this); } }
  });
  vm.runInContext(script, context);
  assert.equal(window.bbtexSnippetVersion, 3);
  // The page polls revision.js and loads image.js only for a new revision.
  const loader = element('script');
  assert.match(loader.src, /^revision\.js\?t=/);
  loader.onload();
  window.bbtexRevision('r1');
  assert.match(loader.src, /^image\.js\?t=/);
  loader.onload();
  loader.src = 'unchanged';
  window.bbtexRevision('r1');
  assert.equal(loader.src, 'unchanged', 'same revision: image.js is not fetched again');
  window.bbtexRevision('r2');
  assert.match(loader.src, /^image\.js\?t=/);
  loader.onerror();
  loader.src = 'unchanged';
  window.bbtexRevision('r2');
  assert.match(loader.src, /^image\.js\?t=/, 'a failed fetch is retried');
  loader.onload();
  let revisionSeen = null;
  vm.runInNewContext(readFileSync(join(folder, 'revision.js'), 'utf8'),
    {window: {bbtexRevision(r) { revisionSeen = r; }}});
  assert.match(revisionSeen, /^[0-9a-f]{32}$/);
  const state = {generation: 'one', revision: 1, status: 'current', source,
    line: 3, imageLine: 3, image: 'image-one', message: '', log: ''};
  window.bbtexSnippet(state);
  const firstLoad = pending.pop();
  window.bbtexSnippet({...state, revision: 2, status: 'rendering', image: '', message: 'Rendering'});
  firstLoad.onload();
  assert.equal(element('figure').hidden, true);
  assert.equal(element('status').textContent, 'Rendering…');

  window.bbtexSnippet({...state, revision: 3, image: 'image-two'});
  pending.pop().onload();
  assert.equal(element('formula').src, 'image-two');
  window.bbtexSnippet({...state, revision: 2, image: 'obsolete'});
  assert.equal(element('formula').src, 'image-two');
  window.bbtexSnippet({...state, revision: 4, image: 'image-two', status: 'error',
    message: '<script>not markup</script>', log: '/tmp/quoted "log".log'});
  pending.pop().onload();
  assert.equal(element('message').textContent, '<script>not markup</script>');
  assert.match(element('caption').textContent, /out of date/);
  assert.match(element('log').textContent, /Open Preview Log/);
  assert.equal(context.document.body.dataset.status, 'error');

  let reloaded = false;
  vm.runInNewContext(readFileSync(join(folder, 'image.js'), 'utf8'), {
    window: {}, location: {reload() { reloaded = true; }}
  });
  assert.equal(reloaded, true);
  reloaded = false;
  vm.runInNewContext(readFileSync(join(folder, 'image.js'), 'utf8'), {
    window: {bbtexSnippetVersion: 2, bbtexSnippet() { throw new Error('Old renderer must reload'); }},
    location: {reload() { reloaded = true; }}
  });
  assert.equal(reloaded, true);
  console.log('Browser state: delayed images, obsolete responses, stale captions, safe text, and migration passed');
} finally {
  rmSync(directory, {recursive: true, force: true});
}
