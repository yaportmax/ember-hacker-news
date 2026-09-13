#!/usr/bin/env python3
"""Complete the publisher-approved Ember release through Apple's public API."""
import base64
import hashlib
import json
import os
from pathlib import Path
import time
import urllib.request
import urllib.error
from urllib.parse import urlencode, urlparse
import jwt
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import hashes

APP='6811495244'
VERSION='8ab7b960-c615-492e-bf12-e4f5b3b15b75'
INFO='9349a644-a72b-40d9-956d-d03222afab48'
LOCALIZATION='ecac61f4-9590-49d5-9f16-d71e350e661e'
INFO_LOCALIZATION='a9d81fc5-5d9d-4468-93d5-601f3bbacebf'
CONTACT='eb04ce49-cfa1-45f5-826b-afd6bc722214'
BASE='https://api.appstoreconnect.apple.com'
signing=json.loads(os.environ.pop('EMBER_APPLE_SIGNING'))
assert signing['bundle_id']=='com.maxyaport.ember' and signing['team_id']=='4BY949S88S'
token=jwt.encode({'iss':signing['issuer_id'],'iat':int(time.time()),'exp':int(time.time())+1200,'aud':'appstoreconnect-v1'},signing['private_key'],algorithm='ES256',headers={'kid':signing['key_id']})
print('::add-mask::'+token,flush=True)
private,_,_=pkcs12.load_key_and_certificates(base64.b64decode(signing['certificate_p12']),signing['certificate_password'].encode())
contact=json.loads(private.decrypt(base64.b64decode(Path('Release/review-contact.enc').read_text()),padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=None)))
for value in contact.values():print('::add-mask::'+value,flush=True)
assert set(contact)=={'contactFirstName','contactLastName','contactPhone','contactEmail'}

def request(method,path,payload=None):
    url=path if path.startswith('https://') else BASE+path
    assert urlparse(url).netloc=='api.appstoreconnect.apple.com'
    req=urllib.request.Request(url,data=json.dumps(payload).encode() if payload is not None else None,method=method,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=60) as r:
            body=r.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body=e.read().decode()
        for value in contact.values():body=body.replace(value,'[redacted]')
        raise RuntimeError(f'{method} {path} HTTP {e.code}: {body}') from None

def get(path):return request('GET',path)
def ref(kind,id):return {'data':{'type':kind,'id':id}}
def patch(kind,id,attrs=None,rels=None):
    data={'type':kind,'id':id}
    if attrs is not None:data['attributes']=attrs
    if rels is not None:data['relationships']=rels
    return request('PATCH',f'/v1/{kind}/{id}',{'data':data})
def post(kind,attrs=None,rels=None,version=1,included=None):
    data={'type':kind}
    if attrs is not None:data['attributes']=attrs
    if rels is not None:data['relationships']=rels
    payload={'data':data}
    if included is not None:payload['included']=included
    return request('POST',f'/v{version}/{kind}',payload)
def collection(path):
    items=[]
    while path:
        response=get(path);items+=response['data'];path=response.get('links',{}).get('next')
    return items

record={}
def stage(name,action):
    if os.environ.get('EMBER_VERIFY_AND_SUBMIT')=='1' and name!='submission':
        return
    try:
        record[name]=action()
        print(name+': '+json.dumps(record[name]),flush=True)
    except Exception as e:
        record[name]={'error':str(e)}
        print(name+': '+str(e),flush=True)

app=get('/v1/apps/'+APP)['data']
assert app['attributes']['bundleId']=='com.maxyaport.ember'
version=get('/v1/appStoreVersions/'+VERSION)['data']
assert version['attributes']['appVersionState']=='PREPARE_FOR_SUBMISSION'
build=get('/v1/appStoreVersions/'+VERSION+'/build')['data']
assert build['attributes']['version']=='6.1.0' and build['attributes']['processingState']=='VALID' and build['attributes']['buildAudienceType']=='APP_STORE_ELIGIBLE'

def metadata():
    patch('appStoreReviewDetails',CONTACT,{**contact,'demoAccountRequired':False})
    patch('appInfoLocalizations',INFO_LOCALIZATION,{'subtitle':'Stories. Discussions. No noise','privacyPolicyUrl':'https://github.com/yaportmax/ember-hacker-news/blob/main/docs/PRIVACY.md'})
    patch('appInfos',INFO,rels={'primaryCategory':ref('appCategories','NEWS'),'secondaryCategory':ref('appCategories','PRODUCTIVITY')})
    patch('apps',APP,{'contentRightsDeclaration':'USES_THIRD_PARTY_CONTENT'})
    check=get('/v1/appStoreReviewDetails/'+CONTACT)['data']['attributes']
    assert all(check[k]==v for k,v in contact.items())
    return {'saved':True,'contact_verified':True}
