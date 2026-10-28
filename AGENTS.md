# Plan 2 repository rules
- This is the canonical static website repository, D:\github\nrdscfix.
- The PowerShell source belongs to Plan 1 at D:\github\DSC-FIXER. Do not independently edit the bundled snapshot; refresh from tested Plan 1 source.
- Before editing existing files, create and verify a new timestamped repository backup outside the repository, excluding .git, with a SHA256 inventory.
- Preserve user approval, UAC and repair review. Do not execute installers or change real system settings merely for tests.
- No commit, push, publishing, trust-policy change or log upload without explicit authorization.