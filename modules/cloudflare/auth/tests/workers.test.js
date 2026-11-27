// Behaviour tests for the three Worker scripts in ../cf-workers.
//
// Run from the repository root:
//   node --test 'modules/cloudflare/auth/**/*.test.js'
//
// Each script runs unmodified in a node:vm context that provides Node's real
// Response, Headers, Request, URL and atob. Only addEventListener, fetch and the
// secret globals on self are stubbed. The stub fetch returns responses whose
// headers throw on mutation, as fetch() responses do in Workers, so a script
// that sets a header without copying the response first fails here.

'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { describe, test } = require('node:test');
const vm = require('node:vm');

const WORKERS_DIR = path.join(__dirname, '..', 'cf-workers');
const USER = 'staging-user';
const PASSWORD = 'staging-password';
const HSTS = 'max-age=31536000';

const SCRIPTS = [
    { file: 'auth-noindex-worker.js', auth: true, noindex: true },
    { file: 'auth-only-worker.js', auth: true, noindex: false },
    { file: 'noindex-only-worker.js', auth: false, noindex: true },
];

// Make a response's headers behave like those of a fetch() response in Workers.
function immutableHeaders(response) {
    for (const method of ['set', 'append', 'delete']) {
        response.headers[method] = () => {
            throw new TypeError(`Can't modify immutable headers (${method})`);
        };
    }
    return response;
}

function originResponse(init = {}) {
    return immutableHeaders(
        new Response('origin body', {
            status: 200,
            headers: { 'Content-Type': 'text/plain' },
            ...init,
        })
    );
}

// Load a script into a fresh context and return a function that dispatches a
// fetch event to it, plus the requests the script passed to fetch.
function loadWorker(file, origin = () => originResponse()) {
    const fetchCalls = [];
    let handler;
    const context = {
        Response,
        Headers,
        Request,
        URL,
        atob,
        shared_auth_user: USER,
        shared_auth_password: PASSWORD,
        addEventListener(type, listener) {
            assert.equal(type, 'fetch');
            handler = listener;
        },
        async fetch(request) {
            fetchCalls.push(request);
            return origin(request);
        },
    };
    context.self = context;
    vm.createContext(context);
    vm.runInContext(fs.readFileSync(path.join(WORKERS_DIR, file), 'utf8'), context, {
        filename: file,
    });
    assert.equal(typeof handler, 'function', `${file} registers a fetch listener`);

    async function dispatch(request) {
        let responded;
        handler({
            request,
            respondWith(promise) {
                responded = promise;
            },
        });
        assert.ok(responded, 'the listener calls respondWith');
        return await responded;
    }

    return { dispatch, fetchCalls };
}

function basic(credentials) {
    return `Basic ${Buffer.from(credentials).toString('base64')}`;
}

function get(url, headers = {}, method = 'GET') {
    return new Request(url, { method, headers });
}

function authorized(url, method = 'GET') {
    return get(url, { Authorization: basic(`${USER}:${PASSWORD}`) }, method);
}

// A request that reaches the origin through the script: credentials when the
// script asks for them.
function originRequest(script, url) {
    return script.auth ? authorized(url) : get(url);
}

function assertUnauthorized(response) {
    assert.equal(response.status, 401);
    assert.equal(response.headers.get('WWW-Authenticate'), 'Basic realm="Secure Area"');
}

