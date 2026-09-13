#!/usr/bin/env python3
"""Inspect Ember's release record with existing Apple credentials; never log secrets."""
import json
import os
import urllib.request
import urllib.error
import time
import jwt

APP = '6811495244'
signing = json.loads(os.environ.pop('EMBER_APPLE_SIGNING'))
assert signing['bundle_id'] == 'com.maxyaport.ember' and signing['team_id'] == '4BY949S88S'
token = jwt.encode({'iss': signing['issuer_id'], 'iat': int(time.time()), 'exp': int(time.time())+600, 'aud': 'appstoreconnect-v1'}, signing['private_key'], algorithm='ES256', headers={'kid': signing['key_id']})
print('::add-mask::'+token)

def get(path):
    try:
        req=urllib.request.Request('https://api.appstoreconnect.apple.com'+path, headers={'Authorization':'Bearer '+token})
        with urllib.request.urlopen(req,timeout=45) as response:return json.load(response)
    except urllib.error.HTTPError as e:
        return {'http_status':e.code,'errors':json.loads(e.read()).get('errors',[])}

def summarize(data):
    if 'data' not in data:return data
    def item(x):
        attrs=x.get('attributes',{}).copy()
        if x['type'] in ['appStoreReviewDetails','betaAppReviewDetails']:
            attrs={k:bool(v) for k,v in attrs.items() if k.startswith('contact') or k=='demoAccountRequired'}
        return {'id':x['id'],'type':x['type'],'attributes':attrs}
    d=data['data']
    return [item(x) for x in d] if isinstance(d,list) else (item(d) if d else None)

result={}
for label,path in [('app',f'/v1/apps/{APP}'),('versions',f'/v1/apps/{APP}/appStoreVersions'),('infos',f'/v1/apps/{APP}/appInfos'),('availability',f'/v1/apps/{APP}/appAvailabilityV2'),('pricing',f'/v1/apps/{APP}/appPriceSchedule'),('betaReview',f'/v1/apps/{APP}/betaAppReviewDetail')]:
    result[label]=summarize(get(path))
for v in result['versions']:
    vid=v['id']
    result['localizations']=summarize(get(f'/v1/appStoreVersions/{vid}/appStoreVersionLocalizations'))
    result['reviewContact']=summarize(get(f'/v1/appStoreVersions/{vid}/appStoreReviewDetail'))
    result['build']=summarize(get(f'/v1/appStoreVersions/{vid}/build'))
for info in result['infos']:
    iid=info['id']
    result['ageRating']=summarize(get(f'/v1/appInfos/{iid}/ageRatingDeclaration'))
    result['infoLocalizations']=summarize(get(f'/v1/appInfos/{iid}/appInfoLocalizations'))
print('EMBER_RELEASE_STATUS='+json.dumps(result))
