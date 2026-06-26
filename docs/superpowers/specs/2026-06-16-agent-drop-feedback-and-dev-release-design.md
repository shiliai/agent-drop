# Agent Drop Upload History And Developer Release Design

## Summary

This design covers two related pieces of work:

1. Issue #2: add a reliable in-app upload history so Finder uploads have durable feedback, even when macOS notifications from the Finder Sync extension are unreliable.
2. A new release issue: add GitHub-based developer builds for open-source users who can accept manual macOS trust and Finder extension setup, without requiring Apple Developer Program membership in the first release path.

The current V1 upload behavior remains unchanged: Finder sends selected files to `~/.agent-inbox/YYYY-MM-DD/` on the selected SSH target and copies final remote paths to the local clipboard.

## Goals

- Show recent upload attempts inside the Agent Drop app.
- Persist upload history locally so it survives app relaunch.
- Record both success and failure outcomes from Finder uploads.
- Let users copy uploaded remote path(s) again from the app.
- Keep Finder badges as quick inline feedback.
- Provide a GitHub Actions developer build path for open-source users.
- Document the manual steps needed to run an unsigned or ad-hoc developer build on macOS.
- Keep Developer ID signing, notarization, Homebrew, and auto-update out of the first release automation.

## Non-Goals

- No prompt generation.
- No remote file browsing.
- No retry upload button in issue #2.
- No full diagnostics console in issue #2.
- No Apple Developer Program requirement for the first GitHub build issue.
- No Developer ID signing or notarization in the first GitHub build issue.
- No Homebrew Cask or Sparkle auto-update in the first GitHub build issue.

## Issue #2: In-App Upload History

### User Experience

The Agent Drop app window should become the reliable feedback surface.

The first screen should show a compact `Recent Uploads` list with:

- Time.
- SSH target.
- File count.
- Status.
- A short summary.

Selecting a row shows detail for that upload:

- Target name.
- Upload time.
- Status: success, failed, or partial if introduced later.
- Original local file names.
- Final remote paths for successful uploads.
- Short failure message for failed uploads.
- A `Copy Paths` action for successful uploads.

The existing setup text can remain, but it should be secondary to the upload history. Agent Drop should feel like a small utility app, not only an instruction window.

### Data Model

Add a small shared history model in `AgentDropCore`:

```text
UploadHistoryEntry
  id
  createdAt
  targetName
  status
  localFileNames
  remoteDisplayPaths
  errorMessage
```

`status` should start with:

- `succeeded`
- `failed`

The entry should be Codable so it can be written as JSON.

### Storage

The Finder Sync extension and main app are separate processes with separate containers by default. Apple recommends App Groups for first-class sharing between a containing app and its extensions, but App Groups would pull this project toward paid-team provisioning and signing assumptions earlier than we want.

For the developer-tool release path, use the Finder Sync extension container as the history source of truth:

```text
~/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json
```

The extension writes history there after each Finder upload. The main app reads the same file for display. To keep this no-paid-account path practical, the containing app should be unsandboxed for developer builds, while the Finder Sync extension remains sandboxed.

Both targets should access the history through a small `UploadHistoryStore` boundary in `AgentDropCore`, so a later Developer ID/App Group release can migrate to a true shared app group container without rewriting UI or Finder upload code.

The store should:

- Create the directory if missing.
- Append new entries.
- Keep only the most recent 100 entries.
- Write atomically where practical.
- Handle corrupt JSON by preserving the bad file with a `.corrupt-<timestamp>` suffix and starting a fresh history.

Because Finder uploads are user-triggered and short, a simple file lock or serial write boundary is enough for V1. We do not need a database.

### Finder Sync Behavior

After a Finder upload completes:

- On success, write a succeeded history entry with copied remote paths.
- On failure, write a failed history entry with file names, target, and short error text.
- Keep the existing Finder badge behavior.
- Continue best-effort notification delivery, but do not rely on it as the primary feedback.

The extension should not open or focus the app after every upload in V1. That would make a fast Finder workflow feel noisy. The user can open Agent Drop when they want to inspect history.

### App Behavior

The main app should:

