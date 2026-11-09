# Security policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report privately through GitHub: the repository's **Security** tab → **Report a vulnerability**
(GitHub private vulnerability reporting). Include steps to reproduce and the affected version. You should get a reply within a reasonable time; this is a volunteer project.

## Supported versions

Only the latest commit on the default branch is supported while the project is pre-1.0.

## Security model and known limits

- **Local, with one exception.** The only network request is for an X post saved without its text: TaskDock
  asks X's public embed service (`https://publish.twitter.com/oembed`, with `dnt=true`) for that post, sending only
  the post's public link. The browser bridge listens on `127.0.0.1:47123` (loopback interface only).
- **Saved posts over the bridge.** Anything that can connect to the bridge (see below) can add X posts to the saved
  list and read the saved posts' ids. The app keeps only the post id and handle taken from a valid x.com or
  twitter.com post link, so a forged message can't add other links. The x.com content script reads only the posts
  on the page and sends them only to the extension.
- **Bridge access check is weak by design.** The bridge accepts WebSocket connections whose `Origin`
  starts with `chrome-extension://`. Any installed browser extension, or any local process (which can
  set any `Origin` header), can connect and read the current task's name, icon, goal and start time.
  Clients cannot control TaskDock: incoming messages other than `hello`/`ping` are ignored.
  Messages are capped at 64 KB.
- **System changes.** TaskDock rewrites `com.apple.dock` preferences, restarts the Dock, hides apps,
  and runs Apple Shortcuts by the names you configure (`/usr/bin/shortcuts run <name>`, no shell).
- **Calendar data** is read locally through EventKit only after you grant access.
- Builds are ad-hoc signed and not notarized.
