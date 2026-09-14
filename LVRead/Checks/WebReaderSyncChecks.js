// Run with: node LVRead/Checks/WebReaderSyncChecks.js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../LVRead/Resources/WebReader.html'), 'utf8');
for (const [, script] of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)) new vm.Script(script);
const source = ['blankPage', 'remoteSpreadOffset', 'normalizeCache', 'visibleSignature', 'refreshCache', 'refreshRemotePage', 'recordProgress', 'applyRemoteCache', 'finishTurn'].map(name => {
  const match = html.match(new RegExp(`    (?:async )?function ${name}\\([^]*?\\n    }`));
  assert(match, `Missing ${name}`);
  return match[0];
}).join('\n');
const page = (number, chapterIndex = 0) => ({ chapterIndex, pageIndex: number - 1, content: `Page ${chapterIndex}:${number}` });

async function check({mode = 'spread', bookId = 'book', before = [page(2), page(3)], pages = [1, 2, 3, 4, 5].map(n => page(n)), remote = 3, expected = [2, 3], renders = 0}) {
  let renderCount = 0;
  const state = {mode, cache: {bookId: 'book', pages: before}, cursor: 0, progressVersion: 0};
  const payload = {bookId, pages, anchorOffset: pages.findIndex(p => p.pageIndex === remote - 1)};
  const context = vm.createContext({
    state, location: {protocol: 'https:'},
    currentPage: () => state.cache?.pages[state.cursor], prepareTurn: () => false, reduceMotion: {matches: true},
    pageKey: p => p ? `${p.chapterIndex}:${p.pageIndex}` : '',
    api: async url => url === 'cache' ? payload : {}, cacheEndpoint: () => 'cache',
    applySettings() {}, setConnected() {}, updateReadingMeta() {}, updateBookThickness() {}, preloadTurn() {},
    renderCurrent() { renderCount++; }, persist: async () => {}
  });
  vm.runInContext(source, context);
  assert.equal(await vm.runInContext('refreshCache(false)', context), true);
  assert.deepEqual(Array.from(state.cache.pages.slice(state.cursor, state.cursor + 2), p => p.pageIndex + 1), expected);
  assert.equal(renderCount, renders);
  if (mode === 'spread') assert.equal(state.cursor % 2, 0, 'Spread navigation requires an even cursor');
}

async function checkFastSync() {
  let fullRefreshes = 0;
  let renders = 0;
  let remote = page(3);
  const state = {mode: 'spread', cache: {bookId: 'book', pages: [2, 3, 4, 5].map(n => page(n))}, cursor: 0, progressVersion: 0, connected: true};
  const context = vm.createContext({
    state, remotePageRequest: 0, remotePageRefreshPending: false,
    currentPage: () => state.cache?.pages[state.cursor], prepareTurn: () => false, reduceMotion: {matches: true},
    pageKey: p => p ? `${p.chapterIndex}:${p.pageIndex}` : '',
    api: async () => ({...remote, bookId: 'book'}), currentUnit: () => 2,
    refreshCacheWindow: async () => { fullRefreshes++; },
    renderCurrent() { renders++; }, persist: async () => {},
    isNearCacheBoundary: () => false, scheduleCacheRefresh() {}
  });
  vm.runInContext(source, context);
  await vm.runInContext('refreshRemotePage()', context);
  assert.equal(state.cursor, 0);
  assert.equal(renders, 0);
  remote = page(4);
  await vm.runInContext('refreshRemotePage()', context);
  assert.equal(state.cache.pages[state.cursor].pageIndex, 3);
  assert.equal(renders, 1);
  assert.equal(fullRefreshes, 0, 'Cached turns must not fetch the whole cache');
  for (const [number, left, expectedRenders] of [[5, 4, 1], [3, 2, 2], [2, 2, 2], [4, 4, 3], [5, 4, 3]]) {
    remote = page(number);
    await vm.runInContext('refreshRemotePage()', context);
    assert.equal(state.cache.pages[state.cursor].pageIndex + 1, left);
    assert.equal(renders, expectedRenders, 'Forward and backward turns must preserve pairs');
  }
  remote = page(9);
  await vm.runInContext('refreshRemotePage()', context);
  assert.equal(fullRefreshes, 1, 'Missing pages must load the cache');

  let releaseSave;
  let sent = false;
  context.currentPage = () => page(4);
  context.clearTimeout = () => {};
  context.persist = () => new Promise(resolve => { releaseSave = resolve; });
  context.syncPendingProgress = async () => { sent = true; };
  const recording = vm.runInContext('recordProgress()', context);
  assert.equal(sent, true, 'Progress must send before local storage finishes');
  releaseSave();
  await recording;
}

