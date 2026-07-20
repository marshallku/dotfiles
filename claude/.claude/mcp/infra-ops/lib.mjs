// Pure, ssh-free security + config helpers for infra-ops. Separated so smoke.mjs
// can unit-test the injection guards without touching the network.

// Host allowlist (from servers.md). Logical name → ssh target + role blurb.
export const HOSTS = {
    prd01: { target: "prd01", role: "Docker host — compose services (portainer, adguard, n8n, nextcloud, gitgarden, dongjoo.me, …)" },
    mgmt01: { target: "marshall@192.168.219.109", role: "k3s cluster (namespace mgmt01) + Prometheus:30090 / Grafana:30300" },
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
