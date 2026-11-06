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
