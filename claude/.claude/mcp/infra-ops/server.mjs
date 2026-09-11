#!/usr/bin/env node
// infra-ops — MCP tools to manage the operator's homelab from Claude Code.
//
// Wraps the documented ops vocabulary (skills/home-infra.md + servers.md):
//   READ  : hosts, docker_ps/logs, prometheus_query, host_status, k8s_get/logs/describe
//   WRITE : docker_restart, k8s_rollout_restart  (clearly labeled; the human
//           invoking the tool is the approval — this MCP is for interactive use)
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
import { HOSTS, shq, ident, freeArg, hostTarget, tail } from "./lib.mjs";

const execFileAsync = promisify(execFile);

const DOCKER_DEFAULT = "app01";
const PROM_HOST = "k3s01";
const PROM_URL = "http://localhost:30090/api/v1/query"; // NodePort on k3s01, reached via ssh k3s01
const K8S_HOST = "k3s01";
// k3s ships `kubectl` as a symlink to the k3s binary, which defaults to
// /etc/rancher/k3s/k3s.yaml — root-owned 0600, so a bare `kubectl` errors for the
// marshall user. marshall has a readable copy at ~/.kube/config, so every call
// pins KUBECONFIG rather than relying on the default lookup. $HOME expands on the
// REMOTE side (the whole string is the shell ssh runs there), which is the point.
const KUBECTL = 'KUBECONFIG="$HOME/.kube/config" kubectl';
// The GitOps source of truth (local clone). ArgoCD reconciles the k8s services
// from this repo, and docker-compose services on app01 mirror it — so managing
// the manifest = reading/inspecting this repo + git state (no cluster access
// needed, which is why these keep working even when the cluster is down).
const MANIFEST_DIR = "/Users/marshallku/dev/manifest";
let MANIFEST_REAL = MANIFEST_DIR;
try {
    MANIFEST_REAL = realpathSync(MANIFEST_DIR);
} catch {
    /* repo not cloned here — tools return a clear error at call time */
}

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
        // Remote commands here fold stderr into stdout (`2>&1`), so on a non-zero
        // exit the useful text — kubectl's NotFound/Forbidden, docker's "no such
        // container" — is in e.stdout, which e.message does not carry.
        const detail = [e.stderr, e.stdout].map((x) => (x || "").toString().trim()).filter(Boolean).join("\n");
        return fail(`ssh ${target} failed: ${detail || (e.message || "").toString().trim()}`);
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
    "List running Docker containers on a host (default app01): name, status, image.",
    { host: z.string().optional() },
    async ({ host }) => {
        const t = hostTarget(host || DOCKER_DEFAULT);
        return ssh(t, `docker ps --format '{{.Names}}\\t{{.Status}}\\t{{.Image}}'`);
    },
);

tool(
    "infra_docker_logs",
    "Tail a Docker container's logs on a host (default app01).",
    { container: z.string(), host: z.string().optional(), tail: z.number().optional() },
    async ({ container, host, tail: n }) => {
        const t = hostTarget(host || DOCKER_DEFAULT);
        const c = ident(container, "container");
        return ssh(t, `docker logs --tail ${tail(n ?? 100)} ${shq(c)} 2>&1`);
    },
);

tool(
    "infra_docker_restart",
    "WRITE: restart a Docker container on a host (default app01). Use when a service is wedged.",
    { container: z.string(), host: z.string().optional() },
    async ({ container, host }) => {
        const t = hostTarget(host || DOCKER_DEFAULT);
        const c = ident(container, "container");
        return ssh(t, `docker restart ${shq(c)}`);
    },
);

tool(
    "infra_prometheus_query",
    "Run an instant PromQL query against Prometheus on k3s01 (localhost:30090). Returns the raw JSON result. Good for host/container metrics (e.g. 'up', 'node_memory_MemAvailable_bytes').",
    { query: z.string() },
    async ({ query }) => {
        if (typeof query !== "string" || query.trim() === "") throw new Error("query is required");
        return ssh(hostTarget(PROM_HOST), `curl -sS --max-time 15 -G ${shq(PROM_URL)} --data-urlencode query=${shq(query)}`);
    },
);

