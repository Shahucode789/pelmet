#!/usr/bin/env python3
"""Select upstream releases and prepare a strictly patched personal build."""
import hashlib, json, os, pathlib, subprocess, urllib.request, urllib.parse, urllib.error
ROOT = pathlib.Path(__file__).resolve().parent
REPO = os.environ['GITHUB_REPOSITORY']
BASE = 'cbe38e19a54a3f4e3707509b52ec0ad92b6ad416'
def api(path):
    req = urllib.request.Request('https://api.github.com/' + path, headers={
        'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(req) as response: return json.load(response)
releases = api('repos/fif7y/pelmet/releases?per_page=100')
release = max((r for r in releases if not r['draft']), key=lambda r: r['published_at'])
tag = release['tag_name']
commit = api('repos/fif7y/pelmet/commits/' + urllib.parse.quote(tag, safe=''))['sha']
patch = ROOT / 'native-now-playing.patch'
key = (ROOT / 'update-public-key.txt').read_text().strip()
assert len(key) == 44
inputs = hashlib.sha256()
for name in ['native-now-playing.patch','update-public-key.txt','prepare-update.py','.github/workflows/build-pelmet.yml']:
    inputs.update((ROOT/name).read_bytes())
fingerprint = commit + ':' + inputs.hexdigest()
try:
    previous = api(f'repos/{REPO}/releases/latest')
    unchanged = f'Build fingerprint: {fingerprint}' in (previous.get('body') or '')
except urllib.error.HTTPError as e:
    if e.code != 404: raise
    unchanged = False
with open(os.environ['GITHUB_OUTPUT'],'a') as out:
    out.write(f'needed={str(not unchanged).lower()}\n')
if unchanged:
    print('Latest upstream release is already patched and published.'); raise SystemExit(0)
subprocess.run(['git','clone','--filter=blob:none','https://github.com/fif7y/pelmet.git','upstream-build'],check=True)
subprocess.run(['git','checkout','--detach',commit],cwd='upstream-build',check=True)
# Refuse an upstream release older than the user's original beta build.
subprocess.run(['git','merge-base','--is-ancestor',BASE,commit],cwd='upstream-build',check=True)
subprocess.run(['git','apply','--check',str(patch)],cwd='upstream-build',check=True)
subprocess.run(['git','apply',str(patch)],cwd='upstream-build',check=True)
project = pathlib.Path('upstream-build/project.yml')
text = project.read_text()
old_feed = 'SUFeedURL: https://fif7y.github.io/pelmet/appcast.xml'
old_key = 'SUPublicEDKey: HyfGTw9yRC/C2CUxxamEhzxZuK+WWuG7WPI6F+BUOgE='
assert text.count(old_feed) == text.count(old_key) == 1, 'Upstream updater configuration changed; review required.'
text = text.replace(old_feed, f'SUFeedURL: https://github.com/{REPO}/releases/latest/download/appcast.xml')
text = text.replace(old_key, f'SUPublicEDKey: {key}\n        SURequireSignedFeed: true\n        SUVerifyUpdateBeforeExtraction: true')
project.write_text(text)
settings = pathlib.Path('upstream-build/Packages/PelmetCore/Sources/PelmetCore/SettingsStore.swift').read_text()
assert 'hideSystemExtras || replacesCollateralExtras' not in settings
assert 'public var effectiveHideSystemExtras: Bool {\n        hideSystemExtras\n    }' in settings
media = pathlib.Path('upstream-build/Pelmet/Extras/MediaControls.swift').read_text()
assert 'visible = active\n' in media and 'appState.openAudioVideoPill' in media
notes = f'''Personal Pelmet build with native-controls patch.\n\nUpstream: fif7y/pelmet@{commit} ({tag})\nBuild fingerprint: {fingerprint}\n\nUpdates come only from this fork and retain the patch. Conflicts or failed tests stop publication.\nPelmet camera/mic icons open Apple's own effects panel while hardware is active.\nNative Now Playing is preserved while the bar is revealed, not during assessment-mode concealment.\nAd-hoc signed; not Apple-notarized.\n'''
pathlib.Path('build-notes.md').write_text(notes)
pathlib.Path('upstream-version.txt').write_text(tag.removeprefix('v'))
print(f'Preparing {tag} at {commit}; strict patch application succeeded.')
