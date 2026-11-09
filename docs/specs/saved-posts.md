# Saved X posts

Status: built 2026-11-09. Approved choices: Articles/ monthly note, embed fetch allowed, Share Shortcut. Tests: `PostsTests`, `extension/lib.test.js`, `scripts/e2e-posts.sh`.

## Goal

I read X every day and write one article a month based on it. I want to save any post in one action, from the Mac browser or the iPhone, into a single list that keeps the link and the exact text. When it's time to write, I go through the list, add my thoughts, and press one button to get an Obsidian note with everything in it.

## User flows

**Save in the browser (Mac).**

1. On x.com, every post gets a small ◎ button next to X's own bookmark button.
2. One click saves the post. The button turns into a check (✓), and the check stays on that post on every later visit.
3. A small "Add a thought…" field appears under the button.
   - Type and press ↩ to attach a note.
   - Ignore it and it disappears after 5 seconds.
   - Esc closes it at once.
4. Fallback if X changes its page and the button doesn't show: right-click any post link and choose **Save post to TaskDock**.
5. If the TaskDock app isn't running, the extension keeps the saves and sends them when the app is back. Nothing is lost.

**Save on iPhone or iPad.**

1. In the X app: Share, then **Save to TaskDock**. This is an Apple Shortcut I set up once; the README gives the steps.
2. The Shortcut asks "Thought? (optional)". Tap Done to skip.
3. It adds one line, the link plus your note, to `iCloud Drive/Shortcuts/TaskDock/inbox.txt`.
4. On the Mac, TaskDock picks up new lines within a minute. It then gets the post's exact text, author and date from X's public embed service (`publish.twitter.com/oembed`, no account or API key needed; tested 2026-11-09).

**Review and write (Mac).**

1. In the ◎ menu, **Saved Posts (12 new)** opens the list window.
2. Each row shows the author, @handle, post date, the full post text, your note (editable in place), **Open on X**, and a delete button.
3. The list is newest first, with a **New / All** switch. "New" means not yet used in an article.
4. Each new post has a checkbox, checked by default.
5. **Start writing** creates `Articles/Posts – November 2026.md` in your Obsidian vault with every checked post, and opens it in Obsidian.
   - If that note already exists, the new posts are added at the end. Nothing is ever overwritten.
   - The included posts are marked as used and move out of "New".

The note looks like this:

```markdown
# Posts – November 2026

## Jack (@jack) · 21 Mar 2006
> just setting up my twttr

https://x.com/jack/status/20

My take: first post ever, compare with how X describes itself now
```

## Design

### Extension (`extension/`)

- **New content script on x.com and twitter.com.** For each post (`article[data-testid="tweet"]`), it adds the ◎ button to the action row.
- **What it reads from the page:**
  - the post link and id, from the post's timestamp link;
  - the date (`time[datetime]`);
  - the name and @handle (`[data-testid="User-Name"]`);
  - the text (`[data-testid="tweetText"]`).
- **Long posts.** If X shows "Show more", the text in the timeline is cut off. The save is then marked "partial", and the app fetches the full text from the embed service.
- **New permissions.**
  - Access to `x.com` and `twitter.com`, for the button.
  - `contextMenus`, for the right-click fallback.

  Chrome will ask once when you reload the extension.
- **New bridge messages.**
  - Extension to app: `save-post` (the post) and `post-note` (id plus note).
  - App to extension: `saved-ids`, so a check shows on posts you already saved, even ones saved from the phone.
- **Offline queue.** Unsent saves wait in `storage.local` and go out on reconnect.

### App (`Sources/TaskDock/`)

- **New file `Posts.swift`.**
  - Model: `Post { id, url, author, handle, text, postedAt, savedAt, note, partial, usedIn }`.
  - Stored in `~/Library/Application Support/TaskDock/posts.json`.
  - Saving the same post twice keeps one entry. Its note is kept, and missing text is filled in.
- **Inbox reader.**
  - Reads `~/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/TaskDock/inbox.txt` on the existing timer.
  - Skips post ids already in the list.
  - Only reads that file, never writes to it, so it can't fight with iCloud sync.
- **Embed fetch.** Used only for posts saved without their text (phone, right-click, partial). If it fails (offline, deleted or private post), the post keeps its link and is labelled "Text not captured yet". The fetch is retried on the next launch.
- **List window.** Built the same way as the Templates window, and follows the system light/dark setting.
- **Start writing.**
  - Finds the vault from Obsidian's own list of vaults (`obsidian.json`). Yours is `~/Documents/Obsidian Vault`.
  - Writes the note.
  - Opens it with `obsidian://open?path=…`.

### Privacy change

The README says "Nothing is sent over the network." That changes: for posts saved without their text, TaskDock asks X's public embed service for that post. The request contains only the post's public link. The README and SECURITY.md need to say this.

## Tests

- **Unit (XCTest):**
  - merging a duplicate post (note kept, text filled);
  - parsing inbox lines;
  - parsing the embed response into text, author and date;
  - building the Markdown note, including appending to an existing note.
- **Extension (`node --test`):** parsing post links and ids, and building the message.
- **End-to-end:**
  - the existing fake browser sends `save-post`, and the post appears in `posts.json`;
  - an inbox line becomes a post;
  - Start writing on a temporary vault produces the expected note and marks the posts used.
- **Live, once:**
  - save a real post on x.com, including a long one;
  - save from the iPhone Shortcut;
  - Start writing into the real vault.

## Out of scope

- The X API.
- Saving a whole thread. Each post is saved on its own; save several to keep a thread.
- Downloading images or video. The link keeps them.
- The native X app on the Mac (use Share, then copy the link into the browser).
- Writing the article inside TaskDock.

## Decisions to confirm

1. The Obsidian note goes in an `Articles/` folder, created if missing, as one note per month: "Posts – November 2026".
2. TaskDock may contact X's public embed service for posts saved without their text. This is the only network use.
3. The iPhone path is the Share-menu Shortcut. The alternative is to bookmark posts on X and have the extension import x.com/i/bookmarks on the Mac. That needs no setup, but it can't take a note at save time and only syncs when you open the bookmarks page.