- Load recent upload history on launch.
- Refresh history when the window becomes active.
- Show an empty state before the first upload.
- Let users copy remote paths from a successful history row.
- Show a small status or toast after copying paths again.

No live background watcher is required for V1. A manual or activation refresh is enough.

### Error Handling

- If history write fails, upload behavior still completes and diagnostics should record the history failure.
- If history read fails because the JSON is corrupt, preserve the corrupt file and show an empty history.
- If a failed upload has a long technical error, store the full string only if it is reasonably short; otherwise store a concise display message and keep full diagnostics in the existing log file.
- If clipboard copy from the app fails, show a visible message in the app and leave the history unchanged.

### Testing

Add focused tests for:

- Encoding and decoding history entries.
- Appending entries.
- Trimming to 100 entries.
- Preserving order newest-first in the app-facing API.
- Handling missing history files.
- Handling corrupt JSON.
- Copy payload formatting for selected entries.

Manual verification should cover:

- Finder successful upload creates a history row.
- Finder failed upload creates a failed history row.
- Relaunching Agent Drop keeps history.
- Copying paths from history updates the clipboard.
- Existing Finder badges still appear.

## New Issue: GitHub Developer Build Release

### Product Positioning

Agent Drop is currently a developer tool for open-source users. The first publishable build should optimize for developers who are comfortable with:

- Reading source.
- Building locally if needed.
- Manually approving an unsigned or ad-hoc signed macOS app.
- Manually enabling a Finder Sync extension.

This release path should not promise the polish of a notarized consumer app.

### Release Artifacts

GitHub Actions should produce:

- A test result from `swift test`.
- A no-signing build check with `xcodebuild ... CODE_SIGNING_ALLOWED=NO`.
- A zipped `Agent Drop.app` artifact when possible.
- Release notes or install instructions that explain manual trust and Finder extension setup.

The artifact can initially be attached to workflow runs. A follow-up step can attach it to GitHub Releases on version tags.

### Install Documentation

README or a dedicated install doc should explain:

1. Download the developer build artifact or clone and build from source.
2. Move `Agent Drop.app` to `/Applications` or `~/Applications`.
3. Open the app once.
4. If macOS blocks the app, use Privacy & Security to allow opening it.
5. Enable the Finder extension in System Settings.
6. Restart Finder if the menu does not appear.
7. Verify with a small Finder upload.

The doc should clearly label this as a developer build, not a notarized public release.

### CI Shape

Use GitHub Actions on macOS:

```text
pull_request / push:
  swift test
  xcodegen generate
  xcodebuild build CODE_SIGNING_ALLOWED=NO

tag v*:
  same checks
  package developer artifact
  attach artifact to GitHub Release
```

The workflow should not require Apple signing secrets for the first version.

### Future Upgrade Path

Keep the workflow structured so a later issue can add:

- Apple Developer Program membership.
- Developer ID Application certificate.
- Notarization credentials.
- Stapled DMG or ZIP.
- Homebrew Cask.
- Automatic update feed.

Those are deliberately deferred because they add account cost and secret management before the project has enough external users to justify it.

## Risks And Mitigations

- Finder extension and app history sharing can be brittle because they do not share a container by default. Mitigation: centralize the extension-container history path in `AgentDropCore`, keep the containing app unsandboxed for developer builds, and reserve an App Group migration for a later signed release.
- Unsigned developer builds can confuse users. Mitigation: label the artifact as a developer build and provide explicit setup steps.
- History storage can grow over time. Mitigation: keep only the latest 100 entries.
- History may contain remote path names that reveal project context. Mitigation: store locally only and do not upload telemetry.

## Acceptance Criteria

Issue #2 is complete when:

- Finder uploads create durable in-app history entries.
- Successful entries show copyable remote paths.
- Failed entries show a concise error.
- History survives relaunch.
- Existing tests pass, and new history tests cover the storage behavior.

The new release issue is ready when:

- A GitHub issue exists describing the developer build release scope.
- The issue states that Developer ID signing and notarization are deferred.
- The issue includes CI, artifact, and install-documentation acceptance criteria.
