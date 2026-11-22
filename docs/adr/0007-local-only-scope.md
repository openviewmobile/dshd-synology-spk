# ADR-0007: Fully Local Product Scope Assessment (No Remote Edition)

> Note: This ADR comes from the cross-platform repository; references to documents not migrated with this project are kept as plain text.

- Status: Accepted (v1): local editions for macOS/Windows/Linux/Android; iOS remains research, not in v1
- Date: 2026-11-08
- Deciders: Product/Architecture
- Related: ADR-0002, ADR-0005, ADR-0006, device-local runtime research, iOS local feasibility, v1 delivery scope

## Context

The product goal has changed to:

- **No remote edition**;
- **A local edition on every platform**;
- The kernel is still dsh (Node + local shell/filesystem).

The question is not "can it be packaged" but: **which platforms allow an app to run the full dsh kernel locally at the OS level.**

## Conclusion

| Platform | Full local dsh | Assessment |
|---|---|---|
| macOS | ✅ | Electron/local Node 24; feasible |
| Windows | ✅ | Electron/local Node 24; feasible |
| Linux | ✅ | Electron/local Node 24; feasible |
| Android | ✅ (conditional) | Cortex/PRoot + targetSdk 28; feasible but not on Play |
| iOS | ⚠️ Under research | No product-grade evidence for full L2; iSH/UTM/Node-in-process (L0/L1) pending hands-on testing |
| Web | ❌ | Browsers have no local filesystem/subprocesses; a Host is mandatory |

**Current evidence: "all six platforms fully local" at full L2 does not hold.**
If "fully local" is a hard requirement, the currently deliverable scope is: **macOS + Windows + Linux + Android**; iOS still needs a 4–8 week spike and cannot be permanently removed now.
If "six platforms" is a hard requirement, then iOS/Web must either go remote or accept the capability cuts of the dsh Lite/emulator route.

## 1. Three desktop platforms: no controversy

- Electron 44 + bundled Node 24 + dsh;
- Local files, bash, ripgrep, pnpm, Python, native modules;
- Signing/notarization/updates;
- Distribution via GitHub Releases.

This is the path already validated by the current architecture.

## 2. Android: feasible, but requires a separate SKU

- Not shipping on Play, so `targetSdk 28` can be used to execute Linux binaries from the app's private directory;
- Route: Cortex (native glibc, Apache-2.0) or PRoot (mature, GPL);
- Distribution: GitHub APK / enterprise MDM;
- Costs:
  - Unknown sources/Play Protect/restricted settings;
  - 16 KB page size;
  - 1 GB-class runtime;
  - Foreground service/background kills/battery;
  - Native modules must be verified one by one;
  - GPL/rootfs licensing.

**Android is the only additional mobile platform possible under "fully local".**

## 3. iOS: an IPA is not local

### 3.1 System restrictions are unchanged

- `fork/exec` prohibited: cannot start bash/node/pnpm;
- JIT prohibited: Node/V8 can only interpret;
- Background suspension: cannot keep a Host resident;
- Sandbox: cannot install a Linux userland.

**Sideloading/an IPA only changes the installation method, not the restrictions above.**

### 3.2 Candidate technical paths (all pending hands-on testing)

| Path | Principle | Issues | Current assessment |
|---|---|---|---|
| **iSH embedding** | x86 Linux emulation + syscall translation inside the app; install Node/dsh in Alpine | GPLv3; 32-bit; no JIT; 5–100x slower; known Node illegal instructions; not an SDK | Closest to full local; needs real-device validation of Node 24 |
| **UTM SE/VM embedding** | ARM64 Linux VM inside the app (QEMU interpreter) | No JIT; slower; huge bundle; background; not an SDK | Can run ARM64 Node 24; product performance doubtful |
| **Node 24 in-process** | Build Node 24 as an iOS library; no Linux userland | No `child_process`/bash/PTY; native modules must be rebuilt; nodejs-mobile only has Node 18 | Most likely to yield **dsh Lite (L0/L1)** |
| **Custom lightweight Swift/JS agent** | Bypass Node/dsh, rewrite the tools | Not dsh; tools/plugins/Session incompatible | A different product, not local dsh |
| **jailbreak/TrollStore** | Bypass the restrictions | Unsupported, insecure, unsustainable | Not doing it |

iSH embedding could in theory let "an iPhone run Linux + Node locally", but:

- iSH is 32-bit i386; although Alpine edge x86 has Node 24.22.1, Node 24 has no official linux-x86 binary, so this is a distro patch;
- iSH already has Node/NPM `Illegal instruction` reports (Node 20+ requires falling back to an older version); whether Node 24 can start must be tested on a real device;
- iSH officially quotes performance at 5–100x slower than native;
- GPLv3, restricting closed-source/commercial distribution;
- An IPA can only be self-signed/Ad Hoc/enterprise, not a mainstream user channel;
- Killed in the background, long tasks are unreliable.

**Current assessment: there is no product-grade evidence for full L2; the iSH route must not be declared dead just because it "should work in theory", nor treated as already feasible.**

## 4. Web: there is no such thing as a "local kernel"

Browsers cannot:

