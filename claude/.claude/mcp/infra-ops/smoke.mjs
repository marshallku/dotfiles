// Unit tests for the security-critical helpers (no network). Run: npm run smoke
import { shq, ident, freeArg, hostTarget, tail } from "./lib.mjs";
import assert from "node:assert/strict";

let pass = 0;
const t = (name, fn) => {
    fn();
    pass++;
    console.log("ok  " + name);
};
const throws = (fn) => {
    try {
        fn();
        return false;
    } catch {
        return true;
    }
};

t("shq escapes single quotes", () => {
    assert.equal(shq("a'b"), `'a'\\''b'`);
    assert.equal(shq("plain"), `'plain'`);
});

t("shq keeps injection payloads as one literal arg", () => {
    assert.equal(shq("x; rm -rf /"), `'x; rm -rf /'`);
    assert.equal(shq("$(reboot)"), `'$(reboot)'`);
    assert.equal(shq("`id`"), "'`id`'");
});

t("ident accepts normal object names", () => {
    ["nginx", "n8n", "my-pod.0", "svc/foo", "a_b", "deployment/api"].forEach((n) => assert.equal(ident(n, "x"), n));
});

t("ident rejects shell metachars, spaces, and option-injection", () => {
    ["--help", "-v", "a;b", "a b", "a`b`", "", "a$b", "a|b", "a&b", "a>b", ".hidden", "/abs"].forEach((n) =>
        assert.ok(throws(() => ident(n, "x")), `should reject: ${JSON.stringify(n)}`),
    );
});

t("hostTarget enforces the allowlist", () => {
    assert.equal(hostTarget("k3s01"), "marshall@192.168.219.193");
    assert.equal(hostTarget("app01"), "marshall@192.168.219.194");
    // Retired 2026-09 by the pve02 consolidation — must no longer resolve.
    ["prd01", "mgmt01", "dev01"].forEach((h) => assert.ok(throws(() => hostTarget(h)), `retired host should be gone: ${h}`));
    ["evil", "app01; rm", "", undefined].forEach((h) => assert.ok(throws(() => hostTarget(h)), `should reject host ${JSON.stringify(h)}`));
});

t("freeArg allows selectors but blocks option-injection", () => {
    ["app=blog", "app.kubernetes.io/name=argocd,tier=web"].forEach((v) => assert.equal(freeArg(v, "x"), v));
    ["-o=json", "--all", "", undefined, 7].forEach((v) => assert.ok(throws(() => freeArg(v, "x")), `should reject ${String(v)}`));
});

t("tail bounds to 1–2000 integers", () => {
    assert.equal(tail(100), 100);
    assert.equal(tail(1), 1);
    [0, -1, 2001, 1.5, "abc", NaN, undefined].forEach((v) => assert.ok(throws(() => tail(v)), `should reject tail ${String(v)}`));
});

console.log(`\n${pass} checks passed`);
