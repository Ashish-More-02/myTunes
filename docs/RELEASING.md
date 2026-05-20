# Creating a new GitHub release

A short, repeatable checklist for cutting a new myTunes release. Two paths — pick whichever fits your mood.

> **Versioning rule of thumb:** `vMAJOR.MINOR.PATCH`
> - **MAJOR** — breaking changes
> - **MINOR** — new features, backwards compatible
> - **PATCH** — bug fixes, polish, small tweaks
>
> Always prefix the tag with `v` (e.g. `v1.0.2`, not `1.0.2`).

---

## Before you start (every release)

1. Commit and push all your code changes to `master`.
2. Rebuild the app so the binary inside `myTunes.app/` matches the source:
   ```bash
   cd ~/Desktop/myTunes
   ./build_app.sh
   ```
3. Open the rebuilt `myTunes.app`, click around for 30 seconds, confirm nothing is obviously broken.

Decide your version number. Look at the latest tag and bump accordingly:
```bash
git tag --list --sort=-v:refname | head -3
```

---

## Path A — From the terminal (fastest, ~30 seconds)

Pick a `VERSION` and run the four blocks in order.

```bash
# Set the version once
VERSION=v1.0.3

# 1. Tag the commit and push the tag
git tag -a "$VERSION" -m "myTunes $VERSION"
git push origin "$VERSION"

# 2. Zip the app bundle for users to download
zip -r "myTunes-${VERSION}-macOS.zip" myTunes.app -x "*.DS_Store"

# 3. Create the release and attach the zip
gh release create "$VERSION" "myTunes-${VERSION}-macOS.zip" \
  --title "myTunes $VERSION" \
  --notes "What's new in this release.

## Fixes
- ...

## Install
1. Download the zip below
2. Unzip and drag myTunes.app into /Applications
3. First launch: right-click → Open (Gatekeeper bypass)

Requires macOS 13.0 or later."

# 4. Confirm it published
gh release view "$VERSION" --web
```

### Multi-line release notes (nicer)

If you want richer notes than a single `--notes "..."` string, use a heredoc:

```bash
gh release create "$VERSION" "myTunes-${VERSION}-macOS.zip" \
  --title "myTunes $VERSION" \
  --notes "$(cat <<'EOF'
Short summary of the release goes here.

## Fixes
- Bug fix one
- Bug fix two

## New
- Shiny new feature

## Install
1. Download **myTunes-${VERSION}-macOS.zip** below
2. Unzip and drag **myTunes.app** into **/Applications**
3. First launch: **right-click → Open** to bypass Gatekeeper

**Full changelog:** https://github.com/Ashish-More-02/myTunes/compare/v1.0.2...$VERSION
EOF
)"
```

### Useful variations

| Goal | Command |
|---|---|
| Save as a **draft** first (don't publish yet) | add `--draft` to `gh release create` |
| Mark as a **pre-release** (beta/RC) | add `--prerelease` |
| **Auto-generate** notes from commits since last tag | add `--generate-notes` (skip `--notes`) |
| Attach **more files** | list them after the version: `gh release create v1.0.3 file1.zip file2.dmg` |
| **Edit** notes after publishing | `gh release edit v1.0.3 --notes "new text"` |
| **Delete** a release (keeps the tag) | `gh release delete v1.0.3` |
| Delete the **tag** too | `git push origin :refs/tags/v1.0.3 && git tag -d v1.0.3` |

### One-time `gh` setup (if you've never used it)

```bash
brew install gh
gh auth login            # follow the prompts, pick HTTPS + browser auth
gh auth status           # should show your account
```

---

## Path B — From the GitHub website

If you'd rather click than type.

### 1. Push your tag first (optional but cleanest)

```bash
git tag -a v1.0.3 -m "myTunes v1.0.3"
git push origin v1.0.3
```

You can also let GitHub create the tag when you publish — both work.

### 2. Open the new release page

Go to **https://github.com/Ashish-More-02/myTunes/releases/new**

(Or: repo home → **Releases** in the right sidebar → **Draft a new release**.)

### 3. Fill in the form

| Field | What to enter |
|---|---|
| **Choose a tag** | Pick `v1.0.3` from the dropdown. If it's not there, type it and select **"Create new tag: v1.0.3 on publish"**. |
| **Target** | Leave on `master`. |
| **Release title** | `myTunes v1.0.3` |
| **Describe this release** | Paste markdown notes (highlights, fixes, install steps). Click **"Generate release notes"** at the top right to auto-fill from commit messages, then edit. |
| **Attach binaries** | Drag your `myTunes-v1.0.3-macOS.zip` into the box at the bottom that says "Attach binaries by dropping them here…". |
| **Set as a pre-release** | Tick only for beta/RC builds. |
| **Set as the latest release** | Leave checked. |

### 4. Publish

- **Publish release** — goes live immediately, visible to everyone.
- **Save draft** — saves privately so you can come back and finish later. Find drafts at `Releases` → top of the list, marked **Draft**.

### 5. Verify

Open the release URL it gives you, click the zip to confirm it downloads, then check it shows up at the top of https://github.com/Ashish-More-02/myTunes/releases.

---

## Quick reference card

```
# A new release in 5 commands
VERSION=v1.0.3
./build_app.sh
git tag -a "$VERSION" -m "myTunes $VERSION" && git push origin "$VERSION"
zip -r "myTunes-${VERSION}-macOS.zip" myTunes.app -x "*.DS_Store"
gh release create "$VERSION" "myTunes-${VERSION}-macOS.zip" \
  --title "myTunes $VERSION" --generate-notes
```

---

## Gotchas worth remembering

- **Tag the right commit.** `git tag` tags whatever `HEAD` points to. Run `git log -1` first to make sure that's the commit you want to ship.
- **Rebuild the `.app` before zipping.** It's easy to push source changes but forget to run `./build_app.sh` — users would then get a binary that doesn't match the tag.
- **Don't reuse a version number.** Once `v1.0.3` is out and people might have downloaded it, bump to `v1.0.4` for any change. Deleting and re-tagging the same version is messy.
- **Gatekeeper warning is expected** for unsigned builds. Always tell users to right-click → Open the first time, or you'll get bug reports that aren't bugs.
- **The zip filename matters.** Keeping the format `myTunes-vX.Y.Z-macOS.zip` makes the Releases page easy to scan.
