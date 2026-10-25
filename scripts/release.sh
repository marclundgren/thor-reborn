#!/bin/zsh
# Builds, signs and publishes a ThorReborn release, and adds it to the Sparkle feed.
#
#   scripts/release.sh 1.2.0 notes.md
#
# notes.md is Markdown (paragraphs and "- " bullets). It becomes the GitHub release notes
# and, converted to HTML, the update notes Sparkle shows in the app.
#
# Needs: Xcode, `gh` logged in, and the Sparkle EdDSA private key in the login keychain
# (account dev.thorreborn.ThorReborn). Run from a clean main branch.
set -euo pipefail

VERSION=${1:?usage: scripts/release.sh <version> <notes.md>}
NOTES=${2:?usage: scripts/release.sh <version> <notes.md>}
REPO=marclundgren/thor-reborn
KEY_ACCOUNT=dev.thorreborn.ThorReborn

cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
DD=build/release
PROJECT=ThorReborn.xcodeproj/project.pbxproj

[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean." >&2; exit 1; }
[[ -f "$NOTES" ]] || { echo "No notes file at $NOTES" >&2; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "Tag v$VERSION already exists." >&2; exit 1; }

# Bump the version. The build number (CFBundleVersion) is what Sparkle compares.
BUILD=$(( $(grep -m1 'CURRENT_PROJECT_VERSION = ' $PROJECT | grep -oE '[0-9]+') + 1 ))
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD;/; s/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = $VERSION;/" $PROJECT
echo "==> ThorReborn $VERSION ($BUILD)"

# Universal Release build, zipped for download.
xcodebuild -scheme ThorReborn -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath $DD build | grep -E '(error|BUILD)' || true
APP=$DD/Build/Products/Release/ThorReborn.app
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' $APP/Contents/Info.plist)" == "$BUILD" ]] \
  || { echo "Build failed." >&2; git checkout $PROJECT; exit 1; }
ZIP=$DD/ThorReborn.zip
rm -f $ZIP
ditto -c -k --sequesterRsrc --keepParent $APP $ZIP

# EdDSA signature for Sparkle; prints: sparkle:edSignature="…" length="…"
SIGN_UPDATE=$DD/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
SIGNATURE=$($SIGN_UPDATE --account $KEY_ACCOUNT $ZIP)

# Prepend the new item to the appcast.
python3 - "$VERSION" "$BUILD" "$SIGNATURE" "$NOTES" "$REPO" <<'EOF'
import email.utils, html, pathlib, sys
version, build, signature, notes_path, repo = sys.argv[1:]
lines = pathlib.Path(notes_path).read_text().strip().splitlines()
parts, bullets = [], []
for line in lines + [""]:
    if line.startswith("- "):
        bullets.append(f"<li>{html.escape(line[2:])}</li>")
        continue
    if bullets:
        parts.append("<ul>" + "".join(bullets) + "</ul>")
        bullets = []
    if line.strip():
        parts.append(f"<p>{html.escape(line)}</p>")
item = f"""    <item>
      <title>{version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{"".join(parts)}]]></description>
      <enclosure url="https://github.com/{repo}/releases/download/v{version}/ThorReborn.zip" type="application/octet-stream" {signature}/>
    </item>
"""
path = pathlib.Path("docs/appcast.xml")
text = path.read_text()
marker = "    <!-- releases, newest first -->\n"
path.write_text(text.replace(marker, marker + item, 1))
EOF

# Publish: release asset first, then the feed that points at it.
git add $PROJECT docs/appcast.xml
git commit -q -m "Release $VERSION"
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" $ZIP --repo $REPO --title "ThorReborn $VERSION" --notes-file "$NOTES" --verify-tag
echo "==> Published. The feed updates when GitHub Pages redeploys (about a minute)."
