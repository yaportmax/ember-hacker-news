#!/usr/bin/env python3
"""Archive validated source and upload an internal-only TestFlight build."""
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone

import release


def main():
    release.require_macos()
    release.static_checks()
    receipt = json.loads(release.RECEIPT.read_text())
    fingerprint = release.fingerprint()
    if receipt.get('source_sha256') != fingerprint or not receipt.get('live_api_checked'):
        raise SystemExit('A matching successful native CI receipt is required.')
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
    password = signing['certificate_password']
    keychain_password = secrets.token_urlsafe(32)
    for value in [password, keychain_password]:
        print('::add-mask::'+value, flush=True)
    release.BUILD.mkdir(exist_ok=True)
    profile_dir = Path.home()/'Library/MobileDevice/Provisioning Profiles'
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
            result = {'uploaded_at':datetime.now(timezone.utc).isoformat(),'source_commit':os.environ['EMBER_SOURCE_SHA'],'source_sha256':fingerprint,'validation_run':os.environ['EMBER_VALIDATION_RUN'],'bundle_id':bundle,'version':info['CFBundleShortVersionString'],'build':build_number,'internal_only':True,'status':'uploaded; Apple processing and tester availability must be verified separately'}
            (release.BUILD/'testflight-upload.json').write_text(json.dumps(result,indent=2)+'\n')
            print('Signed internal-only build uploaded to Apple; processing remains.',flush=True)
        finally:
            subprocess.run(['security','list-keychains','-d','user','-s',*original_keychains],check=False,stdout=subprocess.DEVNULL)
            if keychain.exists():
                subprocess.run(['security','delete-keychain',str(keychain)],check=False,stdout=subprocess.DEVNULL)
            profile_path.unlink(missing_ok=True)
            api_path.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