stage('metadata',metadata)

def age():
    # Public HN discussion and in-app web access are explicitly approved.
    # Occasional general-news topics are disclosed; no native gaming/explicit media.
    attrs={'advertising':False,'parentalControls':False,'ageAssurance':False,
           'unrestrictedWebAccess':True,'userGeneratedContent':True,'socialMedia':True,
           'socialMediaAgeRestricted':False,'messagingAndChat':True,'gambling':False,
           'lootBox':False,'healthOrWellnessTopics':True,'ageRatingOverrideV2':'NONE'}
    for key in ['alcoholTobaccoOrDrugUseOrReferences','gunsOrOtherWeapons','medicalOrTreatmentInformation','profanityOrCrudeHumor','horrorOrFearThemes','matureOrSuggestiveThemes','violenceRealistic']:
        attrs[key]='INFREQUENT'
    for key in ['contests','gamblingSimulated','sexualContentGraphicAndNudity','sexualContentOrNudity','violenceCartoonOrFantasy','violenceRealisticProlongedGraphicOrSadistic']:
        attrs[key]='NONE'
    patch('ageRatingDeclarations',INFO,attrs)
    saved=get('/v1/appInfos/'+INFO+'/ageRatingDeclaration')['data']['attributes']
    canonical=lambda value:{'INFREQUENT':'INFREQUENT_OR_MILD','FREQUENT':'FREQUENT_OR_INTENSE'}.get(value,value)
    assert all(canonical(saved[k])==canonical(v) for k,v in attrs.items()),'Saved age-rating answers differ.'
    return {'saved':True,'answers':attrs}
stage('ageRating',age)

def screenshots():
    sets=collection('/v1/appStoreVersionLocalizations/'+LOCALIZATION+'/appScreenshotSets')
    output=[]
    for device,display,size in [('iPhone','APP_IPHONE_67',(1320,2868)),('iPad','APP_IPAD_PRO_3GEN_129',(2064,2752))]:
        folder=Path('build/store')/device
        attachments=json.loads((folder/'manifest.json').read_text())[0]['attachments']
        attachments.sort(key=lambda a:a['suggestedHumanReadableName'])
        assert len(attachments)==4
        current=next((s for s in sets if s['attributes']['screenshotDisplayType']==display),None)
        if not current:current=post('appScreenshotSets',{'screenshotDisplayType':display},{'appStoreVersionLocalization':ref('appStoreVersionLocalizations',LOCALIZATION)})['data']
        sid=current['id']
        existing=collection('/v1/appScreenshotSets/'+sid+'/appScreenshots')
        for a in attachments:
            from PIL import Image
            filename=a['suggestedHumanReadableName'].split('_')[0]+'.png'
            path=folder/a['exportedFileName']
            with Image.open(path) as image:assert image.size==size and image.mode=='RGB'
            blob=path.read_bytes();checksum=hashlib.md5(blob).hexdigest()
            shot=next((x for x in existing if x['attributes']['fileName']==filename),None)
            if shot:
                assert shot['attributes'].get('sourceFileChecksum') in (None,checksum),'Existing screenshot differs; refusing replacement.'
                if shot['attributes'].get('assetDeliveryState',{}).get('state')=='COMPLETE':continue
            else:shot=post('appScreenshots',{'fileName':filename,'fileSize':len(blob)},{'appScreenshotSet':ref('appScreenshotSets',sid)})['data']
            for op in shot['attributes'].get('uploadOperations',[]):
                assert urlparse(op['url']).scheme=='https'
                headers={h['name']:h['value'] for h in op['requestHeaders']}
                req=urllib.request.Request(op['url'],method=op['method'],headers=headers,data=blob[op['offset']:op['offset']+op['length']])
                with urllib.request.urlopen(req,timeout=90) as r:r.read()
            patch('appScreenshots',shot['id'],{'uploaded':True,'sourceFileChecksum':checksum})
        for attempt in range(12):
            saved=collection('/v1/appScreenshotSets/'+sid+'/appScreenshots')
            states=[x['attributes'].get('assetDeliveryState',{}).get('state') for x in saved]
            if len(states)==4 and all(s=='COMPLETE' for s in states):break
            if any(s=='FAILED' for s in states):raise RuntimeError('Apple screenshot processing failed.')
            time.sleep(5)
        assert len(states)==4 and all(s=='COMPLETE' for s in states),str(states)
        output.append({'device':device,'count':len(states),'state':'COMPLETE'})
    return output
