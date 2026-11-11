# Empty-file crash and interrupted Activity recovery

Scope: code-review delivery for the user's two reports: repeated installed-app
crashes and inability to restart/resume stopped transfers. No release, installed
app replacement, or automatic restart of user transfers is included.

Baseline revision: user reports dated 2026-11-11 (crash and interrupted transfer
screenshots). These reports authorize the bounded fixes below.

| Story | Given / When / Then | Evidence | Status |
| --- | --- | --- | --- |
| CRASH-1: As a transfer user, I want empty-file progress to render without terminating the app so that transfers remain usable. | Given macOS rsync output with `nan%`, when progress is parsed and displayed, then the percentage is unknown and formatting/persistence succeeds. | Old regression exited with SIGTRAP and `Double value cannot be converted to Int`; real `/usr/bin/rsync` empty-file test passes after fix. Production Activity view renders the fixture without crashing. | Complete for code-review delivery |
| RECOVER-1: As a transfer user, I want to resume an interrupted history entry so that I can finish the original transfer. | Given a running record outside this queue, when I confirm its original worker has stopped and choose Resume, then a new attempt uses the original host/source, the old entry exits Active, and retained partial files can be reused. Cancelling confirmation must leave history unchanged. | Queue tests prove original request, duplicate-click guard, retired history persistence and legacy download recovery. Native Activity fixture proves cancel/confirm, completed row and empty Active filter. Four existing real-rsync cancellation/resume tests verify matched bytes for file/directory upload/download. SSH is replaced by the test transport. | Complete for code-review delivery |

Validation:

- `swift test --filter 'TransferProgressTests|RsyncProgressCompatibilityTests|TransferQueueTests|ResumableTransferTests'`: 42 tests, zero failures.
- `xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO`: BUILD SUCCEEDED (app and Finder extension).
- `scripts/activity-regression/run.sh --recovery`: native UI flow passed; screenshot in `docs/assets/interrupted-transfer-recovery.png`.

Safety boundaries: no automatic recovery of an external running record. The UI
asks the user to confirm the original worker has stopped because history does not
contain reliable process ownership. Missing legacy upload paths require file
selection; paths are never guessed. Source changes or missing partial files can
require a fresh transfer. Existing checksum validation and output naming remain
in effect.

Alignment playback: CRASH-1 and RECOVER-1 Complete for the stated code-review
subject, drift 0, ALIGNED. Installed-app upgrade, live remote interrupted records,
full integrated release regression and release acceptance remain unverified.
