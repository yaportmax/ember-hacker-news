#!/usr/bin/env python3
"""Sign Vloh using Max's existing Apple certificate; keep all secrets on the runner."""
import base64, json, os, plistlib, re, secrets, subprocess, tempfile, time
from pathlib import Path
from datetime import datetime, timezone
from urllib.request import Request, urlopen
from urllib.parse import urlencode
from urllib.error import HTTPError
ROOT = Path(__file__).resolve().parent.parent
BUNDLE = 'com.maxyaport.vloh'
TEAM = '4BY949S88S'

def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], cwd=ROOT, check=True, **kwargs)

def token(signing, key):
    def b64(data): return base64.urlsafe_b64encode(data).rstrip(b'=').decode()
    now = int(time.time())
    head = b64(json.dumps({'alg':'ES256','kid':signing['key_id'],'typ':'JWT'}).encode())
    body = b64(json.dumps({'iss':signing['issuer_id'],'iat':now,'exp':now+600,'aud':'appstoreconnect-v1'}).encode())
    message = head + '.' + body
    der = subprocess.check_output(['openssl','dgst','-sha256','-sign',str(key)], input=message.encode())
    offset, parts = 2, []
    assert der[0] == 0x30 and der[1] == len(der)-2
    for _ in range(2):
        assert der[offset] == 2
        size = der[offset+1]; parts.append(der[offset+2:offset+2+size].lstrip(b'\x00').rjust(32,b'\x00')); offset += size+2
    return message + '.' + b64(b''.join(parts))

