"""Atomically refresh the public KOReader account catalog using Python's stdlib."""
import argparse
import json
import os
from pathlib import Path
import re
import ssl
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

OWNER = 'bailigebai'
ROOT = Path(__file__).resolve().parents[1]
BASE_URL = 'https://api.github.com'


def api(path, *, missing_ok=False):
    headers = {'Accept': 'application/vnd.github+json',
               'User-Agent': 'qiqiappstore-catalog', 'X-GitHub-Api-Version': '2022-11-28'}
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(BASE_URL + path, headers=headers)
    # Only retry read-only requests after temporary service or transport errors.
    # Rate limits and authentication/visibility errors must remain failures.
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if missing_ok and error.code == 404:
                return False
            if error.code not in (502, 503, 504) or attempt == 2:
                raise RuntimeError(f'GitHub HTTP {error.code}: {path}') from None
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            reason = getattr(error, 'reason', error)
            if isinstance(reason, ssl.SSLCertVerificationError) or attempt == 2:
                raise RuntimeError(f'GitHub request failed: {path}') from None
        except ValueError:
            raise RuntimeError(f'GitHub returned invalid JSON: {path}') from None
        time.sleep(0.5 * (attempt + 1))


def public_plugin(repo):
    if not isinstance(repo, dict):
        return False
    name = repo.get('name')
    owner = repo.get('owner')
    return (isinstance(name, str) and name != '.koplugin' and '..' not in name
            and re.fullmatch(r'[A-Za-z0-9_.-]+\.koplugin', name) is not None
            and isinstance(owner, dict) and str(owner.get('login', '')).lower() == OWNER
            and repo.get('private') is False
            and str(repo.get('full_name', '')).lower() == f'{OWNER}/{name}'.lower())


def build():
    repos, seen, page = [], set(), 1
    while True:
        listing = api(f'/users/{OWNER}/repos?type=owner&sort=full_name&direction=asc&per_page=100&page={page}')
        if not isinstance(listing, list):
            raise RuntimeError('GitHub returned an incomplete repository list')
        for repo in listing:
            if not isinstance(repo, dict) or not isinstance(repo.get('name'), str) or not isinstance(repo.get('id'), int):
                raise RuntimeError('GitHub returned malformed repository metadata')
            if not public_plugin(repo):
                continue
            identity = repo['full_name'].lower()
            if identity in seen:
                raise RuntimeError('GitHub returned duplicate repository identities')
            seen.add(identity)
            repos.append(repo)
        if len(listing) < 100:
            break
        page += 1

    entries = []
    for repo in sorted(repos, key=lambda value: value['full_name'].lower()):
        path = f'/repos/{OWNER}/' + urllib.parse.quote(repo['name'], safe='')
        metadata = api(path)
        if not public_plugin(metadata) or metadata['id'] != repo['id'] or metadata['full_name'].lower() != repo['full_name'].lower():
            raise RuntimeError(f'Repository identity or visibility changed: {repo["name"]}')
        branch = metadata.get('default_branch')
        if not isinstance(branch, str) or not branch:
            raise RuntimeError(f'Repository has no default branch: {repo["name"]}')
        tree = api(path + '/git/trees/' + urllib.parse.quote(branch, safe='') + '?recursive=1')
        if not isinstance(tree, dict) or tree.get('truncated') is not False or not isinstance(tree.get('tree'), list):
            raise RuntimeError(f'Repository tree is incomplete: {repo["name"]}')
        sha = tree.get('sha')
        if not isinstance(sha, str) or re.fullmatch(r'(?:[a-f0-9]{40}|[a-f0-9]{64})', sha) is None \
                or tree.get('url') != BASE_URL + path + '/git/trees/' + sha:
            raise RuntimeError(f'Repository tree identity is invalid: {repo["name"]}')
        release = api(path + '/releases/latest', missing_ok=True)
        if release is not False and (not isinstance(release, dict) or release.get('draft') is not False
                                     or not isinstance(release.get('assets'), list)):
            raise RuntimeError(f'Release metadata is incomplete: {repo["name"]}')
        entries.append({'metadata': metadata, 'tree': tree, 'release': release})
    return {'schema_version': 1, 'owner': OWNER, 'generated_at': int(time.time()), 'repos': entries}


def write_catalog(document, destination):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n'
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', newline='\n',
                                         dir=destination.parent, prefix='.catalog-', suffix='.tmp', delete=False) as output:
            temporary = Path(output.name)
            output.write(data)
        os.replace(temporary, destination)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'catalog.json')
    args = parser.parse_args()
    try:
        document = build()
        write_catalog(document, args.output)
    except RuntimeError as error:
        print(f'Catalog unchanged: {error}', file=sys.stderr)
        return 1
    print(f'Updated {len(document["repos"])} public .koplugin repositories: {args.output}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