async function checkRemoteAnimation() {
  const state = {mode: 'spread', cursor: 0, progressVersion: 0, cache: {bookId: 'book', pages: [page(4), page(5)]}};
  const directions = [];
  let syncWrites = 0;
  const context = vm.createContext({
    state, remotePageRefreshPending: false,
    pageKey: p => p ? `${p.chapterIndex}:${p.pageIndex}` : '',
    currentPage: () => state.cache.pages[state.cursor], reduceMotion: {matches: false},
    prepareTurn(direction) { directions.push(direction); state.turnDirection = direction; state.turning = true; return true; },
    animateTurn(to, done) { done(); }, requestAnimationFrame: done => done(),
    clearTimeout() {}, renderCurrent() {}, preloadTurn() {}, persist() {},
    elements: {turning: {classList: {remove() {}}, style: {}}}
  });
  vm.runInContext(source, context);
  context.recordProgress = () => { syncWrites++; };
  context.nextCache = {bookId: 'book', pages: [2, 3, 4, 5].map(n => page(n)), anchorOffset: 0};
  await vm.runInContext('applyRemoteCache(nextCache)', context);
  assert.equal(state.cache.pages[state.cursor].pageIndex + 1, 2);
  assert.deepEqual(directions, [-1]);
  context.nextCache.anchorOffset = 2;
  await vm.runInContext('applyRemoteCache(nextCache)', context);
  assert.deepEqual(directions, [-1, 1]);
  assert.equal(state.cache.pages[state.cursor].pageIndex + 1, 4);
  assert.equal(syncWrites, 0, 'Remote animation must not echo progress back to the App');
  assert.equal(state.turning, false);
}

(async () => {
  await checkFastSync();
  await checkRemoteAnimation();
  await check({}); // App enters the right page: retain 2–3.
  await check({remote: 2});
  await check({before: [page(4), page(5)], remote: 3, expected: [2, 3], renders: 1});
  await check({before: [page(4), page(5)], remote: 2, expected: [2, 3], renders: 1});
  await check({before: [page(4), page(5)], pages: [2, 3, 4, 5].map(n => page(n)), remote: 3, expected: [2, 3], renders: 1});
  await check({remote: 4, expected: [4, 5], renders: 1});
  await check({remote: 1, expected: [1, 2], renders: 1});
  await check({pages: [2, 3, 4, 5].map(n => page(n))}); // Shifted cache window.
  await check({mode: 'mobile', expected: [3, 4], renders: 1});
  await check({mode: 'single', expected: [3, 4], renders: 1});
  await check({bookId: 'other-book', expected: [3, 4], renders: 1});
  await check({before: [page(2), page(3)], pages: [page(3), page(4)], expected: [3, 4], renders: 1});
  await check({before: [page(2, 0), page(1, 1)], pages: [page(2, 0), page(1, 1), page(2, 1)], remote: 1, expected: [2, 1]});
  console.log('PASS: visible spread retention, forward/backward navigation, shifted/missing cache, mode/book changes, chapter boundary, JavaScript syntax.');
})().catch(error => { console.error(error); process.exitCode = 1; });