def main():
    signing = json.loads(os.environ.pop('EMBER_APPLE_SIGNING'))
    assert signing['team_id'] == TEAM and signing['bundle_id'] == 'com.maxyaport.ember'
    build = ROOT/'build'; build.mkdir(exist_ok=True)
    number = os.environ['VLOH_BUILD_NUMBER']
    assert re.fullmatch(r'[1-9]\d{0,3}\.\d{1,2}\.\d{1,2}', number)
    keychains = re.findall(r'"([^"]+)"', subprocess.check_output(['security','list-keychains','-d','user'],text=True))
    with tempfile.TemporaryDirectory(prefix='vloh-signing-') as directory:
        temp = Path(directory)
        key = temp/f"AuthKey_{signing['key_id']}.p8"; key.write_text(signing['private_key']); key.chmod(0o600)
        cert = temp/'distribution.p12'; cert.write_bytes(base64.b64decode(signing['certificate_p12'])); cert.chmod(0o600)
        old_profile = temp/'ember.mobileprovision'; old_profile.write_bytes(base64.b64decode(signing['profile'])); old_profile.chmod(0o600)
        original = plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(old_profile)]))
        certificate_data = set(original['DeveloperCertificates'])
        password = signing['certificate_password']; chain_password = secrets.token_urlsafe(32)
        for value in [password, chain_password]: print('::add-mask::' + value, flush=True)
        def api(path, method='GET', body=None):
            req = Request('https://api.appstoreconnect.apple.com/v1/' + path, data=json.dumps(body).encode() if body else None, method=method, headers={'Authorization':'Bearer '+token(signing,key),'Content-Type':'application/json'})
            try:
                with urlopen(req,timeout=45) as response: return json.load(response) if response.status != 204 else {}
            except HTTPError as error:
                # Log only Apple's structured public error titles, never request credentials.
                try: errors=json.load(error).get('errors',[]); print('Apple API: '+ '; '.join(x.get('title','')+': '+x.get('detail','') for x in errors),flush=True)
                except Exception: pass
                raise RuntimeError(f'Apple API failed with HTTP {error.code}') from None
        apps = api('apps?' + urlencode({'filter[bundleId]':BUNDLE}))['data']
        if not apps: raise RuntimeError('Create Vloh in App Store Connect before uploading.')
        app_id=apps[0]['id']
        bundles=api('bundleIds?'+urlencode({'filter[identifier]':BUNDLE}))['data']
        if len(bundles)!=1: raise RuntimeError('Vloh bundle ID registration is missing.')
        bundle_id=bundles[0]['id']
        certificates=api('certificates?limit=200')['data']
        matching=[item for item in certificates if base64.b64decode(item['attributes']['certificateContent']) in certificate_data]
        if not matching: raise RuntimeError('Existing Apple Distribution certificate could not be resolved.')
        certificate_id=matching[0]['id']
        profiles=api('profiles?'+urlencode({'filter[name]':'Vloh App Store','include':'bundleId','limit':'200'}))['data']
        profiles=[p for p in profiles if p['attributes']['profileState']=='ACTIVE' and p['relationships']['bundleId']['data']['id']==bundle_id]
        if profiles: profile=profiles[0]
        else:
            profile=api('profiles','POST',{'data':{'type':'profiles','attributes':{'name':'Vloh App Store','profileType':'IOS_APP_STORE'},'relationships':{'bundleId':{'data':{'type':'bundleIds','id':bundle_id}},'certificates':{'data':[{'type':'certificates','id':certificate_id}]}}}})['data']
        uuid=profile['attributes']['uuid']
        checked_profile=temp/'vloh.mobileprovision'; checked_profile.write_bytes(base64.b64decode(profile['attributes']['profileContent'])); checked_profile.chmod(0o600)
        decoded=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(checked_profile)]))
        assert decoded['Entitlements']['application-identifier']==TEAM+'.'+BUNDLE
        assert 'iCloud.com.maxyaport.vloh' in decoded['Entitlements'].get('com.apple.developer.icloud-container-identifiers',[]), 'Profile must authorize Vloh CloudKit container.'
        chain=temp/'vloh.keychain-db'
        def security(*args): run(['security',*args],stdout=subprocess.DEVNULL)
        api_dir=Path.home()/'.appstoreconnect/private_keys'; api_dir.mkdir(parents=True,exist_ok=True)
        api_key=api_dir/key.name
        if api_key.exists(): raise RuntimeError('Refusing to overwrite an existing API key file.')
        profile_dir=Path.home()/'Library/Developer/Xcode/UserData/Provisioning Profiles'; profile_dir.mkdir(parents=True,exist_ok=True)
        profile_path=profile_dir/(uuid+'.mobileprovision')
        if profile_path.exists(): raise RuntimeError('Refusing to replace an existing profile.')
        try:
            api_key.write_bytes(key.read_bytes()); api_key.chmod(0o600)
            profile_path.write_bytes(checked_profile.read_bytes()); profile_path.chmod(0o600)
            security('create-keychain','-p',chain_password,chain)
            security('set-keychain-settings','-lut','21600',chain)
            security('unlock-keychain','-p',chain_password,chain)
            security('import',cert,'-k',chain,'-P',password,'-T','/usr/bin/codesign','-T','/usr/bin/security')
            security('set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',chain_password,chain)
            security('list-keychains','-d','user','-s',chain,*keychains)
            archive=build/'Vloh.xcarchive'; export=build/'TestFlight'; options=build/'ExportOptions.plist'
            options.write_bytes(plistlib.dumps({'method':'app-store-connect','destination':'export','teamID':TEAM,'signingStyle':'manual','signingCertificate':'Apple Distribution','provisioningProfiles':{BUNDLE:uuid},'uploadSymbols':True,'manageAppVersionAndBuildNumber':False,'testFlightInternalTestingOnly':False}))
            run(['xcodebuild','archive','-project','Vloh.xcodeproj','-scheme','Vloh','-configuration','Release','-destination','generic/platform=iOS','-archivePath',archive,'CODE_SIGN_STYLE=Manual','CODE_SIGN_IDENTITY=Apple Distribution',f'PROVISIONING_PROFILE_SPECIFIER={uuid}',f'CURRENT_PROJECT_VERSION={number}'])
            run(['xcodebuild','-exportArchive','-archivePath',archive,'-exportPath',export,'-exportOptionsPlist',options])
            app=archive/'Products/Applications/Vloh.app'; info=plistlib.loads((app/'Info.plist').read_bytes())
            assert info['CFBundleIdentifier']==BUNDLE and info['CFBundleVersion']==number
            run(['codesign','--verify','--deep','--strict',app])
            ipas=list(export.glob('*.ipa')); assert len(ipas)==1
            run(['xcrun','altool','--upload-app','--type','ios','--file',ipas[0],'--apiKey',signing['key_id'],'--apiIssuer',signing['issuer_id']])
            result={'status':'uploaded; processing pending','app_id':app_id,'bundle':BUNDLE,'build':number,'source':os.environ['GITHUB_SHA'],'uploaded_at':datetime.now(timezone.utc).isoformat()}
            receipt=build/'testflight-upload.json';receipt.write_text(json.dumps(result,indent=2))
            groups=api('betaGroups?'+urlencode({'filter[app]':app_id}))['data']
            internal=next((g for g in groups if g['attributes']['name']=='Max — Internal Testing'),None)
            if internal is None:
                internal=api('betaGroups','POST',{'data':{'type':'betaGroups','attributes':{'name':'Max — Internal Testing','isInternalGroup':True,'hasAccessToAllBuilds':True,'publicLinkEnabled':False},'relationships':{'app':{'data':{'type':'apps','id':app_id}}}}})['data']
            deadline=time.monotonic()+600
            while time.monotonic()<deadline:
                builds=api('builds?'+urlencode({'filter[app]':app_id,'filter[version]':number,'include':'buildBetaDetail,betaGroups'}))
                if builds['data']:
                    item=builds['data'][0]; state=item['attributes']['processingState']
                    if state in ['FAILED','INVALID']: raise RuntimeError('Apple rejected processing this build.')
                    if state=='VALID':
                        localizations=api('builds/'+item['id']+'/betaBuildLocalizations')['data']
                        if not localizations:
                            api('betaBuildLocalizations','POST',{'data':{'type':'betaBuildLocalizations','attributes':{'locale':'en-US','whatsNew':'Test recording/importing clips, trims and audio, saved drafts, private iCloud invitations, playback, reactions and chat.'},'relationships':{'build':{'data':{'type':'builds','id':item['id']}}}}})
                        attached=api('betaGroups/'+internal['id']+'/builds')['data']
                        if not any(b['id']==item['id'] for b in attached):
                            api('betaGroups/'+internal['id']+'/relationships/builds','POST',{'data':[{'type':'builds','id':item['id']}]})
                        enrolled=api('betaGroups/'+internal['id']+'/betaTesters')['data']
                        if not enrolled:
                            source=api('betaGroups/aed222f8-bdd7-4b26-9a8a-7618e3a65278')['data']
                            assert source['attributes']['isInternalGroup']
                            testers=api('betaGroups/'+source['id']+'/betaTesters')['data']
                            assert len(testers)==1, 'Only reuse Max; source tester group changed.'
                            # Directly linking the Ember tester ID returned HTTP
                            # 409. Resolve Max's membership atomically by email,
                            # as verified on Vloh build 10.1.0.
                            api('betaTesters','POST',{'data':{'type':'betaTesters','attributes':{'email':testers[0]['attributes']['email']},'relationships':{'betaGroups':{'data':[{'type':'betaGroups','id':internal['id']}]}}}})
                            enrolled=api('betaGroups/'+internal['id']+'/betaTesters')['data']
                        assert enrolled, 'No internal tester has access yet.'
                        details=api('builds/'+item['id']+'/buildBetaDetail')['data']['attributes']
                        if details.get('internalBuildState')=='IN_BETA_TESTING':
                            result.update({'status':'available to Max internal tester group','apple_build_id':item['id'],'group_id':internal['id'],'tester_count':len(enrolled),'verified_at':datetime.now(timezone.utc).isoformat()});receipt.write_text(json.dumps(result,indent=2));print(result['status'],flush=True);return
                print('Waiting for Apple processing.',flush=True);time.sleep(30)
            raise RuntimeError('Uploaded; Apple processing is still pending. Inspect the receipt before reporting availability.')
        finally:
            subprocess.run(['security','list-keychains','-d','user','-s',*keychains],stdout=subprocess.DEVNULL)
            subprocess.run(['security','delete-keychain',str(chain)],stdout=subprocess.DEVNULL)
            profile_path.unlink(missing_ok=True);api_key.unlink(missing_ok=True)
if __name__=='__main__': main()
