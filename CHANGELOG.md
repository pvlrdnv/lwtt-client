# Changelog

## 4.19

- Fixed equal-length credential redaction and kept rollback independent of diagnostic reads.
- Reported failed test restoration separately without an implicit second attempt.
- Bound tunnel status and background results to their actual process sessions.
- Fixed hostname error highlighting, reserved Windows profile names and numeric IP validation.
- Read SAN names without localized Windows text and recognized CA certificates.
- Supported basic multiline TOML strings and strict bypass enable flags.
- Removed the elevation check dependency on the Windows Server service.
- Kept archive verification active under Python optimization and corrected stale paths and instructions.

## 4.18

- Made PEM certificates optional, with Windows trust used by default.
- Collapsed the certificate section by default and exposed replace/remove actions while editing profiles.
- Always use an explicitly selected PEM for verification; invalid replacements retain the previous selection.
- Added certificate-specific failure messages and upload actions without misclassifying timeout, DNS or authorization failures.
- Preserved failed-session diagnostics before restoring the previous connection.

## 4.17

- Fixed editor layout rebuilding during text input and guarded unsaved changes.
- Added a shared bypass list in the tray with per-profile exclusions preserved.
- Preserved unrelated TOML settings and fixed escaped password decoding.
- Moved connection operations into a shared background coordinator with locking, cancellation and recovery journals.
- Reused the existing manager window through an atomic request mailbox.
- Restricted process termination to the current installation.
- Pinned TrustTunnel v1.0.49 and verified upstream SHA256 in both builders.
- Added PowerShell regression and isolated interface checks.

## 4.15

- Renamed public files to the short `lwtt` prefix.
- Updated internal file references to new script names.
- Prepared public package without saved server profiles.

## 4.14

- Stable working baseline.
- Fixed profile opening, status synchronization, tray menu behavior, diagnostic version output, and copyable error messages.
