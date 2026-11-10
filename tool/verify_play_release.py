"""Verify and package already-built Play artifacts; never reads private keys."""
from pathlib import Path
import hashlib,json,re,shutil,struct,subprocess,zipfile
root=Path(__file__).resolve().parent.parent
out=root/'release/google_play/artifacts'; out.mkdir(parents=True,exist_ok=True)
java=Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin')
sdk=Path('/Users/alijasim/Library/Android/sdk/build-tools/36.1.0')
aab=root/'build/app/outputs/bundle/release/app-release.aab'
apk=root/'build/app/outputs/flutter-apk/app-release.apk'
report={'date':'2026-10-25','status':'technical_candidate_policy_blockers_remain','play_define':'PLAY_STORE_BUILD=true','bundle_version':'1.0.1+5','application_id':'com.motriiq.app'}
def run(name,args):
 p=subprocess.run([str(x) for x in args],capture_output=True,text=True)
 (out/'evidence'/f'{name}.txt').write_text(p.stdout+p.stderr)
 if p.returncode:raise RuntimeError(f'{name} failed; see evidence')
 return p.stdout+p.stderr
run('bundletool-validation',[java/'java','-jar','/tmp/motriiq-play-tools/bundletool-all-1.18.3.jar','validate',f'--bundle={aab}'])
config=run('bundle-config',[java/'java','-jar','/tmp/motriiq-play-tools/bundletool-all-1.18.3.jar','dump','config',f'--bundle={aab}'])
assert 'PAGE_ALIGNMENT_16K' in config
signature=run('bundle-signature',[java/'jarsigner','-verify',aab]);assert 'jar verified.' in signature
cert=run('signer-certificate',[java/'keytool','-printcert','-jarfile',aab])
report['signer_sha256']=re.search(r'SHA256:\s*([A-F0-9:]+)',cert).group(1)
run('apk-signature',[java/'java','-jar',sdk/'lib/apksigner.jar','verify','--print-certs',apk])
run('apk-zipalign',[sdk/'zipalign','-c','-P','16','-v','4',apk])
manifest=run('apk-manifest',[sdk/'aapt2','dump','badging',apk])
assert "name='com.motriiq.app' versionCode='5' versionName='1.0.1'" in manifest
assert "targetSdkVersion:'36'" in manifest
assert 'application-debuggable' not in manifest
for permission in ('FOREGROUND_SERVICE','READ_MEDIA_IMAGES','READ_EXTERNAL_STORAGE','ACCESS_BACKGROUND_LOCATION','ACCESS_ADSERVICES_AD_ID','ACCESS_ADSERVICES_ATTRIBUTION','ACCESS_ADSERVICES_TOPICS'):
 assert "uses-permission: name='android.permission."+permission+"'" not in manifest,permission
report['permissions']=re.findall(r"uses-permission: name='([^']+)'",manifest)
assert 'com.google.android.gms.permission.AD_ID' not in report['permissions']
report['advertising']='Google Mobile Ads SDK removed; no ad ID permissions; paid business feed disabled in Play build.'
report['target_sdk']=36;report['min_sdk']=24;report['debuggable']=False
report['elf_libraries']=[]
with zipfile.ZipFile(aab) as z:
 for name in z.namelist():
  if '/lib/' not in name or not name.endswith('.so'):continue
  b=z.read(name);is64=b[4]==2;endian='<' if b[5]==1 else '>'
  off=struct.unpack_from(endian+('Q' if is64 else 'I'),b,32 if is64 else 28)[0]
  size,count=struct.unpack_from(endian+'HH',b,54 if is64 else 42)
  aligns=[]
  for i in range(count):
   q=off+i*size
   if struct.unpack_from(endian+'I',b,q)[0]==1:aligns.append(struct.unpack_from(endian+('Q' if is64 else 'I'),b,q+(48 if is64 else 28))[0])
  assert aligns and min(aligns)>=16384,name
  report['elf_libraries'].append({'file':name,'load_segment_alignment':aligns})
report['alignment']='All packaged native libraries >=16KB; AAB requests PAGE_ALIGNMENT_16K; APK zipalign passed. Runtime emulator is 4KB, so a real 16KB boot test remains.'
report['files']={}
for src,name in [(aab,'motri-iq-1.0.1-5-play.aab'),(apk,'motri-iq-1.0.1-5-play.apk'),(root/'android/.local-signing/upload_certificate.pem','upload-certificate.pem'),(root/'build/app/outputs/mapping/release/mapping.txt','mapping.txt')]:
 shutil.copy2(src,out/name)
 report['files'][name]={'sha256':hashlib.sha256((out/name).read_bytes()).hexdigest(),'bytes':(out/name).stat().st_size}
# Native symbols are already embedded by AGP in BUNDLE-METADATA. Preserve a
# separate copy for diagnostics without inventing symbol files.
with zipfile.ZipFile(aab) as z:
 symbols=[n for n in z.namelist() if n.startswith('BUNDLE-METADATA/com.android.tools.build.debugsymbols/') and n.endswith('.sym')]
 if symbols:
  with zipfile.ZipFile(out/'native-debug-symbols.zip','w',zipfile.ZIP_DEFLATED) as dest:
   for name in symbols:dest.writestr(name.split('debugsymbols/',1)[1],z.read(name))
report['source_sha256']={}
for folder in ['lib','assets/fonts']:
 for p in sorted((root/folder).rglob('*')):
  if not p.is_file():continue
  if folder=='lib' and (p.suffix!='.dart' or p.name.startswith(('main_backup','main_fixed','tmp_img_'))):continue
  report['source_sha256'][str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
for f in ['pubspec.yaml','pubspec.lock','android/app/build.gradle.kts','android/app/proguard-rules.pro','android/app/src/main/AndroidManifest.xml']:
 report['source_sha256'][f]=hashlib.sha256((root/f).read_bytes()).hexdigest()
(out/'release-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print('Verified package, signatures, API36, permissions and native/ZIP alignment; final artifacts preserved.')
