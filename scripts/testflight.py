#!/usr/bin/env python3
"""Run quick core checks, sign once, and upload an internal TestFlight build."""
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

import release


def apple_availability(signing, key_path, build_number):
    """Read only: verify processing, beta state, and the existing internal group."""
    def encoded(value):
        return base64.urlsafe_b64encode(value).rstrip(b'=').decode()
    now = int(time.time())
    header = encoded(json.dumps({'alg': 'ES256', 'kid': signing['key_id'], 'typ': 'JWT'}).encode())
    payload = encoded(json.dumps({'iss': signing['issuer_id'], 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}).encode())
    message = header + '.' + payload
    signature = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(key_path)],
                               input=message.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout
    # OpenSSL emits ASN.1 DER; ES256 JWT signatures concatenate fixed-width r/s.
    if signature[0] != 0x30 or signature[1] != len(signature) - 2:
        raise RuntimeError('Invalid Apple token signature.')
    offset, parts = 2, []
    for _ in range(2):
        if signature[offset] != 0x02:
            raise RuntimeError('Invalid Apple token signature.')
        length = signature[offset + 1]
        value = signature[offset + 2:offset + 2 + length].lstrip(b'\x00')
        if len(value) > 32:
            raise RuntimeError('Invalid Apple token signature.')
        parts.append(value.rjust(32, b'\x00')); offset += 2 + length
    token = message + '.' + encoded(b''.join(parts))
    query = urllib.parse.urlencode({'filter[app]': '6811495244', 'filter[version]': build_number,
                                   'include': 'buildBetaDetail,betaGroups', 'limit': '5'})
    request = urllib.request.Request('https://api.appstoreconnect.apple.com/v1/builds?' + query,
                                     headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/json'})
    deadline = time.monotonic() + 480
    last = {'status': 'uploaded; waiting for Apple processing'}
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                data = json.load(response)
            for build in data.get('data', []):
                attributes = build['attributes']
                if attributes.get('version') != build_number:
                    continue
                detail = next((v for v in data.get('included', []) if v['type'] == 'buildBetaDetails'
                               and v['id'] == (build.get('relationships', {}).get('buildBetaDetail', {}).get('data') or {}).get('id')), {})
                groups = [v['id'] for v in (build.get('relationships', {}).get('betaGroups', {}).get('data') or [])]
                state = detail.get('attributes', {}).get('internalBuildState')
                last = {'apple_build_id': build['id'], 'processing_state': attributes.get('processingState'),
                        'internal_build_state': state, 'beta_groups': groups, 'status': 'uploaded; Apple processing remains'}
                if attributes.get('processingState') == 'VALID' and state == 'IN_BETA_TESTING' and 'aed222f8-bdd7-4b26-9a8a-7618e3a65278' in groups:
                    return {**last, 'status': 'available to internal testers', 'verified_at': datetime.now(timezone.utc).isoformat()}
                if attributes.get('processingState') in ['FAILED', 'INVALID']:
                    return {**last, 'status': 'Apple processing failed'}
        except urllib.error.HTTPError as error:
            if error.code not in [429, 500, 502, 503, 504]:
                return {'status': 'uploaded; availability check failed', 'availability_http_status': error.code}
        except (urllib.error.URLError, TimeoutError):
            pass
        print('Waiting for Apple to make this build available to the internal group.', flush=True)
        time.sleep(30)
    return last


def main():
    release.ROOT = Path.cwd().resolve()
    release.BUILD = release.ROOT/'build'
    release.RELEASE = release.ROOT/'Release'
    release.RECEIPT = release.RELEASE/'validation.json'
    release.require_macos()
    release.static_checks()
    fingerprint = release.fingerprint()
    build_number = os.environ['EMBER_BUILD_NUMBER']
    if not re.fullmatch(r'[1-9]\d{0,3}\.\d{1,2}\.\d{1,2}', build_number):
        raise SystemExit('Invalid Apple build number.')
    signing = json.loads(os.environ.pop('EMBER_APPLE_SIGNING'))
    team = signing['team_id']
    bundle = signing['bundle_id']
    if team != '4BY949S88S' or bundle != 'com.maxyaport.ember':
        raise SystemExit('Signing identity does not belong to Ember.')
    config = (release.ROOT/'Config.xcconfig').read_text()
    if f'EMBER_BUNDLE_ID = {bundle}' not in config or f'DEVELOPMENT_TEAM = {team}' not in config:
        raise SystemExit('Project identity does not match signing configuration.')
    key_id = signing['key_id']
    profile_uuid = signing['profile_uuid']
    if not re.fullmatch(r'[A-Z0-9]{10}', key_id) or not re.fullmatch(r'[A-Fa-f0-9-]{36}', profile_uuid):
        raise SystemExit('Invalid signing identifiers.')
    # The full simulator suite is an optional manual workflow. These quick
    # service checks precede the one native compilation performed by archive.
    release.run(['swift','test','-j','1'],env={**os.environ,'EMBER_LIVE_TESTS':'1'})
    password = signing['certificate_password']
    keychain_password = secrets.token_urlsafe(32)
    for value in [password, keychain_password]:
        print('::add-mask::'+value, flush=True)
    release.BUILD.mkdir(exist_ok=True)
    profile_dir = Path.home()/'Library/Developer/Xcode/UserData/Provisioning Profiles'
    profile_path = profile_dir/(profile_uuid+'.mobileprovision')
    api_dir = Path.home()/'.appstoreconnect/private_keys'
    api_path = api_dir/f'AuthKey_{key_id}.p8'
    if profile_path.exists() or api_path.exists():
        raise SystemExit('Refusing to replace an existing signing file on this machine.')
    profile_dir.mkdir(parents=True, exist_ok=True)
    api_dir.mkdir(parents=True, exist_ok=True)
    original_keychains = subprocess.check_output(['security','list-keychains','-d','user'], text=True)
    original_keychains = re.findall(r'"([^"]+)"', original_keychains)
    with tempfile.TemporaryDirectory(prefix='ember-signing-') as temp:
        temp = Path(temp)
        keychain = temp/'ember.keychain-db'
        certificate = temp/'distribution.p12'
        def private_write(path, data):
            with path.open('xb') as output:
                os.chmod(path, 0o600)
                output.write(data)
        try:
            private_write(certificate, base64.b64decode(signing['certificate_p12'], validate=True))
            private_write(profile_path, base64.b64decode(signing['profile'], validate=True))
            private_write(api_path, signing['private_key'].encode())
            profile = plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(profile_path)]))
            if profile['UUID'] != profile_uuid or team not in profile['TeamIdentifier']:
                raise RuntimeError('Provisioning profile identity mismatch.')
            if profile['Entitlements'].get('application-identifier') != f'{team}.{bundle}':
                raise RuntimeError('Provisioning profile does not authorize Ember.')
            if profile['ExpirationDate'].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
                raise RuntimeError('Provisioning profile expired.')
            if profile['Entitlements'].get('get-task-allow') or profile.get('ProvisionedDevices'):
                raise RuntimeError('An App Store distribution profile is required.')
            def security(*args):
                subprocess.run(['security',*map(str,args)],check=True,stdout=subprocess.DEVNULL)
            security('create-keychain','-p',keychain_password,keychain)
            security('set-keychain-settings','-lut','21600',keychain)
            security('unlock-keychain','-p',keychain_password,keychain)
            security('import',certificate,'-k',keychain,'-P',password,'-T','/usr/bin/codesign','-T','/usr/bin/security')
            security('set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',keychain_password,keychain)
            security('list-keychains','-d','user','-s',keychain,*original_keychains)
            archive = release.BUILD/'Ember.xcarchive'
            export = release.BUILD/'TestFlight'
            options = release.BUILD/'TestFlightExport.plist'
            options.write_bytes(plistlib.dumps({'method':'app-store-connect','destination':'export','teamID':team,'signingStyle':'manual','signingCertificate':'Apple Distribution','provisioningProfiles':{bundle:profile_uuid},'uploadSymbols':True,'manageAppVersionAndBuildNumber':False,'testFlightInternalTestingOnly':True}))
            release.run(['xcodebuild','archive','-project','Ember.xcodeproj','-scheme','Ember','-configuration','Release','-destination','generic/platform=iOS','-archivePath',archive,'CODE_SIGN_STYLE=Manual','CODE_SIGN_IDENTITY=Apple Distribution',f'PROVISIONING_PROFILE_SPECIFIER={profile_uuid}',f'DEVELOPMENT_TEAM={team}',f'CURRENT_PROJECT_VERSION={build_number}'])
            release.run(['xcodebuild','-exportArchive','-archivePath',archive,'-exportPath',export,'-exportOptionsPlist',options])
            app = archive/'Products/Applications/Ember.app'
            info = plistlib.loads((app/'Info.plist').read_bytes())
            if info['CFBundleIdentifier'] != bundle or info['CFBundleVersion'] != build_number:
                raise RuntimeError('Archived app identity/version mismatch.')
            release.run(['codesign','--verify','--deep','--strict',app])
            ipas = list(export.glob('*.ipa'))
            if len(ipas) != 1:
                raise RuntimeError('Expected exactly one exported IPA.')
            release.run(['xcrun','altool','--upload-app','--type','ios','--file',ipas[0],'--apiKey',key_id,'--apiIssuer',signing['issuer_id']])
            if release.fingerprint() != fingerprint:
                raise RuntimeError('Validated source changed during packaging.')
            result = {'uploaded_at':datetime.now(timezone.utc).isoformat(),'source_commit':os.environ['EMBER_SOURCE_SHA'],'source_sha256':fingerprint,'workflow_run':os.environ['EMBER_VALIDATION_RUN'],'checks':['static project checks','core and live API tests','signed Release archive'],'ui_tests_run':False,'bundle_id':bundle,'version':info['CFBundleShortVersionString'],'build':build_number,'internal_only':True,'status':'uploaded; Apple processing and tester availability must be verified separately'}
            (release.BUILD/'testflight-upload.json').write_text(json.dumps(result,indent=2)+'\n')
            print('Signed internal-only build uploaded to Apple; checking tester availability.',flush=True)
            result.update(apple_availability(signing, api_path, build_number))
            (release.BUILD/'testflight-upload.json').write_text(json.dumps(result,indent=2)+'\n')
            print(result['status'], flush=True)
        finally:
            subprocess.run(['security','list-keychains','-d','user','-s',*original_keychains],check=False,stdout=subprocess.DEVNULL)
            if keychain.exists():
                subprocess.run(['security','delete-keychain',str(keychain)],check=False,stdout=subprocess.DEVNULL)
            profile_path.unlink(missing_ok=True)
            api_path.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
