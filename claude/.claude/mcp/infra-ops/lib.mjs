// Pure, ssh-free security + config helpers for infra-ops. Separated so smoke.mjs
// can unit-test the injection guards without touching the network.

// Host allowlist. Logical name → ssh target + role blurb.
// The 2026-09 pve02 consolidation retired prd01/mgmt01/dev01: k3s moved to the
// single node k3s01 and the compose stacks to app01. Both are cloud-init guests
// with no ~/.ssh/config alias, hence user@ip targets.
export const HOSTS = {
    k3s01: { target: "marshall@192.168.219.193", role: "Single-node k3s (ArgoCD-reconciled) + Prometheus:30090 / Grafana:30300" },
    app01: { target: "marshall@192.168.219.194", role: "Docker host — compose stacks with volumes (AdGuard main, n8n, blog, portainer, …)" },
    edge01: { target: "marshall@192.168.219.192", role: "Edge — Cloudflare tunnel + certs, stateless by design" },
    storage01: { target: "marshall@192.168.219.191", role: "ZFS storage/NAS + GPU passthrough" },
    pi01: { target: "marshall@192.168.219.127", role: "Raspberry Pi — secondary AdGuard DNS + homelab-status" },
    pve02: { target: "root@192.168.219.199", role: "Proxmox hypervisor hosting the guests above" },
    macmini: { target: "macmini", role: "life-assistant launchd host" },
    arch: { target: "arch", role: "misc host" },
};

/** POSIX single-quote escape for safe interpolation into a REMOTE shell command.
 *  ssh concatenates trailing args into a shell on the far side, so local
 *  execFile arg-arrays do NOT protect the remote — this does. */
export const shq = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;

/** Strict object identifier: letters/digits/._-/ only, no leading '-' (blocks
 *  docker/kubectl option-injection like a container named "--help"). Throws. */
export const ident = (s, label) => {
    if (typeof s !== "string" || !/^[a-zA-Z0-9][a-zA-Z0-9._/-]*$/.test(s)) {
        throw new Error(`invalid ${label} ${JSON.stringify(s)} — allowed: letters, digits, . _ - / and no leading '-'`);
    }
    return s;
};

/** Free-form value that still reaches a remote command (label selectors, PromQL).
 *  shq makes it one literal arg; the leading-'-' guard is what shq cannot do,
 *  since `kubectl get pods '-o=json'` would still be parsed as a flag. Throws. */
export const freeArg = (s, label) => {
    if (typeof s !== "string" || s === "" || s.startsWith("-")) {
        throw new Error(`invalid ${label} ${JSON.stringify(s)} — must be non-empty and not start with '-'`);
    }
    return s;
};

/** Resolve a logical host name to its ssh target, or throw on unknown. */
export const hostTarget = (h) => {
    const e = HOSTS[h];
    if (!e) throw new Error(`unknown host ${JSON.stringify(h)} — known: ${Object.keys(HOSTS).join(", ")}`);
    return e.target;
};

/** Validate a tail line count (1–2000). Throws otherwise. */
export const tail = (n) => {
    const v = Number(n);
    if (!Number.isInteger(v) || v < 1 || v > 2000) throw new Error("tail must be an integer 1–2000");
    return v;
};
