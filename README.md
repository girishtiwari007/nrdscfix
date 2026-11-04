## Current website method

The primary **Troubleshooting Method** shows a two-line command for Windows PowerShell opened as administrator. The website no longer offers the PowerShell CMD launcher download. Follow steps 1, 2 and 3, highlighted green, yellow and light yellow in sequence; reduced-motion preferences keep them steady. Software/form downloads, isLive testing, view density controls and local log export remain available.

# Plan 2 â€” E-Office Digital Signing Toolkit

Canonical website repository: D:\github\nrdscfix (girishtiwari007/nrdscfix).
Plan 1 PowerShell repository: D:\github\DSC-FIXER (girishtiwari007/DSC-FIXER).

index.html and toolkit.html are published from the main branch root through GitHub Pages.

Open index.html locally, or run:
python -m http.server 8765 --bind 127.0.0.1 --directory D:\github\nrdscfix

Run website interaction checks:
node D:\github\nrdscfix\tests\verify.cjs

The two-line PowerShell command executes the published Plan 1 GitHub script. Open Windows PowerShell as administrator, copy the command, paste it and press Enter. The page no longer offers the online CMD launcher download. Browser policy, antivirus and execution policy remain active. No automatic log upload is included.

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

## Self-contained page build
index.html now embeds its CSS and JavaScript with SHA256 hashes in its CSP. This removes separate asset requests needed for styling and controls, including when opening a downloaded/local page. Edit tools/index.template.html and the source CSS/JS files, then run python D:\github\nrdscfix\tools\build-page.py and node D:\github\nrdscfix\tests\verify.cjs before publishing. Do not hand-edit generated index.html or replace its CSP with unsafe-inline.

