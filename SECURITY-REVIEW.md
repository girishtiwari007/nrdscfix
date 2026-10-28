# Plan 1 / Plan 2 code and security review — 28 October 2026

## Repository mapping

| Plan | Canonical local repository | Entry point |
| --- | --- | --- |
| Plan 1 | D:\github\DSC-FIXER | install.ps1 |
| Plan 2 | D:\github\nrdscfix | index.html |

Plan 2 contains root-level static assets, downloads/, tests/verify.cjs and tools/refresh-bundle.ps1. The online launcher runs the published Plan 1 GitHub script. The alternate bundled Windows-Troubleshooter.ps1 is a byte-for-byte snapshot of local Plan 1, not an independently maintained repair implementation. Existing workspace preview files are historical staging; use nrdscfix as the canonical website checkout.

## Findings requiring release attention

### High — mutable, unsigned remote code is executed as administrator

Plan 2 downloads/Start-DSS-Online.cmd:8 builds the requested TLS + irm .../main/install.ps1 | iex command and starts it with -Verb RunAs. The standby command has the same trust model. No immutable release reference, expected publisher certificate or separately trusted hash is checked. Compromise of the GitHub publishing account or upstream content can therefore replace what runs after UAC approval. This is a supply-chain exposure, not evidence that the repository is compromised or an arbitrary website input injection.

Recommended remediation: publish a reviewed immutable release, download it to a saved file, verify a separately trusted release digest and/or expected code-signing publisher, and execute the verified file. Replacing iex with -File alone does not authenticate the source. No trust-policy change or certificate was fabricated during this review.

### High — installer identity heuristics can be forged

Plan 1 install.ps1:570 identifies installers using an OLE header prefix and product/version strings. Test-PackageValid at line 866 treats that heuristic as validation. A safe fixture consisting only of a fake header plus `Digital Signer Service 4.1.8` was accepted by the validator. No installation was attempted; Windows Installer may reject that malformed fixture. A genuinely malicious MSI can also claim the expected metadata, so these tests do not establish trusted provenance.

PackageSha256 is empty by default (line 214), and no approved publisher signature is enforced before silent installation. Local copies and the website bundle inherit this trust gap.

Recommended remediation: read actual MSI database properties and require the exact expected version, then independently authenticate the installer with an approved digest or expected signer/publisher. Do not treat a SHA256 fetched from the same replaceable source as independent authentication. Obtain the approved vendor release and signer/digest before changing acceptance policy, to avoid silently breaking valid DSS packages.

### Medium — configurable package source is not restricted to HTTPS

Plan 1 install.ps1:222 accepts DSSF_PKGURL without a scheme/host allowlist. Default sources use HTTPS and the consent prompt names the source, but a configured HTTP source could expose installer bytes to network tampering, particularly while the default expected hash is empty. Static inspection confirmed this configuration gap; no network interception was attempted.

Recommended remediation: require HTTPS for production downloads, constrain approved hosts and redirect destinations, and retain fixture paths only in explicit test mode. Preserve review and source-change consent.

## Defensive checks and changes

- Both repositories were backed up outside their checkouts with verified SHA256 inventories before editing.
- Plan 1 functional code was not changed as part of repository mapping. Prior uncommitted changes were preserved.
- Plan 2 uses only local scripts/styles/fonts; the external Google Fonts import was removed. Added a restrictive CSP including connect-src 'none', object-src 'none', base-uri 'none', form-action 'none', plus no-referrer.
- Inspected external tab links retain noopener/noreferrer. Current frontend has no dynamic HTML sink or eval call and uploads no logs.
- Safe archive probes blocked ../ traversal, absolute drive paths and NTFS alternate-stream paths on this Windows runtime. Existing regressions cover ZIP traversal, invalid hashes, HTML download rejection and source-change consent.
- Existing tests verify expiry exceptions stay limited to the exact signer endpoint, hosts repair preserves unrelated mappings, repairs require review and download consent defaults to No, cancellation stops remaining repairs, and sanitized reports exclude private fixture values.
- A limited scan of 31 text files matched no private-key, GitHub-token or AWS access-key patterns. This is not an exhaustive secret or dependency scan.

## Test results

- Plan 1: 223 isolated PowerShell checks passed across nine suites, including actual WinForms construction/event smoke simulations and temporary hosts fixtures.
- Plan 2: 15 browser-independent interaction checks passed; JavaScript syntax passed.
- Six static website/integrity checks passed, including byte-identical Plan 1 snapshot, launcher payload consistency, CSP presence, no external font import, safe external tab attributes, and no identified dynamic HTML sink.
- Four adversarial probes: three unsafe archive cases blocked; one installer-header spoof accepted and reported above.

No real installers, repairs, firewall changes, UAC approval, live penetration test, hosted HTTP-header scan or browser visual certification were performed. CSP behavior and download handling need checking in the target browser/hosting environment. Passing functional tests does not resolve the two high release risks.

## Code navigation

- Plan 1: install.ps1:570 (installer identity), :866 (package validation), :1015 (hosts check), :1038 (hosts repair), :2224 (guarded repair queue), :2621 (review UI).
- Plan 2: index.html (page), app.js (download/menu/copy handlers), downloads/Start-DSS-Online.cmd:8 (elevated launcher), launcher-data.js (exact downloadable CMD payload).

## Sources

- Microsoft PowerShell injection guidance: https://learn.microsoft.com/en-us/powershell/scripting/security/preventing-script-injection
- Microsoft Windows Installer digital signatures: https://learn.microsoft.com/en-us/windows/win32/msi/digital-signatures-and-windows-installer

No commits, pushes, repository creation, publication or deployments were performed.
