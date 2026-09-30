#!/usr/bin/env python3
"""Finish distribution of the already validated and uploaded Vloh build."""
import json, os, sys, tempfile, time
from pathlib import Path
from datetime import datetime, timezone
from urllib.request import Request, urlopen
from urllib.parse import urlencode
from urllib.error import HTTPError
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'Vloh/scripts'))
from testflight import token

class AppleError(Exception):
    def __init__(self, status, errors):
        self.status = status
        self.errors = errors
        super().__init__('Apple API HTTP ' + str(status))

def main():
    signing = json.loads(os.environ.pop('EMBER_APPLE_SIGNING'))
    assert signing['team_id'] == '4BY949S88S'
    app_id, number = '6817912319', '10.1.0'
    output = ROOT / 'VlohRelease/receipt.json'
    receipt = {'app_id': app_id, 'bundle': 'com.maxyaport.vloh', 'build': number,
               'source': 'bb96d711f833968f38d6c3ca6aa5f969d5d5723a',
               'status': 'checking uploaded build and tester access'}
    def save(): output.write_text(json.dumps(receipt, indent=2))
    save()
    with tempfile.TemporaryDirectory(prefix='vloh-api-') as folder:
        key = Path(folder) / 'AuthKey.p8'
        key.write_text(signing['private_key']); key.chmod(0o600)
        def api(path, method='GET', body=None):
            request = Request('https://api.appstoreconnect.apple.com/v1/' + path,
                data=json.dumps(body).encode() if body else None, method=method,
                headers={'Authorization': 'Bearer ' + token(signing, key), 'Content-Type': 'application/json'})
            try:
                with urlopen(request, timeout=45) as response:
                    return json.load(response) if response.status != 204 else {}
            except HTTPError as error:
                try: errors = json.load(error).get('errors', [])
                except Exception: errors = []
                # No addresses, credentials or complete responses in public runner logs.
                print('Apple API HTTP ' + str(error.code) + ': ' + ', '.join(e.get('code', '') for e in errors), flush=True)
                raise AppleError(error.code, errors) from None
        app = api('apps/' + app_id)['data']
        assert app['attributes']['bundleId'] == receipt['bundle']
        deadline = time.monotonic() + 600
        while True:
            builds = api('builds?' + urlencode({'filter[app]': app_id, 'filter[version]': number}))['data']
            if builds:
                assert len(builds) == 1
                build = builds[0]
                state = build['attributes']['processingState']
                receipt['processing_state'] = state; save()
                if state == 'VALID': break
                if state in ['FAILED', 'INVALID']: raise RuntimeError('Apple processing rejected the uploaded build.')
            if time.monotonic() > deadline: raise RuntimeError('Apple processing is still pending.')
            print('Waiting for Apple processing.', flush=True); time.sleep(30)
        receipt['apple_build_id'] = build['id']; save()
        groups = api('betaGroups?' + urlencode({'filter[app]': app_id}))['data']
        group = next(g for g in groups if g['attributes']['name'] == 'Max — Internal Testing')
        assert group['attributes']['isInternalGroup'] and not group['attributes']['publicLinkEnabled']
        receipt['group_id'] = group['id']; save()
        localizations = api('builds/' + build['id'] + '/betaBuildLocalizations')['data']
        if not localizations:
            api('betaBuildLocalizations', 'POST', {'data': {'type': 'betaBuildLocalizations',
                'attributes': {'locale': 'en-US', 'whatsNew': 'Test recording and importing clips, trims and audio, saved drafts, private iCloud group invitations, playback, reactions and chat. Sign in to iCloud in iPhone Settings first.'},
                'relationships': {'build': {'data': {'type': 'builds', 'id': build['id']}}}}})
        attached = api('betaGroups/' + group['id'] + '/builds')['data']
        if not any(b['id'] == build['id'] for b in attached):
            api('betaGroups/' + group['id'] + '/relationships/builds', 'POST',
                {'data': [{'type': 'builds', 'id': build['id']}]})
        source_group = api('betaGroups/aed222f8-bdd7-4b26-9a8a-7618e3a65278')['data']
        assert source_group['attributes']['isInternalGroup'], 'Only reuse the existing internal account.'
        source = api('betaGroups/' + source_group['id'] + '/betaTesters')['data']
        assert len(source) == 1, 'Do not invite additional testers from a changed source group.'
        tester = source[0]
        enrolled = api('betaGroups/' + group['id'] + '/betaTesters')['data']
        email = tester['attributes']['email']
        if not any(t['attributes'].get('email', '').casefold() == email.casefold() for t in enrolled):
            try:
                api('betaGroups/' + group['id'] + '/relationships/betaTesters', 'POST',
                    {'data': [{'type': 'betaTesters', 'id': tester['id']}]})
            except AppleError as error:
                if error.status != 409: raise
                # Create/resolve the tester in the target group atomically, using
                # only Max's existing Apple tester email; never invite another person.
                api('betaTesters', 'POST', {'data': {'type': 'betaTesters',
                    'attributes': {'email': email},
                    'relationships': {'betaGroups': {'data': [{'type': 'betaGroups', 'id': group['id']}]}}}})
        enrolled = api('betaGroups/' + group['id'] + '/betaTesters')['data']
        assert any(t['attributes'].get('email', '').casefold() == email.casefold() for t in enrolled), 'Max is not enrolled yet.'
        details = api('builds/' + build['id'] + '/buildBetaDetail')['data']['attributes']
        receipt['internal_build_state'] = details.get('internalBuildState'); save()
        assert receipt['internal_build_state'] == 'IN_BETA_TESTING', 'Build is not available to internal testers yet.'
        attached = api('betaGroups/' + group['id'] + '/builds')['data']
        assert any(b['id'] == build['id'] for b in attached)
        receipt.update({'status': 'available to Max internal tester group', 'tester_count': len(enrolled),
                        'verified_at': datetime.now(timezone.utc).isoformat()})
        save(); print(receipt['status'], flush=True)

if __name__ == '__main__': main()