for (const script of SCRIPTS) {
    describe(script.file, () => {
        describe('http to https redirect', () => {
            for (const method of ['GET', 'HEAD']) {
                test(`http ${method} answers 301 to the https URL`, async () => {
                    const worker = loadWorker(script.file);
                    const response = await worker.dispatch(
                        get('http://staging.example.com/a/b?c=1&d=two', {}, method)
                    );
                    assert.equal(response.status, 301);
                    assert.equal(response.headers.get('Location'), 'https://staging.example.com/a/b?c=1&d=two');
                    assert.equal(response.headers.get('WWW-Authenticate'), null);
                    assert.equal(response.headers.get('Strict-Transport-Security'), null);
                    assert.equal(worker.fetchCalls.length, 0);
                });
            }

            for (const method of ['POST', 'PUT', 'OPTIONS', 'DELETE', 'PATCH']) {
                test(`http ${method} answers 308 to the https URL`, async () => {
                    const worker = loadWorker(script.file);
                    const response = await worker.dispatch(
                        get('http://staging.example.com/api/items?page=2', {}, method)
                    );
                    assert.equal(response.status, 308);
                    assert.equal(response.headers.get('Location'), 'https://staging.example.com/api/items?page=2');
                    assert.equal(response.headers.get('WWW-Authenticate'), null);
                    assert.equal(response.headers.get('Strict-Transport-Security'), null);
                    assert.equal(worker.fetchCalls.length, 0);
                });
            }

            test('the redirect clears a non-standard port', async () => {
                const worker = loadWorker(script.file);
                const response = await worker.dispatch(get('http://h.example:8080/x?y=1'));
                assert.equal(response.status, 301);
                assert.equal(response.headers.get('Location'), 'https://h.example/x?y=1');
                assert.equal(worker.fetchCalls.length, 0);
            });

            test('http with valid credentials is still redirected, not forwarded', async () => {
                const worker = loadWorker(script.file);
                const response = await worker.dispatch(authorized('http://staging.example.com/x'));
                assert.equal(response.status, 301);
                assert.equal(response.headers.get('Location'), 'https://staging.example.com/x');
                assert.equal(worker.fetchCalls.length, 0);
            });
        });

        describe('/.well-known/ bypass', () => {
            test('over http it reaches the origin with no redirect, auth or HSTS', async () => {
                const worker = loadWorker(script.file);
                const request = get('http://staging.example.com/.well-known/acme-challenge/x');
                const response = await worker.dispatch(request);
                assert.equal(response.status, 200);
                assert.equal(await response.text(), 'origin body');
                assert.equal(response.headers.get('Location'), null);
                assert.equal(response.headers.get('WWW-Authenticate'), null);
                assert.equal(response.headers.get('Strict-Transport-Security'), null);
                assert.equal(response.headers.get('X-Robots-Tag'), null);
                assert.equal(worker.fetchCalls.length, 1);
                assert.equal(worker.fetchCalls[0], request);
            });

            test('over https it reaches the origin with no auth and gets HSTS', async () => {
                const worker = loadWorker(script.file);
                const request = get('https://staging.example.com/.well-known/acme-challenge/x');
                const response = await worker.dispatch(request);
                assert.equal(response.status, 200);
                assert.equal(response.headers.get('WWW-Authenticate'), null);
                assert.equal(response.headers.get('Strict-Transport-Security'), HSTS);
                assert.equal(response.headers.get('X-Robots-Tag'), null);
                assert.equal(worker.fetchCalls.length, 1);
                assert.equal(worker.fetchCalls[0], request);
            });

            test('the origin status is kept, not replaced by an auth response', async () => {
                const worker = loadWorker(script.file, () => originResponse({ status: 404 }));
                const response = await worker.dispatch(
                    get('http://staging.example.com/.well-known/acme-challenge/unknown')
                );
                assert.equal(response.status, 404);
                assert.equal(worker.fetchCalls.length, 1);
            });
        });

        describe('HSTS', () => {
            test('an https response from the origin gets max-age=31536000', async () => {
                const worker = loadWorker(script.file);
                const response = await worker.dispatch(originRequest(script, 'https://staging.example.com/'));
                assert.equal(response.status, 200);
                assert.equal(response.headers.get('Strict-Transport-Security'), HSTS);
            });

            test('an HSTS value sent by the origin is kept', async () => {
                const originHsts = 'max-age=600; includeSubDomains';
                const worker = loadWorker(script.file, () =>
                    originResponse({ headers: { 'Strict-Transport-Security': originHsts } })
                );
                const response = await worker.dispatch(originRequest(script, 'https://staging.example.com/'));
                assert.equal(response.headers.get('Strict-Transport-Security'), originHsts);
            });
        });

        describe('protocol switches', () => {
            test('a 101 response from the origin is returned as the same object', async () => {
                const switching = originResponse();
                Object.defineProperty(switching, 'status', { value: 101 });
                const worker = loadWorker(script.file, () => switching);
                const response = await worker.dispatch(originRequest(script, 'https://staging.example.com/socket'));
                assert.equal(response, switching);
            });

            test('a response carrying a webSocket is returned as the same object', async () => {
                const upgraded = originResponse();
                upgraded.webSocket = {};
                const worker = loadWorker(script.file, () => upgraded);
                const response = await worker.dispatch(originRequest(script, 'https://staging.example.com/socket'));
                assert.equal(response, upgraded);
            });
        });

        describe('origin response', () => {
            test('the origin status, body and headers pass through', async () => {
                const worker = loadWorker(script.file, () =>
                    originResponse({ status: 201, headers: { 'Content-Type': 'application/json' } })
                );
                const response = await worker.dispatch(originRequest(script, 'https://staging.example.com/x'));
                assert.equal(response.status, 201);
                assert.equal(response.headers.get('Content-Type'), 'application/json');
                assert.equal(await response.text(), 'origin body');
                assert.equal(worker.fetchCalls.length, 1);
            });

            test(
                script.noindex
                    ? 'the origin response gets X-Robots-Tag: noindex, nofollow'
                    : 'the origin response gets no X-Robots-Tag',
                async () => {
                    const worker = loadWorker(script.file);
                    const response = await worker.dispatch(originRequest(script, 'https://staging.example.com/x'));
                    assert.equal(
                        response.headers.get('X-Robots-Tag'),
                        script.noindex ? 'noindex, nofollow' : null
                    );
                }
            );
        });

        if (!script.auth) {
            return;
        }

        describe('basic auth', () => {
            test('a request without credentials answers 401 with HSTS', async () => {
                const worker = loadWorker(script.file);
                const response = await worker.dispatch(get('https://staging.example.com/'));
                assertUnauthorized(response);
                assert.equal(response.headers.get('Strict-Transport-Security'), HSTS);
                assert.equal(worker.fetchCalls.length, 0);
            });

            test('correct credentials reach the origin', async () => {
                const worker = loadWorker(script.file);
                const request = authorized('https://staging.example.com/x?y=1');
                const response = await worker.dispatch(request);
                assert.equal(response.status, 200);
                assert.equal(await response.text(), 'origin body');
                assert.equal(worker.fetchCalls.length, 1);
                assert.equal(worker.fetchCalls[0], request);
            });

            for (const [label, credentials] of [
                ['a wrong password', `${USER}:wrong`],
                ['a wrong user', `someone:${PASSWORD}`],
            ]) {
                test(`${label} answers 401 with HSTS`, async () => {
                    const worker = loadWorker(script.file);
                    const response = await worker.dispatch(
                        get('https://staging.example.com/', { Authorization: basic(credentials) })
                    );
                    assertUnauthorized(response);
                    assert.equal(response.headers.get('Strict-Transport-Security'), HSTS);
                    assert.equal(worker.fetchCalls.length, 0);
                });
            }

            for (const authorization of [
                'Basic a',
                'Basic !!!',
                'Basic',
                basic('no-colon'),
                'Bearer token',
            ]) {
                test(`a malformed Authorization header "${authorization}" answers 401`, async () => {
                    const worker = loadWorker(script.file);
                    const response = await worker.dispatch(
                        get('https://staging.example.com/', { Authorization: authorization })
                    );
                    assertUnauthorized(response);
                    assert.equal(worker.fetchCalls.length, 0);
                });
            }

            test('.well-known in the query string does not skip auth', async () => {
                const worker = loadWorker(script.file);
                const response = await worker.dispatch(get('https://h.example/x?p=/.well-known/'));
                assertUnauthorized(response);
                assert.equal(worker.fetchCalls.length, 0);
            });

            test('a path that only starts like .well-known does not skip auth', async () => {
                const worker = loadWorker(script.file);
                const response = await worker.dispatch(get('https://h.example/.well-known-not/x'));
                assertUnauthorized(response);
                assert.equal(worker.fetchCalls.length, 0);
            });
        });
    });
}