- start Node processes;
- execute bash/pnpm;
- access arbitrary local filesystems;
- stay resident in the background.

WebAssembly also cannot provide the full Node API, subprocesses, and system tools. "Web local" has only two meanings:

1. The browser connects to a Host on the same machine/LAN/cloud → still remote;
2. A desktop app embeds the Host and the browser is merely its UI → not a standalone Web product.

**Conclusion: no remote edition means no Web edition.**

## 5. Four product scopes

### Option A: Fully local on four platforms (recommended if "local" is a hard requirement)

| Platform | Form | Kernel |
|---|---|---|
| macOS | Desktop app | Local dsh |
| Windows | Desktop app | Local dsh |
| Linux | Desktop app | Local dsh |
| Android | Local APK | Local Cortex/PRoot + dsh |
| iOS | Not offered | — |
| Web | Not offered | — |

- Pros: truly fully local; no cloud dependency; strongest privacy story.
- Cons: gives up iOS/Web; high Android maintenance cost; limited market size.
- Timeline: desktop 2–3 months; Android local 6–12 months; 9–15 months total (3–5 people).

### Option B: Fully local on six platforms + iOS/Web "Lite"

- iOS/Web do not run dsh; use a lightweight agent (Swift/JS/WASM) or a read-only UI.
- Result: not the same kernel, not the same toolset, not the same product.
- Not recommended: users will perceive it as "crippled", and two agents must be maintained.

### Option C: Six platforms, but iOS/Web remote (violates "no remote")

- Desktop/Android local; iOS/Web connect to a local Host or the cloud.
- This is the only option that keeps full dsh on six platforms.
- If "no remote" cannot be compromised, this option does not hold.

### Option D: Force iOS with iSH/UTM

- Fine as a technical demo, not viable as a product.
- Not recommended for investment.

## 6. If Option A is chosen, how to define the architecture

```
┌─────────────────────────────┐
│ Unified UI / client logic   │
│ (Flutter or Electron/React) │
└──────────────┬──────────────┘
               │ Local HTTP/WS
     ┌─────────┴─────────┐
     │                   │
┌────▼──────┐      ┌─────▼──────┐
│ Desktop   │      │ Android    │
│ Electron  │      │ Cortex/    │
│ + Node 24 │      │ PRoot +    │
│ + dsh     │      │ Node 24    │
└───────────┘      └────────────┘
```

Key decisions:

- Whether to unify the UI:
  - Electron/React: desktop reuses upstream, Android uses Capacitor/Flutter;
  - Flutter: unified UI for desktop+Android, but the protocol/shell must be rewritten;
- Android runtime: Cortex preferred (Apache-2.0, good performance), PRoot as fallback;
- Distribution: GitHub Releases; Android APK targetSdk 28; desktop signing/notarization;
- No iOS/Web builds, no remote pairing/relay/cloud.

## 7. Cost and risk

| Item | Estimate |
|---|---|
| Three desktop platforms | 2–3 months (reuse upstream) |
| Android local | 6–12 months (Cortex/PRoot, native modules, background, storage) |
| Unified UI (if Flutter) | +9–15 months |
| iOS local attempt | 3–6 months, demo only |
| Web local | Impossible |
| Maintenance | Android runtime must follow dsh/Node/rootfs upgrades monthly |

Main risks:

- Compatibility/security warnings from Android targetSdk 28;
- Play Protect/OEM restrictions;
- 16 KB page size;
- Native module compilation;
- Killed in the background;
- GPL/rootfs licensing;
- Insufficient user coverage without iOS/Web.

## 8. Recommendation

1. **Confirm whether "fully local" outranks "six-platform coverage".**
   - If yes: choose Option A and hard-code the product scope as macOS/Windows/Linux/Android.
   - If six platforms cannot be abandoned: choose Option C, with iOS/Web remote.
2. **Do not force iOS local with iSH/UTM**; the return on investment is extremely poor.
3. **Validate Android before committing**: Cortex/PRoot running dsh's Node 24, tools, native modules, and background behavior; invest only after it passes.
4. **UI unification can be deferred**: start with desktop Electron + Android local, validate demand, then decide on Flutter.
5. **Make "no local iOS/Web support" explicit in docs/website** to avoid misaligned user expectations.

## 9. Final assessment

- **v1 scope: local editions for macOS/Windows/Linux/Android; no iOS/Web/remote.**
- **Fully local on four platforms (macOS/Windows/Linux/Android): feasible.**
- **Fully local on six platforms: current evidence does not support full L2.**
- **Full local dsh on iOS: under research; iSH/UTM can produce a demo, Node-in-process may produce an L0/L1 dsh Lite.**
- **Local dsh on Web: conceptually impossible.**
- **If "no remote" is a hard constraint, the product must give up iOS/Web; if six platforms is a hard constraint, remote must be accepted.**

## Review conditions

- Apple opens up JIT/subprocesses/local runtimes (unlikely);
- Web standards gain usable local process/filesystem capabilities (unlikely);
- Android local runtime validation fails;
- The iOS spike completes and confirms L0/L1 or that L2 is infeasible;
- The product decides to drop iOS;
- The product decides to restore the remote edition in order to keep six platforms.
