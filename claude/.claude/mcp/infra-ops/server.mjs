#!/usr/bin/env node
// infra-ops — MCP tools to manage the operator's homelab from Claude Code.
//
// Wraps the documented ops vocabulary (skills/home-infra.md + servers.md):
//   READ  : hosts, docker_ps/logs, prometheus_query, host_status
//   WRITE : docker_restart  (clearly labeled; the human invoking the tool is the
//           approval — this MCP is for interactive use)
// (k8s tools omitted until a working kubeconfig exists on mgmt01 — see note below.)
//
// Everything runs over ssh to a FIXED host allowlist. Security note that shapes
// the whole file: ssh concatenates its trailing args into a shell command on the
// REMOTE side, so passing arg-arrays to local execFile does NOT prevent remote
// injection. Therefore every operator-supplied value that reaches a remote
// command is either (a) a strict identifier (`ident`, which also blocks leading
// '-' option-injection) or (b) POSIX single-quote escaped (`shq`). The remote
// command is built as one fully-escaped string and passed as a single ssh arg.

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile, readdir, open, stat } from "node:fs/promises";
import { realpathSync } from "node:fs";
import { resolve } from "node:path";
import { HOSTS, shq, ident, hostTarget, tail } from "./lib.mjs";

const execFileAsync = promisify(execFile);

const DOCKER_DEFAULT = "prd01";
const PROM_HOST = "mgmt01";
const PROM_URL = "http://localhost:30090/api/v1/query"; // NodePort on mgmt01, reached via ssh mgmt01
// The GitOps source of truth (local clone). ArgoCD reconciles the k8s services
// from this repo, and docker-compose services on prd01 mirror it — so managing
// the manifest = reading/inspecting this repo + git state (no cluster access
// needed, which is why these work even while kubectl on mgmt01 does not).
const MANIFEST_DIR = "/Users/marshallku/dev/manifest";
let MANIFEST_REAL = MANIFEST_DIR;
try {
    MANIFEST_REAL = realpathSync(MANIFEST_DIR);
} catch {
    /* repo not cloned here — tools return a clear error at call time */
}
// NOTE: k8s tools are intentionally absent — mgmt01 currently exposes no
// kubeconfig to the marshall user (no ~/.kube/config, no readable k3s.yaml, sudo
// needs a password), and the manifest repo is mid-migration, so `kubectl` there
// only errors. Add k8s_* tools back once a working kubeconfig exists (verified
// 2026-07-20: docker@prd01, prometheus@mgmt01, host_status all work; k8s did not).

/** Run a fully-escaped remote command string over ssh (BatchMode: never prompt). */
async function ssh(target, remoteCmd) {
    try {
        const { stdout, stderr } = await execFileAsync(
            "ssh",
            ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", target, remoteCmd],
            { maxBuffer: 4 * 1024 * 1024, timeout: 30_000 },
        );
        return ok(stdout.trim() || stderr.trim() || "(no output)");
    } catch (e) {
        return fail(`ssh ${target} failed: ${(e.stderr || e.message || "").toString().trim()}`);
    }
}

const ok = (text) => ({ content: [{ type: "text", text: String(text).slice(0, 40_000) }] });
const fail = (text) => ({ content: [{ type: "text", text: String(text) }], isError: true });

const server = new McpServer({ name: "infra-ops", version: "0.1.0" });

/** Register a tool whose handler may throw validation errors → surfaced as fail. */
const tool = (name, desc, schema, fn) =>
    server.tool(name, desc, schema, async (args) => {
        try {
            return await fn(args || {});
        } catch (e) {
            return fail(e.message || String(e));
        }
    });

// --- tools ------------------------------------------------------------------

tool("infra_hosts", "List the managed hosts (ssh targets) and their roles. No ssh — read-only reference.", {}, async () => {
    const lines = Object.entries(HOSTS).map(([name, e]) => `${name}\t${e.role}`);
    return ok(lines.join("\n"));
});

tool(
    "infra_docker_ps",
    "List running Docker containers on a host (default prd01): name, status, image.",
    { host: z.string().optional() },
    async ({ host }) => {
        const t = hostTarget(host || DOCKER_DEFAULT);
        return ssh(t, `docker ps --format '{{.Names}}\\t{{.Status}}\\t{{.Image}}'`);
    },
);

tool(
    "infra_docker_logs",
    "Tail a Docker container's logs on a host (default prd01).",
    { container: z.string(), host: z.string().optional(), tail: z.number().optional() },
    async ({ container, host, tail: n }) => {
        const t = hostTarget(host || DOCKER_DEFAULT);
        const c = ident(container, "container");
        return ssh(t, `docker logs --tail ${tail(n ?? 100)} ${shq(c)} 2>&1`);
    },
);

