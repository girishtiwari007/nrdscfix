# Plan 2 â€” E-Office Digital Signing Toolkit

Canonical website repository: D:\github\nrdscfix (girishtiwari007/nrdscfix).
Plan 1 PowerShell repository: D:\github\DSC-FIXER (girishtiwari007/DSC-FIXER).

index.html and assets are at the repository root. For future GitHub Pages hosting,
select the root of the intended branch. No hosting or publication was performed.

Open index.html locally, or run:
python -m http.server 8765 --bind 127.0.0.1 --directory D:\github\nrdscfix

Run website interaction checks:
node D:\github\nrdscfix\tests\verify.cjs

The online CMD launcher and standby command execute the published Plan 1 GitHub
script, not a separate troubleshooting implementation. Open the downloaded CMD
and approve UAC; browsers cannot directly elevate PowerShell. A private signing
key, browser policy bypass, antivirus change or automatic log upload is not included.

downloads/Windows-Troubleshooter.ps1 is the local Plan 1 snapshot. The alternate
downloads/DSS-Windows-Launcher.zip contains that snapshot. Refresh it using
tools/refresh-bundle.ps1 after reviewing and testing Plan 1. These are unsigned
artifacts; bundled SHA256 values are integrity checks, not publisher authentication.

Software links include Java, AnyDesk, UltraViewer and DSS (direct + Drive mirror).
Copyright/usage terms for the bundled script are in downloads/LICENSE.txt.
No third-party installers are redistributed. Session logs remain on the Windows PC.

Security review: see SECURITY-REVIEW.md. Source authorization and installer publisher
verification remain release risks; passing fixtures is not a security certification.
The static site has no external font/CDN dependency and limits scripts/styles to
local assets with CSP. Deploy over HTTPS and configure response security headers
on a host that supports them. The local file preview may handle downloads differently.

No commits or pushes are authorized by this setup.