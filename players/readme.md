# Player images

This folder holds optional avatar images shown next to players on the leaderboards
(as the round face on the podium and beside each name in the list).

Images are anonymous: they are keyed by a random **player ID**, never by your Steam
account. Adding one is opt-in and done via a pull request that a moderator reviews and
approves.

## Requirements

- **Format:** PNG
- **Size:** exactly **256 x 256** pixels
- **File name:** `<your-player-id>.png` (see below for how to find your ID)
- **Location:** this `players/` folder

For example: `players/e5c02f61-4d29-4de0-8a8f-7668c4397d22.png`

## Finding your player ID

1. Open the **Leaderboards** page and find your name on any week you appear in.
2. **Right-click your name** and choose **Copy ID**.
3. That copies your player ID (a GUID like `e5c02f61-4d29-4de0-8a8f-7668c4397d22`) to
   your clipboard — this is the file name to use.

Your ID is stable across weeks, so a single image covers every board you're on.

## Submitting your image (pull request)

The easiest way is straight from the GitHub website — no git knowledge required:

1. Sign in to GitHub. If you don't have an account, create a free one at
   [github.com](https://github.com) first.
2. Rename your image file to `<your-player-id>.png` (256 x 256 PNG).
3. Open this `players/` folder on GitHub and click **Add file → Upload files**.
4. Drag your `<your-player-id>.png` in.
5. Under **Commit changes**, set the commit message to `Avatar for <your-player-id>`,
   choose **Create a new branch and start a pull request**, then **Propose changes** to
   open the pull request.

A moderator will then review and approve it. Please:

- only add your **own** image, and
- add just the one file per pull request.

Images that are offensive, misleading, or impersonate another player will be rejected.

Once merged, your avatar will appear on the leaderboards automatically. It may take a
few minutes to show up.

## Reporting an image

Spotted an image that's offensive, misleading, or impersonating someone — or want your
own image removed (for example, if someone added you without your permission)? Please
[open an issue](https://github.com/daemonus/plateup-speed-run-leaderboards/issues)
identifying the player ID (file name), and a moderator will review and remove it.
