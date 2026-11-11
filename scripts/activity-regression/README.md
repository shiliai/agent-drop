# Activity completion regression (#29)

Run `scripts/activity-regression/run.sh` on macOS. This compiles the production
Activity view with an isolated 100-row fixture. It does not transfer files or read
or modify the user's history. Close the fixture window and quit the fixture app
when finished.

1. Keep All selected. The first row starts in In Progress (1).
2. Click Complete transfer without changing tabs or refreshing.
3. Check that Recent (100) contains activity-demo.txt showing Completed, a Finish
   time, and Copy paths. The former Uploading indicator must disappear.
4. Click its Copy paths action. `pbpaste` must return
   `~/.agent-inbox/activity-demo.txt`.
5. Select Completed. The first row must still have the same completion data and
   action; older rows must remain visible. Active must contain no transfers.

Before the fix, step 3 reproduced the reported defect: the header changed to
Recent (100), but the first row kept its running snapshot without Copy paths.
After the fix, steps 1–5 passed using the native macOS accessibility UI on
2026-11-06. This fixture exercises SwiftUI updates and clipboard copying; it does
not claim network transfer coverage.

## Interrupted recovery and empty-file progress

Run `scripts/activity-regression/run.sh --recovery`. The production Activity view
starts with a history-only running entry whose progress comes from the macOS
rsync empty-file output (`0 nan% 00:00:00`). This mode uses an isolated history
store and a simulated executor; it never starts SSH or accesses user history.

1. The row renders without crashing and has a Resume interrupted transfer action.
2. Click Resume, then Cancel in the confirmation. The row remains running.
3. Click Resume again and confirm Resume. A new Completed row with Copy paths
   appears; the original row becomes Cancelled with an interruption explanation.
4. Select Active. It must show No Active Transfers.

These steps passed through native macOS accessibility on 2026-11-11. The
[screenshot](../../docs/assets/interrupted-transfer-recovery.png) shows the result.
Actual partial-byte reuse is covered separately by `ResumableTransferTests`,
using real local rsync and a transport fixture in place of SSH.
