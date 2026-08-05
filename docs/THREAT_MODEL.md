# AssembleLink Threat Model

## Assets

- workstation inventory
- hardware profile
- approved software catalog
- install queues
- execution receipts
- user trust
- machine integrity

## Threats and mitigations

| Threat | Risk | Mitigation |
|---|---|---|
| Unapproved software install | High | Only approved catalog entries generate executable commands |
| Silent install | High | Require explicit user action and admin prompts |
| License bypass | High | Licensed tools require manual review |
| Fake source | High | Official source or winget ID required |
| Driver damage or false update claim | High | Drivers and BIOS remain recommendation-only; local inventory reports installed versions but never claims an update without separate provider verification, administrator approval, an official source, recovery planning, and post-install device verification |
| Hardware-profile privacy leakage | Medium | Driver inventory is local-only, bounds device text and counts, excludes MAC addresses and device paths, and exposes only the metadata required to identify support paths |
| Misleading install result | Medium | Classify outcomes accurately |
| Receipt tampering or replay overwrite | Medium | Immutable per-run result and receipt names, independently recomputed SHA-256 sidecars, and negative replay tests; publisher signing remains a release gate |
| Catalog command injection | Critical | Catalog stores package identities, never executable command strings; execution builds a fixed argument vector |
| Path traversal through IDs | High | Capability, toolkit, and software IDs are allowlisted and never used as unchecked paths |
| Malicious blueprint | High | Imports accept catalog IDs only, reject unknown schema/IDs, and cannot embed commands or URLs |
| Rebuild export turns unknown software into an installer | High | Machine blueprint export refreshes local inventory, includes only installed entries with valid approved catalog IDs, deduplicates identities, resolves them through the normal content-hashed planner, and reports unmatched software without guessing a source or command |
| Registry components are mistaken for catalog-ready applications | Medium | Inventory retains every observed row but separately labels managed applications, application candidates, developer components, driver components, and system components; only application candidates enter catalog-review counts and no heuristic classification grants execution authority |
| Confused browser UI | High | Machine-changing commands exist only behind Tauri IPC; browser preview fails closed |
| Dependency substitution | High | Exact Winget IDs and exact-match lookup/install are required |
| Catalog package disappearance or reassignment | High | Release verification probes every automatable identity against the named live Winget source with bounded timeouts and hashed evidence; missing packages are removed from automation and retained only through a reviewed official-manual path |
| Alternate package-source substitution | High | Resolve, install, and verify only against the named `winget` community source |
| False installer success | High | Re-query the exact installed package identity after execution; exit code alone is not proof |
| Interrupted installation | Medium | Durable per-item progress supports discovery after restart; resume requires renewed user approval, revalidates the content-hashed plan and completed-result prefix, retries non-terminal outcomes, and independently rechecks every exact Winget identity before skipping completed automatic work |
| Forged resume state | High | Recovery reads fixed bounded files, requires matching plan/progress schemas and counts, allowlists returned fields, rejects mismatched result prefixes and invalid boolean/status types, and never treats mutable progress as authority for installation or plan approval |
| Progress-channel file abuse | High | Live setup progress reads one fixed per-user state file without reseeding or waiting on the execution lock; the desktop bounds file size and item count, rejects path escapes, malformed schemas, invalid counts, and stale plan IDs, then returns only a normalized field allowlist |
| Local state disclosure | Medium | Mutable profiles, logs, and receipts live in per-user application data and are excluded from source control |
| False “current” status | High | “Current” requires comparable installed/available versions from a successful approved-provider observation; stale, malformed, rate-limited, offline, and unavailable checks remain unknown |
| Fixture evidence contaminates a workstation proof | High | Software intelligence labels live and fixture collection explicitly; the workstation proof accepts only live evidence, binds it through the append-only receipt and SHA-256 sidecars, and rejects path escapes, mismatched hashes, or synthetic fixture state |
| Forged dashboard assurance | High | The trusted desktop bounds each source file, recomputes SHA-256 sidecars, validates exact schemas, requires live rather than fixture software evidence, and writes a new append-only assurance state and receipt before presenting verified status |
| Renderer opens before the packaged engine is initialized | High | Native application startup now seeds and validates the trusted scripts, catalog, and manifests before the webview is allowed to run; missing packaged resources fail startup with a specific trusted-runtime error instead of leaving a partially functional dashboard |
| Software-name impersonation | High | Registry names are untrusted; catalog matching uses normalized exact reviewed aliases only and ambiguous aliases fail closed |
| Provider identity confusion | High | Winget checks use an exact package ID and explicit source; GitHub checks use catalog-pinned owner/repository coordinates |
| Provider response abuse | Medium | Network calls have a short timeout, no redirects, bounded use, response schema checks, serial execution, and an age-limited cache |
| Inventory data weaponization | High | Display fields are escaped, never executed, and intelligence output omits uninstall commands and full install paths |
| Malicious local snapshot markup | High | Legacy snapshot JSON is depth-, count-, and length-bounded; control and markup characters are neutralized before any panel renders; technical JSON is HTML-escaped |
| Receipt-path escape or evidence disclosure | Medium | Receipt enumeration is confined to canonical files beneath the per-user receipt directory, accepts only bounded JSON/text evidence, and returns metadata/hash status rather than paths or contents |
| Signing-key misuse | Critical | Release signing requires an explicit certificate thumbprint, SHA-256 digest, trusted timestamp, and independent Authenticode verification; unsigned artifacts fail the public release gate |
| False clean-machine confidence | High | Execution requires explicit controlled-environment confirmation and matching OS, architecture, privilege, and Winget preconditions; evidence checks cover installer hash/signature/timestamp, installed signer identity, runtime startup, receipt integrity, and uninstall preservation |
| Incomplete or replayed clean-machine proof is presented as matrix completion | High | The matrix auditor selects the latest case proof, recomputes its sidecar, validates schema, case identity, expected outcome, installer hash shape, and every case-specific required check; missing scenarios remain pending and never count as release evidence |
| Unsigned development installer is mistaken for a public release | Critical | Release staging fails closed unless Authenticode and a trusted timestamp validate; the explicit development override produces an `UNSIGNED-DEVELOPMENT` filename and a manifest with `release_eligible: false` |
| GitHub signing secret is exposed or an unsigned artifact is uploaded | Critical | The release workflow imports a base64 PFX only into the ephemeral current-user certificate store, deletes the temporary PFX, builds through Tauri signing configuration, independently verifies the application and installer signatures/timestamps, and creates a draft rather than publishing automatically |
| Clean machine cannot start the dashboard because WebView2 is absent | High | The Windows NSIS configuration embeds the official WebView2 offline installer; application software still comes only from approved providers and remains subject to explicit user approval |
| Packaged engine or catalog tampering | Critical | Executable engines and core catalogs are embedded in the compiled desktop binary and restored before every release-mode operation; release builds ignore the development root override |
| Concurrent IPC runtime corruption | High | Desktop operations share a process-wide runtime lock across trusted reseeding, engine execution, and state reads so one command cannot truncate policy or scripts used by another |
| Host PowerShell module variance | High | Packaged integrity operations use the .NET SHA-256 implementation directly and do not depend on optional PowerShell hashing cmdlets; BOM-tolerant trusted JSON parsing is regression-tested |
| Legacy executor bypass | Critical | The older capability queue IPC surface is not registered; every UI install path converges on the content-hashed setup plan, explicit approval, exact Winget source, and post-install verification |

## Safety rules

- No silent installs.
- No unknown installer execution.
- No license bypass.
- Every execution writes a receipt and SHA-256 sidecar.
- User approval is required before install.
- Unknown catalog, toolkit, capability, and blueprint IDs fail closed.
- Manual, paid, account-gated, driver, and firmware work never enters the automatic executor.
- Installer stdout/stderr is treated as untrusted display data and must not become executable markup.
- Live progress is informational only and cannot approve, alter, cancel, or start an installation.
- Interrupted work never resumes automatically; the user reviews the recovered plan and explicitly approves the remaining execution.
