'use strict';
// Execute shipped QML JavaScript; replace only OS/process boundaries. No live
// keyring, desktop, server, or credentials are used. Delays are deterministic.
const assert = require('assert');
const {loadQmlObject} = require('./qmljs');
const load = (file, env) => loadQmlObject(file, env);
const quiet = {log() {}, warn() {}};
const Qt = {resolvedUrl: p => p};
const policy = load('js/UrlPolicy.qml');
let failures = 0, completed = false;
process.on('beforeExit', () => {
    if (!completed) { console.error('FAIL: asynchronous suite did not complete'); process.exitCode = 1; }
});
async function test(name, fn) {
    try { await fn(); console.log('PASS ' + name); }
    catch (e) { failures++; console.log('FAIL ' + name + ': ' + e.message); }
}
function transport() {
    const pending = [], files = {}, removed = [], admissions = [];
    let sequence = 0, hold = false, holdPrefix = '';
    const http = load('js/HttpTransport.qml', {Qt, console: quiet, SafePath: {
        getRuntimeSubdir: (_, cb) => hold ? admissions.push(cb) : cb({valid: true}),
        createSecureFile: (_, prefix, content, cb) => {
            const path = '/' + prefix + ++sequence;
            files[path] = content;
            if (prefix === holdPrefix) admissions.push(() => cb({valid: true, path}));
            else cb({valid: true, path});
        }
    }});
    http._requestFactory = {createObject: (_, props) => {
        const p = Object.assign({}, props); pending.push(p); return p;
    }};
    http._cleanupProcessFactory = {createObject: () => ({set command(cmd) { removed.push(...cmd.slice(3)); }})};
    http._readBodyFile = (_, cb) => cb(http.response);
    return {http, pending, files, removed, admissions,
        hold(prefix) { if (prefix) holdPrefix = prefix; else hold = true; },
        reply(p, data) { http.response = JSON.stringify(data); p.onDone(0, '200', '', p.responseBodyPath); }};
}
function panelFixture() {
    const t = transport();
    const api = load('js/SeafileAPI.qml', {HttpTransport: t.http, UrlPolicy: policy});
    const cache = load('js/Cache.qml');
    const auth = load('js/Auth.qml', {Qt}); auth._run = () => Promise.resolve('');
    const transfer = load('js/TransferService.qml', {Qt}); transfer.transfersChanged = () => {};
    const env = {console: quiet, Cache: cache, SeafileAPI: api, Auth: auth, TransferService: transfer,
        UrlPolicy: policy, searchDebounceTimer: {stop() {}}, contextMenu: {close() {}},
        panelConnectionService: {setServerUrl() {}}, Favorites: {clearActiveScope() {}}};
    for (const name of ['createFolder', 'rename', 'confirm', 'share', 'upload', 'history', 'trash', 'settings']) env[name + 'Loader'] = {};
    const panel = load('Panel.qml', env);
    panel.showToast = () => {};
    panel.navigationComplete = panel.navigationPhase = panel.beginNavigationTiming = () => {};
    function session(server, account) {
        api.setBaseUrl(server); api.setToken('synthetic-' + account);
        cache.setScope(server, account); panel.serverUrl = server; panel.state = 'browse';
    }
    session('https://a.invalid', 'alice');
    return {t, api, cache, panel, session};
}
const row = name => [{name, type: 'file', mtime: 1, size: 1}];
(async () => {
    await test('A: delayed A response keeps A URL/auth, never pollutes B cache or UI', () => {
        const {t, cache, panel, session} = panelFixture();
        panel.loadFolder('repo', '/docs'); const a = t.pending[0];
        assert(a.command.includes('https://a.invalid/api2/repos/repo/dir/?p=%2Fdocs'));
        const header = a.command[a.command.indexOf('--config') + 1];
        assert(t.files[header].includes('synthetic-alice'), 'request must capture A credentials');
        panel.changeServerUrl('https://b.invalid', true);
        session('https://b.invalid', 'bob');
        panel.loadFolder('repo', '/docs'); const b = t.pending[1];
        assert(b.command.includes('https://b.invalid/api2/repos/repo/dir/?p=%2Fdocs'));
        assert(t.files[b.command[b.command.indexOf('--config') + 1]].includes('synthetic-bob'));
        t.reply(b, row('B')); t.reply(a, row('A'));
        assert.equal(panel.currentItems[0].name, 'B', 'immediate UI must stay B');
        assert.equal(cache.getFolder('repo', '/docs')[0].name, 'B', 'late A poisoned B cache');
        panel.loadFolder('repo', '/docs');
        assert.equal(panel.currentItems[0].name, 'B'); assert.equal(t.pending.length, 2);
    });
    await test('normal navigation: late same-session folder warms its own cache, not visible folder', () => {
        const {t, cache, panel} = panelFixture();
        panel.loadFolder('repo', '/one'); panel.loadFolder('repo', '/two');
        t.reply(t.pending[1], row('two')); t.reply(t.pending[0], row('one'));
        assert.equal(panel.currentItems[0].name, 'two');
        assert.equal(cache.getFolder('repo', '/one')[0].name, 'one');
        panel.loadFolder('repo', '/one'); assert.equal(panel.currentItems[0].name, 'one');
        assert.equal(t.pending.length, 2);
    });
    await test('Panel guards both library and folder writes even if a cancelled callback is delivered', () => {
        const {api, cache, panel, session} = panelFixture(); let folder, libraries;
        api.listFolder = (_, __, cb) => { folder = cb; };
        api.listLibraries = cb => { libraries = cb; };
        panel.loadFolder('repo', '/'); panel.loadLibraries();
        panel.doLogout(); session('https://b.invalid', 'bob');
        folder(true, row('A')); libraries(true, row('A'));
        assert.equal(cache.getFolder('repo', '/'), null); assert.equal(cache.getLibraries(), null);
        assert.equal(panel.currentItems.length, 0);
    });
    await test('B: download admission delayed across logout must not request old auth', () => {
        let join, requests = 0;
        const service = load('js/TransferService.qml', {Qt, UrlPolicy: policy,
            SafePath: {secureJoin: (_, __, cb) => { join = cb; }},
            HttpTransport: {get() { requests++; }}});
        service.transfersChanged = () => {};
        service.startDownload({name: 'file'}, 'synthetic', 'https://a.invalid', 'repo', '/tmp', '/file');
        service.logoutCleanup(); join({valid: true, path: '/tmp/file'});
        assert.equal(requests, 0, 'old admission started an authenticated request');
        assert.equal(service.transfers.length, 0);
    });
    await test('B: already-started transfer is best-effort cancelled, late exit is retired', () => {
        const service = load('js/TransferService.qml', {Qt, SafePath: {releaseCache() {}}});
        service.transfersChanged = service.runCleanup = service.notify = () => {};
        const process = {pgid: 123, stdout: {text: ''}, destroy() {}};
        const transfer = {id: 1, epoch: service.sessionEpoch, type: 'download', state: 'downloading', process};
        service.transfers = [transfer]; service.logoutCleanup();
        assert.equal(transfer.state, 'cancelling');
        service.handleDownloadExited(0, transfer);
        assert.equal(transfer.state, 'cancelled'); assert.equal(service.transfers.length, 0);
    });
    await test('C: colon/slash paths and resource IDs do not alias', () => {
        const c = load('js/Cache.qml'); c.setScope('https://a.invalid', 'alice');
        const paths = ['/', '/root', '/a/b', '/a:b', '/a/:b', '/a:/b'];
        for (const p of paths) c.setFolder('repo', p, p);
        for (const p of paths) assert.equal(c.getFolder('repo', p), p, 'path collision at ' + p);
        c.setFolder('repo:', '/x', 'one'); c.setFolder('repo', '/:x', 'two');
        assert.equal(c.getFolder('repo:', '/x'), 'one');
    });
    await test('C: root/subtree invalidation respects path boundaries', () => {
        const c = load('js/Cache.qml');
        for (const p of ['/', '/a', '/a/b', '/ab', '/a:b']) c.setFolder('repo', p, p);
        c.invalidatePath('repo', '/a');
        assert.equal(c.getFolder('repo', '/a/b'), null);
        assert.equal(c.getFolder('repo', '/ab'), '/ab');
        assert.equal(c.getFolder('repo', '/a:b'), '/a:b');
        c.invalidatePath('repo', '/'); assert.equal(c.getFolder('repo', '/'), null);
    });
    await test('C: account/server delimiter and repeated-login session isolation', () => {
        const c = load('js/Cache.qml');
        c.setScope('https://a.invalid/x|y', 'z'); c.setLibraries(['A']);
        c.setScope('https://a.invalid/x', 'y|z'); assert.equal(c.getLibraries(), null);
        c.setScope('https://a.invalid', 'alice'); c.setLibraries(['old login']);
        c.setScope('https://a.invalid', 'alice'); assert.equal(c.getLibraries(), null);
    });
    await test('C: same-account re-login never reuses a previous session cache', () => {
        const c = load('js/Cache.qml');
        c.setScope('https://a.invalid', 'alice'); c.setLibraries(['old login']);
        c.setScope('https://a.invalid', 'alice'); assert.equal(c.getLibraries(), null);
    });
    await test('Auth: logout clears memory immediately even behind pending keyring storage', async () => {
        const a = load('js/Auth.qml', {Qt}); let release;
        a._run = () => new Promise(resolve => { release = resolve; });
        const store = a.storeToken('synthetic', 'https://a.invalid', 'alice');
        await Promise.resolve();
        a.clearSession();
        assert.equal(a.getToken(), '', 'logout left cached credentials usable');
        a._run = () => Promise.resolve(''); release(''); await store;
        assert.equal(a.getToken(), '');
    });
    for (const stage of ['', 'curl_resp', 'curl_hdr', 'curl_body']) {
        await test('HTTP admission revoked at ' + (stage || 'runtime directory') + '; private files cleaned', () => {
            const t = transport(); t.hold(stage);
            const api = load('js/SeafileAPI.qml', {HttpTransport: t.http, UrlPolicy: policy});
            api.setBaseUrl('https://a.invalid'); api.setToken('synthetic');
            t.http.post('https://a.invalid/api2/repos/', {Authorization: 'Token synthetic'}, 'body', () => assert.fail('stale callback'));
            api.setToken('');
            t.admissions[0]({valid: true});
            assert.equal(t.pending.length, 0, 'old HTTP process launched');
            for (const file of Object.keys(t.files)) assert(t.removed.includes(file), 'orphaned private file');
        });
    }
    await test('server change clears old token and suppresses direct API mutation continuation', () => {
        const {t, api} = panelFixture(); let applied = false;
        api.deleteFile('repo', '/file', api.token, () => { applied = true; });
        const pending = t.pending[0];
        api.setBaseUrl('https://b.invalid');
        assert.equal(api.token, '', 'A token remained configured on B');
        t.reply(pending, {success: true}); assert.equal(applied, false);
        let rejected = false;
        api.listLibraries(success => { rejected = !success; });
        assert(rejected); assert.equal(t.pending.length, 1);
    });
    await test('logout while login is pending suppresses authentication continuation', () => {
        const {t, api} = panelFixture(); let applied = false;
        api.setToken('');
        api.auth('alice', 'synthetic-password', () => { applied = true; });
        api.setToken('');
        t.reply(t.pending[0], {token: 'synthetic-result'});
        assert.equal(applied, false);
    });
    await test('late old transfer completion cannot invalidate cache, notify, or log B out', () => {
        const {panel, cache} = panelFixture();
        cache.setFolder('repo', '/', row('B'));
        panel.showToast = panel.refresh = panel.doLogout = () => assert.fail('old transfer affected B');
        panel.handleTransferCompletion({epoch: -1, type: 'upload', state: 'completed', repoId: 'repo', destUploadPath: '/'});
        panel.handleTransferCompletion({epoch: -1, state: 'auth_failed'});
        assert.equal(cache.getFolder('repo', '/')[0].name, 'B');
    });
    for (const crossOrigin of [false, true]) {
        for (const stage of ['link', 'header', 'config']) {
            if (crossOrigin && stage === 'header') continue;
            await test('download logout during ' + stage + (crossOrigin ? ' cross-origin' : ' same-origin'), () => {
                let release, launches = 0;
                const safe = {secureJoin: (_, name, cb) => cb({valid: true, path: '/tmp/' + name}),
                    createSecureFile: (_, prefix, __, cb) => {
                        const done = () => cb({valid: true, path: '/private/' + prefix});
                        if ((stage === 'header' && prefix === 'seafile_auth') || (stage === 'config' && prefix === 'seafile_curl')) release = done;
                        else done();
                    }};
                const service = load('js/TransferService.qml', {Qt, UrlPolicy: policy, SafePath: safe,
                    HttpTransport: {get: (_, __, cb) => {
                        const done = () => cb(true, 'https://' + (crossOrigin ? 'cdn' : 'a') + '.invalid/file', null, 200);
                        if (stage === 'link') release = done; else done();
                    }}});
                service.transfersChanged = service.runCleanup = () => {};
                service.downloadProcessComponent = {createObject() { launches++; return {}; }};
                service.startDownload({name: 'file'}, 'synthetic', 'https://a.invalid', 'repo', '/tmp', '/file');
                assert.equal(typeof release, 'function'); service.logoutCleanup(); release();
                assert.equal(launches, 0); assert.equal(service.transfers.length, 0);
            });
        }
    }
    await test('Auth: delayed startup lookup cannot restore logged-out memory', async () => {
        const a = load('js/Auth.qml', {Qt}); let release;
        let lookups = 0;
        a._lookup = () => ++lookups === 1 ? new Promise(resolve => { release = resolve; }) : Promise.resolve('synthetic');
        a._run = () => Promise.resolve('');
        const startup = a.isAuthenticated(); await Promise.resolve();
        const logout = a.clearSession(); release('synthetic');
        assert.equal(await startup, false); await logout;
        assert.equal(a.getToken(), ''); assert.equal(a.getServerUrl(), '');
    });
    await test('Auth: queued store/clear/store preserves latest memory and keyring order', async () => {
        const a = load('js/Auth.qml', {Qt}); const disk = {};
        a._run = (cmd, value) => { disk[cmd[cmd.length - 1]] = value || ''; return Promise.resolve(''); };
        const first = a.storeToken('synthetic-A', 'https://a.invalid', 'alice');
        const clear = a.clearSession();
        const last = a.storeToken('synthetic-B', 'https://b.invalid', 'bob');
        await Promise.all([first, clear, last]);
        assert(a.getToken() === 'synthetic-B'); assert(disk[a.keyToken] === 'synthetic-B');
        assert.equal(a.getEmail(), 'bob'); assert.equal(disk[a.keyServer], 'https://b.invalid');
    });
    await test('libraries, TTL, repo isolation, and explicit root invalidation', () => {
        const c = load('js/Cache.qml');
        c.setScope('https://a.invalid', 'alice'); c.setLibraries(['library']);
        c.setFolder('r1', '/', ['root']); c.setFolder('r1', '/nested', ['nested']); c.setFolder('r2', '/', ['other']);
        c.invalidatePath('r1', '/'); assert.equal(c.getFolder('r1', '/'), null);
        assert.equal(c.getFolder('r1', '/nested'), null); assert.equal(c.getFolder('r2', '/')[0], 'other');
        c.invalidateRepo('global'); assert.equal(c.getLibraries(), null);
        c.set('ttl', 'value', -1); assert.equal(c.get('ttl'), null);
    });
    await test('queued upload and stat admission cannot launch after logout', () => {
        let release, requests = 0;
        const service = load('js/TransferService.qml', {Qt, UrlPolicy: policy,
            SafePath: {sanitizeBasename: name => ({valid: true, sanitized: name})},
            HttpTransport: {get() { requests++; }}});
        service.transfersChanged = () => {}; service.maxConcurrentUploads = 1;
        service._statFactory = {createObject: (_, props) => {
            release = props.onDone; return {destroy() {}};
        }};
        const first = service.startUpload('/tmp/a', 'synthetic', 'https://a.invalid', 'repo', '/', 'a');
        const second = service.startUpload('/tmp/b', 'synthetic', 'https://a.invalid', 'repo', '/', 'b');
        assert.equal(first.state, 'validating'); assert.equal(second.state, 'queued');
        service.logoutCleanup(); release('81a4:10');
        assert.equal(requests, 0); assert.equal(service.transfers.length, 0);
        assert.equal(first.state, 'cancelled'); assert.equal(second.state, 'cancelled');
        assert.equal(first.token, undefined); assert.equal(second.token, undefined);
    });
    await test('cache stays bounded when entries share a timestamp', () => {
        const c = load('js/Cache.qml', {Date: {now: () => 100}}); c.maxEntries = 2;
        for (const p of ['/one', '/two', '/three']) c.setFolder('repo', p, p);
        assert.equal(Object.keys(c.cache).length, 2);
    });
    await test('generic cache entries coexist with folder invalidation', () => {
        const c = load('js/Cache.qml'); c.set('generic', 'value');
        c.setFolder('repo', '/', ['root']); c.invalidatePath('repo', '/');
        assert.equal(c.get('generic'), 'value');
    });
    completed = true;
    process.exitCode = failures ? 1 : 0;
})();
