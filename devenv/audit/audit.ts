import { spawn, spawnSync } from "node:child_process";
import { createWriteStream, existsSync, mkdirSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";

const usage = `usage:
  audit new <host> <service> <slug>   create audit/<host>/<service>/<date>-<slug>.ts
  audit run <script> [args...]        run a script, appending its output to <script>.log
  audit list [filter]                 list scripts, newest first`;

const fail = (message: string): never => {
  console.error(message);
  process.exit(1);
};

const repositoryRoot = (): string => {
  // DEVENV_ROOT is the project that imported this module, which is the repo
  // the script belongs in even when the module itself came from another one.
  const devenvRoot = process.env["DEVENV_ROOT"];
  if (devenvRoot) {
    return devenvRoot;
  }

  const git = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" });
  return git.status === 0 ? git.stdout.trim() : fail("audit: not inside a git repository");
};

const auditDirectory = (): string => join(repositoryRoot(), "audit");

// Local rather than UTC: the date in the name is the day as Jamie lived it.
const today = (): string => {
  const now = new Date();
  const pad = (value: number): string => String(value).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
};

const segment = /^[a-z0-9]+(?:[.-][a-z0-9]+)*$/;

const template = `// What this changes, and why it was needed. Someone reading the audit trail
// later has only this paragraph and the log beside it to go on.
//
// Dry run by default. Pass --apply to make the change.

const apply = process.argv.includes("--apply");

const main = async (): Promise<void> => {
  console.log(apply ? "applying" : "dry run, pass --apply to make changes");
};

await main();
`;

const create = (host: string | undefined, service: string | undefined, slug: string | undefined): void => {
  if (!host || !service || !slug) {
    fail(usage);
    return;
  }

  const invalid = [host, service, slug].find((part) => !segment.test(part));
  if (invalid !== undefined) {
    fail(`audit: "${invalid}" should be lowercase words joined by hyphens`);
  }

  const directory = join(auditDirectory(), host, service);
  const path = join(directory, `${today()}-${slug}.ts`);
  if (existsSync(path)) {
    fail(`audit: ${relative(process.cwd(), path)} already exists`);
  }

  mkdirSync(directory, { recursive: true });
  writeFileSync(path, template);
  console.log(relative(process.cwd(), path));
};

const commitOf = (path: string): string => {
  const options = { cwd: dirname(path), encoding: "utf8" } as const;
  const head = spawnSync("git", ["rev-parse", "--short", "HEAD"], options);
  if (head.status !== 0) {
    return "no commit";
  }

  const dirty = spawnSync("git", ["status", "--porcelain", "--", basename(path)], options);
  return `${head.stdout.trim()}${dirty.stdout.trim() === "" ? "" : ", script uncommitted"}`;
};

const run = (script: string | undefined, args: readonly string[]): void => {
  if (!script) {
    fail(usage);
    return;
  }

  const path = resolve(script);
  if (!path.endsWith(".ts") || !existsSync(path)) {
    fail(`audit: no such script: ${script}`);
  }

  const log = createWriteStream(path.replace(/\.ts$/, ".log"), { flags: "a" });
  const command = ["audit run", relative(repositoryRoot(), path), ...args].join(" ");
  log.write(`\n=== ${new Date().toISOString()}  ${command}  (node ${process.version}, ${commitOf(path)})\n`);

  // The child's cwd is the script's directory so any file it writes lands in
  // the trail beside it.
  const child = spawn(process.execPath, [path, ...args], {
    cwd: dirname(path),
    stdio: ["inherit", "pipe", "pipe"],
  });

  child.stdout.on("data", (chunk: Buffer) => {
    process.stdout.write(chunk);
    log.write(chunk);
  });
  child.stderr.on("data", (chunk: Buffer) => {
    process.stderr.write(chunk);
    log.write(chunk);
  });
  child.on("close", (code, signal) => {
    const status = signal === null ? `exit ${code ?? 0}` : `killed by ${signal}`;
    log.end(`=== ${status}\n`, () => process.exit(code ?? 1));
  });
};

const scriptsUnder = (directory: string): readonly string[] =>
  !existsSync(directory)
    ? []
    : readdirSync(directory).flatMap((name) => {
        const path = join(directory, name);
        return statSync(path).isDirectory() ? scriptsUnder(path) : name.endsWith(".ts") ? [path] : [];
      });

const list = (filter: string | undefined): void => {
  const root = auditDirectory();
  scriptsUnder(root)
    .map((path) => relative(root, path))
    .filter((path) => filter === undefined || path.includes(filter))
    .toSorted((left, right) => basename(right).localeCompare(basename(left)))
    .forEach((path) => console.log(path));
};

const [command, ...rest] = process.argv.slice(2);

switch (command) {
  case "new":
    create(rest[0], rest[1], rest[2]);
    break;
  case "run":
    run(rest[0], rest.slice(1));
    break;
  case "list":
    list(rest[0]);
    break;
  default:
    fail(usage);
}
