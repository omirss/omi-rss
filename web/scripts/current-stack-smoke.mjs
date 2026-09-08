// Builds the real image and runs both Compose variants on disposable data.
// Usage: node scripts/current-stack-smoke.mjs /absolute/evidence/directory
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import postgres from "postgres";
import { parse } from "yaml";

const web = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const root = resolve(web, "..");
const evidence = process.argv[2];
assert(evidence?.startsWith("/"), "Pass an existing absolute evidence directory");
const runId = `omi-smoke-${Date.now()}`;
const image = `${runId}:test`;
let checks = 0;
function pass(message) { console.log(`PASS ${++checks}: ${message}`); }
function docker(args, options = {}) {
  return execFileSync("docker", args, { cwd: root, encoding: "utf8", timeout: 900000,
    maxBuffer: 32 * 1024 * 1024, ...options });
}
async function freePort() {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}
async function until(check, timeout = 30000) {
  const deadline = Date.now() + timeout;
  do {
    if (await check()) return;
    await new Promise((resolve) => setTimeout(resolve, 250));
  } while (Date.now() < deadline);
  throw new Error("Timed out waiting for smoke condition");
}

try {
  docker(["build", "-t", image, "-f", resolve(web, "Dockerfile"), web], { stdio: "inherit" });
  for (const variant of ["default", "production"]) {
    const project = `${runId}-${variant}`;
    const filename = variant === "default" ? "docker-compose.yml" : "docker-compose.prod.yml";
    const env = { ...process.env };
    for (const key of ["JWT_SECRET", "POSTGRES_PASSWORD", "SMTP_HOST", "SMTP_PORT", "SMTP_USER", "SMTP_PASS", "EMAIL_FROM", "FRONTEND_URL"])
      delete env[key];
    if (variant === "production") {
      env.JWT_SECRET = "synthetic-smoke-secret-not-for-production-use";
      env.POSTGRES_PASSWORD = "synthetic-smoke-password";
    }
    const config = parse(docker(["compose", "--env-file", "/dev/null", "-f", filename, "config"], { env }));
    const webPort = await freePort();
    const pgPort = await freePort();
    const mailPort = await freePort();
    const base = `http://127.0.0.1:${webPort}`;
    const mail = `http://127.0.0.1:${mailPort}`;
    config.name = project;
    config.networks = { default: { internal: true } };
    for (const name of Object.keys(config.volumes)) config.volumes[name] = {};
    for (const service of Object.values(config.services)) {
      delete service.container_name;
      service.restart = "no";
      delete service.build;
    }
    for (const name of ["web", "worker"]) config.services[name].image = image;
    config.services.web.ports = [`127.0.0.1:${webPort}:3000`];
    config.services.postgres.ports = [`127.0.0.1:${pgPort}:5432`];
    config.services.web.environment.ALLOW_REGISTRATION = "false";
    config.services.web.environment.BCRYPT_ROUNDS = "4";
    config.services.web.environment.FRONTEND_URL = base;
    Object.assign(config.services.worker.environment, { SMTP_HOST: "mailpit", SMTP_PORT: "1025" });
    config.services.mailpit = { image: "axllent/mailpit:latest", ports: [`127.0.0.1:${mailPort}:8025`] };
    const composeFile = resolve(evidence, `${variant}-compose.json`);
    writeFileSync(composeFile, JSON.stringify(config, null, 2));
    const compose = (...args) => docker(["compose", "-p", project, "-f", composeFile, ...args]);
    const password = config.services.postgres.environment.POSTGRES_PASSWORD;
    const db = postgres(`postgres://omi_rss:${password}@127.0.0.1:${pgPort}/omi_rss`, { max: 4 });
    async function request(path, body, token, method = "POST") {
      const response = await fetch(base + path, {
        method: body === undefined ? "GET" : method,
        headers: { "Content-Type": "application/json", ...(token ? { Authorization: token } : {}) },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(7000),
      });
      const text = await response.text();
      let result;
      try { result = JSON.parse(text); } catch { result = text; }
      return { status: response.status, body: result };
    }
    try {
      console.log(`Starting ${project}; loopback ports web=${webPort}, pg=${pgPort}, mail=${mailPort}`);
      console.log(compose("up", "-d", "--wait", "--wait-timeout", "180"));
      // /health, not /ready, was probed by Compose: this is the first auth use.
      const attempts = await Promise.all(["first", "second", "third"].map((username) =>
        request("/api/auth/register", { username, password: "synthetic-password" })));
      assert.deepEqual(attempts.map((x) => x.status).sort(), [201, 403, 403]);
      assert.equal((await db`select count(*)::int as n from users`)[0].n, 1);
      pass(`${variant}: cold concurrent closed bootstrap yields exactly one 201 and two 403, one DB row`);
      assert.equal((await request("/ready")).status, 200);
      pass(`${variant}: PostgreSQL + Redis ready`);
      const account = attempts.find((x) => x.status === 201).body;
      const token = `Bearer ${account.token}`;
      const userId = account.user.id;
      assert.equal((await request("/api/users/me", { email: "invalid" }, token, "PATCH")).status, 400);
      pass(`${variant}: invalid email rejected`);
      assert.equal((await request("/api/users/me", { email: "smoke@example.invalid" }, token, "PATCH")).status, 200);
      const [emailState] = await db`select email_verified, email_verification_token from users where id=${userId}`;
      assert.equal(emailState.email_verified, false);
      assert.match(emailState.email_verification_token, /^[a-f0-9]{64}$/);
      await until(async () => {
        const messages = await (await fetch(mail + "/api/v1/messages")).json();
        return messages.total === 1;
      });
      pass(`${variant}: actual worker starts and delivers add-email verification to isolated Mailpit`);
      assert.equal((await request(`/api/auth/verify-email/${emailState.email_verification_token}`)).status, 200);
      assert.equal((await request("/api/users/me", { email: "smoke@example.invalid", firstName: "Kept" }, token, "PATCH")).status, 200);
      const [kept] = await db`select email_verified, email_verification_token from users where id=${userId}`;
      assert.equal(kept.email_verified, true);
      assert.equal(kept.email_verification_token, null);
      pass(`${variant}: unchanged verified email retains verification`);
      const [foreign] = await db`insert into users(username) values('foreign') returning id`;
      const [feed] = await db`insert into feeds(user_id,url,title,is_active) values(${userId},'https://example.invalid/feed','Smoke',false) returning id`;
      const [article] = await db`insert into articles(feed_id,guid,url,title,content,content_extracted,enclosures)
        values(${feed.id},'smoke','https://example.invalid/article','Smoke','<p>Original body</p>','<p>Extracted body</p>',
        '[{"url":"https://example.invalid/podcast.mp3","type":"audio/mpeg"}]'::jsonb) returning id`;
      const login = await fetch(base + "/api/greader/accounts/ClientLogin", { method: "POST",
        body: new URLSearchParams({ Email: account.user.username, Passwd: "synthetic-password" }) });
      assert.equal(login.status, 200);
      const gt = `GoogleLogin auth=${(await login.text()).match(/Auth=(.+)/)[1]}`;
      const stream = await request("/api/greader/reader/api/0/stream/contents?output=json", undefined, gt);
      assert.equal(stream.status, 200);
      assert.equal(stream.body.items[0].summary.content, "<p>Extracted body</p>");
      assert.equal(stream.body.items[0].enclosure[0].type, "audio/mpeg");
      const detail = await request(`/api/articles/${article.id}`, undefined, token);
      assert.equal(detail.status, 200);
      pass(`${variant}: greader selects extracted body from real SQL and preserves enclosure metadata`);
      const folders = await db`insert into folders(user_id,name,position) values
        (${userId},'one',1),(${userId},'two',2),(${userId},'three',3),(${foreign.id},'foreign',9) returning id,name`;
      const id = (name) => folders.find((f) => f.name === name).id;
      const before = await db`select id,position,updated_at from folders order by id`;
      await db.unsafe(`CREATE FUNCTION smoke_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
        IF NEW.name = 'two' THEN RAISE EXCEPTION 'smoke injected failure'; END IF; RETURN NEW; END $$`);
      await db.unsafe("CREATE TRIGGER smoke_fail BEFORE UPDATE ON folders FOR EACH ROW EXECUTE FUNCTION smoke_fail()");
      assert.equal((await request("/api/folders/reorder", { folderIds: [id("three"), id("two"), id("one")] }, token)).status, 500);
      assert.deepEqual(Array.from(await db`select id,position,updated_at from folders order by id`), Array.from(before));
      pass(`${variant}: injected second reorder failure rolls back every position and timestamp`);
      await db.unsafe("DROP TRIGGER smoke_fail ON folders");
      assert.equal((await request("/api/folders/reorder", { folderIds: [id("foreign"), id("three"), id("two"), id("one")] }, token)).status, 200);
      const positions = await db`select name,position from folders order by name`;
      assert.deepEqual(Array.from(positions), [
        { name: "foreign", position: 9 }, { name: "one", position: 3 },
        { name: "three", position: 1 }, { name: "two", position: 2 },
      ]);
      pass(`${variant}: successful reorder is user-scoped`);
      console.log(compose("stop", "redis"));
      const started = Date.now();
      assert.equal((await request("/ready")).status, 503);
      assert(Date.now() - started < 5000);
      assert.equal((await request("/api/auth/login", { emailOrUsername: account.user.username, password: "synthetic-password" })).status, 503);
      assert.equal((await request("/health")).status, 200);
      pass(`${variant}: Redis outage gives bounded readiness 503 and fail-closed auth; liveness stays 200`);
      console.log(compose("start", "redis"));
      await until(async () => (await request("/ready")).status === 200);
      console.log(compose("stop", "postgres"));
      const pgStarted = Date.now();
      assert.equal((await request("/ready")).status, 503);
      assert(Date.now() - pgStarted < 5000);
      pass(`${variant}: PostgreSQL outage gives bounded readiness 503`);
    } finally {
      await db.end({ timeout: 2 });
      try { writeFileSync(resolve(evidence, `${variant}-containers.log`), compose("logs", "--no-color")); }
      finally { console.log(compose("down", "--volumes", "--remove-orphans", "--timeout", "10")); }
    }
  }
  console.log(`All ${checks} isolated Compose/API checks passed.`);
} finally {
  docker(["image", "rm", image], { stdio: "inherit" });
}
