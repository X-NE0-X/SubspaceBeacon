# Open-source preparation audit

This checkout is the public-source preparation copy of the portable Beacon
component. The original deployment copy remains separate so its enrolled
controller key and operational USB state are not affected.

Completed sanitization:

- Removed the generated identity/controller.pub from the source checkout.
- Excluded Python bytecode caches and added ignore rules for future caches.
- Excluded upstream `_manifest` build-provenance and SBOM metadata; runtime
  does not reference it, while the per-architecture OpenSSH licenses and
  notices remain included.
- Added ignore rules for generated public enrollment keys and runtime logs.
- Added MIT licensing and a third-party notice for the bundled OpenSSH payload.
- Kept example private addresses used by tests and documentation; no actual
  target address is required by the package.
- Regenerated SHA256SUMS.txt for this checkout after sanitization.

Before publishing, review the Git diff and repository metadata once more after
choosing the public hosting location. Do not commit a controller private key,
generated public key, target endpoint file, service log, or proxy subscription
URL.