tool(
    "infra_host_status",
    "Quick health of a host: uptime, disk (df -h /), memory (free -h). Default app01.",
    { host: z.string().optional() },
    async ({ host }) => {
        const t = hostTarget(host || DOCKER_DEFAULT);
        return ssh(t, `echo '# uptime'; uptime; echo; echo '# disk'; df -h / ; echo; echo '# memory'; free -h 2>/dev/null || vm_stat`);
    },
);

// --- k8s (k3s01, via ssh + kubectl) -----------------------------------------

/** Namespace flag: "" (kubectl's default ns), `--all-namespaces`, or `-n <ns>`. */
const nsFlag = (ns) => {
    if (!ns) return "";
    if (ns === "all") return "--all-namespaces";
    return `-n ${shq(ident(ns, "namespace"))}`;
};

/** Run a kubectl subcommand on k3s01. `args` is already escaped by the caller. */
const kubectl = (args) => ssh(hostTarget(K8S_HOST), `${KUBECTL} ${args} 2>&1`);

tool(
    "infra_k8s_get",
    "List k8s objects on k3s01. resource e.g. 'pods', 'deploy', 'ingress', 'application' (ArgoCD). namespace defaults to kubectl's current ns; pass 'all' for every namespace.",
    {
        resource: z.string(),
        namespace: z.string().optional(),
        selector: z.string().optional(),
        output: z.enum(["wide", "yaml", "json", "name"]).optional(),
    },
    async ({ resource, namespace, selector, output }) => {
        const parts = [`get ${shq(ident(resource, "resource"))}`, nsFlag(namespace)];
        if (selector) parts.push(`-l ${shq(freeArg(selector, "selector"))}`);
        parts.push(`-o ${output || "wide"}`);
        return kubectl(parts.filter(Boolean).join(" "));
    },
);

tool(
    "infra_k8s_describe",
    "Describe one k8s object on k3s01 (events included — the first thing to read when a pod will not start).",
    { resource: z.string(), name: z.string(), namespace: z.string().optional() },
    async ({ resource, name, namespace }) =>
        kubectl(
            [`describe ${shq(ident(resource, "resource"))} ${shq(ident(name, "name"))}`, nsFlag(namespace)]
                .filter(Boolean)
                .join(" "),
        ),
);

tool(
    "infra_k8s_logs",
    "Tail a pod's logs on k3s01. target may be a pod name or a controller ref like 'deploy/blog-api'.",
    { target: z.string(), namespace: z.string().optional(), container: z.string().optional(), tail: z.number().optional(), previous: z.boolean().optional() },
    async ({ target, namespace, container, tail: n, previous }) => {
        const parts = [`logs ${shq(ident(target, "target"))}`, nsFlag(namespace)];
        if (container) parts.push(`-c ${shq(ident(container, "container"))}`);
        if (previous) parts.push("--previous"); // the crashed instance, not the live one
        parts.push(`--tail ${tail(n ?? 100)}`);
        return kubectl(parts.filter(Boolean).join(" "));
    },
);

tool(
    "infra_k8s_rollout_restart",
    "WRITE: roll a workload on k3s01 (`kubectl rollout restart`). resource e.g. 'deploy'/'statefulset'. Note ArgoCD auto-syncs from ~/dev/manifest — this restarts pods, it does not change desired state.",
    { resource: z.string(), name: z.string(), namespace: z.string() },
    async ({ resource, name, namespace }) =>
        // -n explicitly, not nsFlag: `rollout restart` has no meaningful "all
        // namespaces" form, so a literal namespace is the only valid input.
        kubectl(
            `rollout restart ${shq(ident(resource, "resource"))} ${shq(ident(name, "name"))} -n ${shq(ident(namespace, "namespace"))}`,
        ),
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
    "List the services defined in the ~/dev/manifest GitOps repo: docker-compose services (deployed to prd01) and k8s services (reconciled to k3s01 by ArgoCD). The manifest is the deploy source of truth.",
    {},
    async () => {
        const groups = [
            ["docker-compose", "docker (app01, `docker compose up -d`)"],
            ["kubernetes/apps", "k8s factory apps (k3s01, ApplicationSet-generated)"],
            ["kubernetes/service", "k8s hand-written services (k3s01 via ArgoCD auto-sync)"],
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