tool(
    "infra_docker_restart",
    "WRITE: restart a Docker container on a host (default prd01). Use when a service is wedged.",
    { container: z.string(), host: z.string().optional() },
    async ({ container, host }) => {
        const t = hostTarget(host || DOCKER_DEFAULT);
        const c = ident(container, "container");
        return ssh(t, `docker restart ${shq(c)}`);
    },
);

tool(
    "infra_prometheus_query",
    "Run an instant PromQL query against Prometheus on mgmt01 (localhost:30090). Returns the raw JSON result. Good for host/container metrics (e.g. 'up', 'node_memory_MemAvailable_bytes').",
    { query: z.string() },
    async ({ query }) => {
        if (typeof query !== "string" || query.trim() === "") throw new Error("query is required");
        return ssh(hostTarget(PROM_HOST), `curl -sS --max-time 15 -G ${shq(PROM_URL)} --data-urlencode query=${shq(query)}`);
    },
);

tool(
    "infra_host_status",
    "Quick health of a host: uptime, disk (df -h /), memory (free -h). Default prd01.",
    { host: z.string().optional() },
    async ({ host }) => {
        const t = hostTarget(host || DOCKER_DEFAULT);
        return ssh(t, `echo '# uptime'; uptime; echo; echo '# disk'; df -h / ; echo; echo '# memory'; free -h 2>/dev/null || vm_stat`);
    },
);

// --- manifest (GitOps source of truth) — local repo, read-only, no cluster ----

async function gitManifest(...args) {
    try {
        const { stdout, stderr } = await execFileAsync("git", ["-C", MANIFEST_DIR, ...args], {
            maxBuffer: 4 * 1024 * 1024,
            timeout: 15_000,
        });
        return stdout.trim() || stderr.trim() || "(no output)";
    } catch (e) {
        throw new Error(`git: ${(e.stderr || e.message || "").toString().trim()}`);
    }
}

tool(
    "infra_manifest_services",
    "List the services defined in the ~/dev/manifest GitOps repo: docker-compose services (deployed to prd01) and k8s services (reconciled to mgmt01 by ArgoCD). The manifest is the deploy source of truth.",
    {},
    async () => {
        const groups = [
            ["docker-compose", "docker (prd01, `docker compose up -d`)"],
            ["kubernetes/service", "k8s (mgmt01 via ArgoCD auto-sync)"],
        ];
        const out = [];
        for (const [rel, label] of groups) {
            try {
                const entries = await readdir(resolve(MANIFEST_DIR, rel), { withFileTypes: true });
                const dirs = entries.filter((e) => e.isDirectory() && !e.name.startsWith(".")).map((e) => e.name);
                out.push(`# ${label}\n${dirs.sort().join(", ") || "(none)"}`);
            } catch {
                /* group dir absent — skip */
            }
        }
        return out.length ? ok(out.join("\n\n")) : fail(`manifest repo not found at ${MANIFEST_DIR}`);
    },
);

tool(
    "infra_manifest_status",
    "git status (uncommitted manifest changes NOT yet reconciled by ArgoCD) + recent commits (deploy history) of the ~/dev/manifest repo.",
    {},
    async () => {
        try {
            const status = await gitManifest("status", "--short");
            const clean = status === "(no output)" ? "(clean)" : status;
            const log = await gitManifest("log", "--oneline", "-12");
            return ok(`# uncommitted (pending ArgoCD reconcile)\n${clean}\n\n# recent commits\n${log}`);
        } catch (e) {
            return fail(e.message);
        }
    },
);

tool(
    "infra_manifest_show",
    "Show a manifest file from ~/dev/manifest (path-jailed, read-only). e.g. path='docker-compose/n8n/docker-compose.yml' or 'kubernetes/service/playzy'.",
    { path: z.string() },
    async ({ path }) => {
        const abs = resolve(MANIFEST_DIR, path);
        let real;
        try {
            real = realpathSync(abs);
        } catch {
            return fail(`no such path in manifest: ${path}`);
        }
        // Jail: the resolved real path must be inside the manifest repo.
        if (real !== MANIFEST_REAL && !real.startsWith(MANIFEST_REAL + "/")) {
            return fail("refused: path escapes the manifest repo");
        }
        try {
            const entries = await readdir(real, { withFileTypes: true });
            const listing = entries.map((e) => (e.isDirectory() ? e.name + "/" : e.name)).sort();
            return ok(`# ${path} (directory)\n${listing.join("\n")}`);
        } catch {
            /* not a directory → read as file (bounded) */
        }
        const LIMIT = 40_000;
        const { size } = await stat(real);
        if (size > LIMIT) {
            const fh = await open(real, "r");
            try {
                const buf = Buffer.alloc(LIMIT);
                const { bytesRead } = await fh.read(buf, 0, LIMIT, 0);
                return ok(buf.toString("utf8", 0, bytesRead) + "\n… (truncated)");
            } finally {
                await fh.close();
            }
        }
        return ok(await readFile(real, "utf8"));
    },
);

const transport = new StdioServerTransport();
await server.connect(transport);
