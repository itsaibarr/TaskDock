# Security policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report privately through GitHub: the repository's **Security** tab → **Report a vulnerability**
(GitHub private vulnerability reporting). Include steps to reproduce and the affected version. You should get a reply within a reasonable time; this is a volunteer project.

## Supported versions

Only the latest commit on the default branch is supported while the project is pre-1.0.

## Security model and known limits

- **Local only.** TaskDock makes no network requests. The browser bridge listens on
  `127.0.0.1:47123` (loopback interface only).
- **Bridge access check is weak by design.** The bridge accepts WebSocket connections whose `Origin`
  starts with `chrome-extension://`. Any installed browser extension, or any local process (which can
  set any `Origin` header), can connect and read the current task's name, icon, goal and start time.
  Clients cannot control TaskDock: incoming messages other than `hello`/`ping` are ignored.
  Messages are capped at 64 KB.
- **System changes.** TaskDock rewrites `com.apple.dock` preferences, restarts the Dock, hides apps,
  and runs Apple Shortcuts by the names you configure (`/usr/bin/shortcuts run <name>`, no shell).
- **Calendar data** is read locally through EventKit only after you grant access.
- Builds are ad-hoc signed and not notarized.