stage('screenshots',screenshots)

def pricing():
    points=collection('/v1/apps/'+APP+'/appPricePoints?'+urlencode({'filter[territory]':'USA','limit':200}))
    free=next(x for x in points if float(x['attributes']['customerPrice'])==0)
    item={'type':'appPrices','id':'${free-price}','attributes':{'startDate':None,'endDate':None},'relationships':{'appPricePoint':ref('appPricePoints',free['id'])}}
    post('appPriceSchedules',rels={'app':ref('apps',APP),'baseTerritory':ref('territories','USA'),'manualPrices':{'data':[{'type':'appPrices','id':'${free-price}'}]}},included=[item])
    return {'saved':True,'price':'Free','baseTerritory':'USA'}
stage('pricing',pricing)

def availability():
    territories=collection('/v1/territories?limit=200')
    included=[{'type':'territoryAvailabilities','id':'${territory-'+t['id']+'}','attributes':{'available':True,'preOrderEnabled':False},'relationships':{'territory':ref('territories',t['id'])}} for t in territories]
    post('appAvailabilities',attrs={'availableInNewTerritories':True},rels={'app':ref('apps',APP),'territoryAvailabilities':{'data':[{'type':x['type'],'id':x['id']} for x in included]}},version=2,included=included)
    return {'saved':True,'territories':len(territories)}
stage('availability',availability)

def submit():
    if any(isinstance(v,dict) and 'error' in v for v in record.values()):return {'submitted':False,'reason':'Resolve preparation errors before submitting.'}
    # Fresh read checks also support resuming without repeating saved mutations.
    saved_contact=get('/v1/appStoreReviewDetails/'+CONTACT)['data']['attributes']
    assert all(saved_contact[k]==v for k,v in contact.items()),'Review contact differs.'
    saved_info=get('/v1/appInfoLocalizations/'+INFO_LOCALIZATION)['data']['attributes']
    assert saved_info['privacyPolicyUrl']=='https://github.com/yaportmax/ember-hacker-news/blob/main/docs/PRIVACY.md'
    saved_age=get('/v1/appInfos/'+INFO+'/ageRatingDeclaration')['data']['attributes']
    assert all(saved_age[k] is True for k in ['unrestrictedWebAccess','socialMedia','messagingAndChat','userGeneratedContent'])
    assert all(saved_age[k] is not None for k in ['advertising','parentalControls','profanityOrCrudeHumor','gambling','violenceRealistic'])
    sets=collection('/v1/appStoreVersionLocalizations/'+LOCALIZATION+'/appScreenshotSets')
    for display in ['APP_IPHONE_67','APP_IPAD_PRO_3GEN_129']:
        sid=next(s['id'] for s in sets if s['attributes']['screenshotDisplayType']==display)
        shots=collection('/v1/appScreenshotSets/'+sid+'/appScreenshots')
        assert len(shots)==4 and all(s['attributes']['assetDeliveryState']['state']=='COMPLETE' for s in shots)
    prices=get('/v1/appPriceSchedules/'+APP+'/manualPrices?'+urlencode({'filter[territory]':'USA','include':'appPricePoint'}))
    assert any(x['type']=='appPricePoints' and float(x['attributes']['customerPrice'])==0 for x in prices.get('included',[])),'Free price not confirmed.'
    assert get('/v1/apps/'+APP+'/appAvailabilityV2')['data']['id']==APP
    existing=collection('/v1/apps/'+APP+'/reviewSubmissions')
    ready=next((x for x in existing if x['attributes'].get('state')=='READY_FOR_REVIEW'),None)
    if not ready:ready=post('reviewSubmissions',{'platform':'IOS'},{'app':ref('apps',APP)})['data']
    rid=ready['id']
    items=collection('/v1/reviewSubmissions/'+rid+'/items?include=appStoreVersion')
    if not any(x.get('relationships',{}).get('appStoreVersion',{}).get('data',{}).get('id')==VERSION for x in items):
        post('reviewSubmissionItems',rels={'reviewSubmission':ref('reviewSubmissions',rid),'appStoreVersion':ref('appStoreVersions',VERSION)})
    patch('reviewSubmissions',rid,{'submitted':True})
    state=get('/v1/reviewSubmissions/'+rid)['data']['attributes']['state']
    return {'submission_id':rid,'state':state,'submitted':state in ['WAITING_FOR_REVIEW','IN_REVIEW','COMPLETED']}
stage('submission',submit)
print('EMBER_PREPARATION_RESULT='+json.dumps(record),flush=True)
