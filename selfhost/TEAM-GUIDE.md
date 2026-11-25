# Using HumanLayer at Little Big Things

HumanLayer was bought by Factory and is shutting down its hosted service. The product is open source, so we forked it and now run our own copy. Day to day it works the way humanlayer.com did. This guide covers how to get on it and the handful of things that are different.

## The short version

| | humanlayer.com | Ours |
|---|---|---|
| App | app.humanlayer.com | https://humanlayer.littlebigthings.co |
| Admin (members, invites) | cloud.humanlayer.com | https://humanlayer-admin.littlebigthings.co |
| Sign-in | Any method | Google, with your @littlebigthings.co account |
| Desktop app | Yes | Not yet. Use the web app. |
| Command-line tool | `humanlayer` | `lbt-humanlayer` |
| Agent runs on | Your machine, your own Claude or Codex login | Same |
| Old tasks and sessions | There | Not moved. See "Your old work" below. |

## Getting started

### 1. Sign in

Go to https://humanlayer.littlebigthings.co and sign in with Google using your @littlebigthings.co account. Other accounts are refused.

If you were invited, accept the invite and you'll land in the Little Big Things organization. Don't create a new organization; ask Tim for an invite if you don't have one.

### 2. Install the command-line tool

Our build is called `lbt-humanlayer`. It is a separate program from the `humanlayer` command you may already have, and the two can sit side by side.

On an Apple Silicon Mac, run this in a terminal:

```bash
mkdir -p ~/bin
curl -fsSL -o ~/bin/lbt-humanlayer https://github.com/little-big-things/humanlayer/releases/download/cli-v0.40.0-lbt.1/humanlayer-darwin-arm64
chmod +x ~/bin/lbt-humanlayer
```

Builds for Intel Macs, Linux and Windows are on the same [release page](https://github.com/little-big-things/humanlayer/releases/tag/cli-v0.40.0-lbt.1). Only the Apple Silicon build has been tested.

Do not use the "Copy start command" button in the app. It gives you the stock HumanLayer command, which connects to their servers, not ours.

### 3. Connect your Mac

Run these in a terminal:

```bash
export HUMANLAYER_RIPTIDE_HOME=$HOME/.humanlayer-lbt
~/bin/lbt-humanlayer login
~/bin/lbt-humanlayer daemon launch
```

- The first line keeps this login separate from any existing HumanLayer login on your machine. Add it to your shell profile so you don't have to retype it.
- `login` opens a browser page. Sign in and pick the Little Big Things organization.
- `daemon launch` keeps running. Leave that terminal open while you work. Your Mac then shows as an online host in the app.

### 4. Add a project and start a task

In the app, go to Settings → Projects → Add project.

- **Repository:** use the HTTPS address, like `https://github.com/<owner>/<repo>.git`, unless you know your Mac has working SSH keys for GitHub. An SSH address without keys fails with "Permission denied (publickey)".
- **Path:** if the repo is already cloned on your Mac, enter that folder. Leave it blank and the daemon clones a fresh copy.
- Leave everything else as it is to start.

Then start a task as usual. Each task gets its own worktree and branch, so the agent never edits your main checkout.

## What's the same

- Tasks, sessions, the board, artifacts, and the research-plan-implement workflow.
- Agents run on your own machine with your own Claude Code or Codex login. Nothing about model access has changed.
- Task and session titles and summaries are generated for you.

## What's different or not working yet

- **No desktop app.** The web app is the only client for now.
- **Pull request status doesn't show.** The GitHub connection isn't set up yet. Pushing branches from your Mac works as normal.
- **Slack, Linear and Jira integrations are off.**
- **Welcome emails don't send.** Invites are sent by our login provider and should arrive, but we haven't tested that yet. If an invite doesn't show up, tell Tim.
- **We run it ourselves.** There's no vendor support. If something breaks, post in Slack and tag Tim.

## Your old work

Nothing was moved from humanlayer.com. Your existing tasks, sessions and artifacts stay there until HumanLayer turns the service off. They have not given a date, only "at least 30 days" from November 4, so treat early December as the cut-off. If there is anything you need from the old system, copy it out now.

Artifacts you created are also on your own Mac under `~/.humanlayer/riptide/artifacts`.

## Staging

There is a second copy at https://humanlayer-staging.littlebigthings.co that we use to try changes before they reach the real one. You don't need it for normal work. To point the command-line tool at it, add `--beta`:

```bash
~/bin/lbt-humanlayer --beta login
~/bin/lbt-humanlayer --beta daemon launch
```

## Troubleshooting

| What you see | What to do |
|---|---|
| "No hosts online" | Check the `daemon launch` terminal is still running. Restart it if not. |
| "Could not clone …" with "Permission denied (publickey)" | Change the project's repository to the HTTPS address, then Retry. |
| Sign-in refuses your account | Use your @littlebigthings.co Google account. |
| "This HumanLayer is limited to @littlebigthings.co email addresses" | Same cause: you're signed in with an outside email. |
| The daemon says another daemon is already running | Stop and ask Tim before forcing anything. |

## For the curious

- Our fork: https://github.com/little-big-things/humanlayer
- How it's hosted: `selfhost/README.md` in that repo
- It runs on Railway, with login through WorkOS.
