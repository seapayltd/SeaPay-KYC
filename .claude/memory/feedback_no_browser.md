---
name: No browser for verification
description: All verification flows must happen natively inside the app — never redirect to Safari, SFSafariViewController, or any external browser
type: feedback
---

All verification must happen inside the OceanCheck app natively. Never open Safari, SFSafariViewController, or any browser for the verification flow. The subject must capture documents and selfie using the app's own camera and upload UI.

**Why:** The app must force installation and native usage to drive app adoption and maintain control of the experience. Browser-based flows break this.

**How to apply:** The subject flow captures ID photos + selfie natively within the app, then submits them via the standalone API endpoints. The subject's device uses the agent's session context (passed via code/QR) but calls the APIs directly. If the subject doesn't have an API key, the app must handle this by either: (a) embedding a temporary token in the QR/invite, or (b) using a session-based submission that doesn't require the subject to have their own key.
