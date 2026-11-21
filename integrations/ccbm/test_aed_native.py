"""Actual compiled upstream CCBM, all AED prefixes; no inference mocks."""
from pathlib import Path
import json,time,hashlib,base64,zipfile
from server import infer,parse_posterior

root=Path(__file__).resolve().parents[2];out=Path(__file__).parent/'out'
initial=['begin_check','check_responsiveness','call_emergency','check_breathing']
shock=['attach_aed','clear_patient','analyze_rhythm','shock_advised','clear_patient','shock','compression']
no_shock=['reassess','clear_patient','analyze_rhythm','no_shock_advised','resume_cpr','compression']
cases={
 'shock_no_shock_repeat':initial+['request_aed','compression','ventilation','ventilation']+shock+['ventilation','ventilation']+no_shock+['ventilation','ventilation','handover'],
 'request_before_breathing':initial[:2]+['request_aed']+initial[2:]+['compression']+shock+['handover'],
 'contact_during_analysis':initial+['compression','request_aed','attach_aed','clear_patient','patient_contact','clear_patient','analyze_rhythm','shock_advised','patient_contact','clear_patient','analyze_rhythm','shock_advised','clear_patient','shock','compression','handover'],
 'nonshockable_initial':initial+['request_aed','compression','attach_aed','clear_patient','analyze_rhythm','no_shock_advised','resume_cpr','compression','handover'],
 'compression_only':initial+['compression_only','compression','request_aed']+shock+no_shock+['handover'],
 'scripted_recovery':initial+['compression','request_aed']+shock+['reassess','clear_patient','analyze_rhythm','no_shock_advised','recovery'],
 'legacy_witness':initial+['compression','ventilation','ventilation','handover'],
}
continuous=initial+['request_aed','compression','attach_aed']
for cycle in range(9):
    if cycle: continuous+=['reassess']
    continuous+=['clear_patient','analyze_rhythm']
    if cycle % 3 < 2: continuous+=['shock_advised','clear_patient','shock','compression']
    else: continuous+=['no_shock_advised','resume_cpr','compression']
cases['continuous_shock_shock_no_shock']=continuous+['handover']
results=[]
for name,sequence in cases.items():
 for length in range(1,len(sequence)+1):
  start=time.monotonic();result=infer(sequence[:length],out/'p-filter',out/'p.states')
  row=dict(case=name,prefix=length,expected=sequence[length-1],elapsed_ms=round((time.monotonic()-start)*1000,1),**result);results.append(row)
  if result['action']!=row['expected'] or result['probability']<0.9:
   print('NATIVE_PREFIX_FAIL',json.dumps(row),flush=True)
   (root/'build/ccbm-aed-prefixes.json').write_text(json.dumps(results,indent=2));raise SystemExit(1)
 print('PASS_NATIVE',name,len(sequence),'prefixes',flush=True)
model=json.loads((root/'addons/ccbm_native/model.json').read_text())
with zipfile.ZipFile(root/'addons/ccbm_native/naret_ccbm_runtime.aar') as z:
 binary=z.read('jni/arm64-v8a/libnaret_ccbm.so')
 assert hashlib.sha256(binary).hexdigest()==model['executable_sha256']
 assert binary[:4]==b'\x7fELF' and int.from_bytes(binary[18:20],'little')==183
assert hashlib.sha256((Path(__file__).parent/'d.pddl').read_bytes().replace(b'\r\n',b'\n')).hexdigest()==model['domain_sha256']
assert hashlib.sha256(base64.b64decode(model['states_base64'])).hexdigest()==model['states_sha256']
(root/'build/ccbm-aed-prefixes.json').write_text(json.dumps(results,indent=2))
print('NATIVE_AED_PASS',len(results),'real inference prefixes; Android artifact/state/domain hashes verified.',flush=True)
