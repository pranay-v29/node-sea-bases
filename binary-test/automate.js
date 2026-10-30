// One BrowserStack Automate session through the BrowserStackLocal tunnel under test.
//
// Serves a page with a unique token on 127.0.0.1:$LOCAL_PORT, opens one remote
// Chrome / Windows 11 session with local=true + the tunnel's localIdentifier,
// loads http://localhost:$LOCAL_PORT/ and asserts the token came back. The
// session is marked passed/failed via the browserstack_executor script.
//
// Env: BROWSERSTACK_USERNAME, BROWSERSTACK_ACCESS_KEY, LOCAL_IDENTIFIER,
//      BUILD_NAME, SESSION_NAME, LOCAL_PORT (default 8099).
'use strict';

const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const { Builder, until } = require('selenium-webdriver');

const required = ['BROWSERSTACK_USERNAME', 'BROWSERSTACK_ACCESS_KEY', 'LOCAL_IDENTIFIER'];
for (const k of required) {
  if (!process.env[k]) {
    console.error(`missing env ${k}`);
    process.exit(2);
  }
}

const port = Number(process.env.LOCAL_PORT || 8099);
const token = 'bslocal-' + crypto.randomBytes(8).toString('hex');
const html = `<!doctype html><html><head><title>${token}</title></head>` +
  `<body><h1 id="token">${token}</h1></body></html>`;

function summary(line) {
  console.log(line);
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, line + '\n');
}

async function main() {
  let hits = 0;
  const server = http.createServer((req, res) => {
    hits++;
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(html);
  });
  await new Promise((resolve, reject) => server.listen(port, '127.0.0.1', resolve).on('error', reject));
  console.log(`local server on http://127.0.0.1:${port}/`);

  const caps = {
    browserName: 'Chrome',
    browserVersion: 'latest',
    'bstack:options': {
      os: 'Windows',
      osVersion: '11',
      local: 'true',
      localIdentifier: process.env.LOCAL_IDENTIFIER,
      projectName: 'BrowserStackLocal binary test',
      buildName: process.env.BUILD_NAME || 'local-binary-test',
      sessionName: process.env.SESSION_NAME || 'local-binary-test',
      userName: process.env.BROWSERSTACK_USERNAME,
      accessKey: process.env.BROWSERSTACK_ACCESS_KEY,
      seleniumVersion: '4.0.0',
    },
  };

  let driver;
  let passed = false;
  let reason = '';
  try {
    driver = await new Builder().usingServer('https://hub.browserstack.com/wd/hub').withCapabilities(caps).build();
    const sessionId = (await driver.getSession()).getId();
    summary(`| automate session id | \`${sessionId}\` |`);

    await driver.get(`http://localhost:${port}/`);
    await driver.wait(until.titleIs(token), 30000);
    const body = await driver.findElement({ id: 'token' }).getText();
    if (body !== token) throw new Error(`token mismatch in body: got '${body}'`);
    if (hits < 1) throw new Error('page loaded but local server saw no request');
    passed = true;
    reason = 'token served through tunnel';
  } catch (e) {
    reason = (e && e.message ? e.message : String(e)).slice(0, 200);
    console.error(e);
  } finally {
    if (driver) {
      const status = { action: 'setSessionStatus', arguments: { status: passed ? 'passed' : 'failed', reason } };
      try {
        await driver.executeScript('browserstack_executor: ' + JSON.stringify(status));
      } catch (e) {
        console.error('setSessionStatus failed:', e.message);
      }
      try { await driver.quit(); } catch (e) { /* ignore */ }
    }
    server.close();
  }

  summary(`| automate result | ${passed ? 'PASSED' : 'FAILED'}: ${reason.replace(/\|/g, '/')} |`);
  process.exit(passed ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
