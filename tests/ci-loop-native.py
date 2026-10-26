#!/usr/bin/env python3
"""Opt-in native AO retry-loop test; creates and deletes isolated fixture resources.

Requires AO_URL, AO_TOKEN and CI_FIXTURE_IMAGE (a Python-capable immutable image).
Uses the current oc context. CI_FIXTURE_NAMESPACE defaults to automation-orchestrator;
AO_PROJECT_ID can select the project for the temporary workflow. No real agent,
application job, merge, production credential or guest is used.
"""
import copy
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.request import Request, urlopen
import uuid
import yaml

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / '.rendered/ci-native'
folder.mkdir(parents=True, exist_ok=True)
ao = os.environ['AO_URL'].rstrip('/') + '/api/v1'
auth = {'Authorization': 'Bearer ' + os.environ['AO_TOKEN']}

def request(url, headers=None, body=None, method=None):
    headers = dict(headers or {})
    if body is not None:
        body = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    for attempt in range(3 if body is None and method is None else 1):
        try:
            with urlopen(Request(url, headers=headers, data=body, method=method), timeout=35) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except Exception:
            if body is not None or method is not None or attempt == 2:
                raise
            time.sleep(2)

name='ci-loop-fixture-'+uuid.uuid4().hex[:6];namespace=os.environ.get('CI_FIXTURE_NAMESPACE','automation-orchestrator')
server='''import json
from http.server import BaseHTTPRequestHandler,HTTPServer
state={'attempts':0,'feedback':0,'completed':0,'head':'a'*40,'green':False}
class Handler(BaseHTTPRequestHandler):
 def send(self,value):
  body=json.dumps(value).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body)
 def do_GET(self):
  if self.path=='/state':return self.send(state)
  if self.path=='/complete':state['completed']+=1
  if self.path=='/author':return self.send({'status':'idle'})
  return self.send({'ready':True,'head_sha':state['head'],'base_sha':'b'*40,'number':2,'ci_passed':state['green'],'ci_failed':False,'validation_required':not state['green']})
 def do_POST(self):
  self.rfile.read(int(self.headers.get('Content-Length',0)))
  if self.path=='/iteration':
   state['attempts']+=1
   if state['attempts']==1:state['feedback']+=1;state['head']='c'*40
   else:state['green']=True
   return self.send({'artifacts':{'ci_iteration':{'passed':state['green']}}})
  if self.path=='/validate':state['attempts']+=1
  if self.path=='/feedback':state['feedback']+=1;state['head']='c'*40
  if self.path=='/complete':state['completed']+=1
  if self.path=='/publish':
   state['green']=state['attempts']==2
   return self.send({'artifacts':{'ci_result':{'passed':state['green'],'superseded':False,'feedback':'fixture lint failure'}}})
  return self.send({'access_token':'fixture','job_id':101,'id':'same-session'})
 def log_message(self,*args):pass
HTTPServer(('0.0.0.0',8080),Handler).serve_forever()
'''
image=os.environ['CI_FIXTURE_IMAGE']
objects=[{'apiVersion':'route.openshift.io/v1','kind':'Route','metadata':{'name':name,'namespace':namespace},'spec':{'to':{'kind':'Service','name':name},'port':{'targetPort':8080},'tls':{'termination':'edge','insecureEdgeTerminationPolicy':'Redirect'}}},{'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':name,'namespace':namespace},'data':{'server.py':server}},
 {'apiVersion':'v1','kind':'Service','metadata':{'name':name,'namespace':namespace},'spec':{'selector':{'app':name},'ports':[{'port':8080,'targetPort':8080}]}},
 {'apiVersion':'v1','kind':'Pod','metadata':{'name':name,'namespace':namespace,'labels':{'app':name}},'spec':{'automountServiceAccountToken':False,'restartPolicy':'Never','activeDeadlineSeconds':600,'securityContext':{'runAsNonRoot':True,'runAsUser':1000,'seccompProfile':{'type':'RuntimeDefault'}},'containers':[{'name':'fixture','image':image,'command':['python3','-u','/fixture/server.py'],'securityContext':{'allowPrivilegeEscalation':False,'capabilities':{'drop':['ALL']}},'volumeMounts':[{'name':'code','mountPath':'/fixture'}],'resources':{'requests':{'cpu':'50m','memory':'64Mi'},'limits':{'memory':'256Mi'}}}],'volumes':[{'name':'code','configMap':{'name':name}}]}}]
manifest=folder/'native-loop-fixture.json';manifest.write_text(json.dumps({'apiVersion':'v1','kind':'List','items':objects}))
workflow=None;execution=None
try:
 subprocess.run(['oc','apply','-f',str(manifest)],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['oc','-n',namespace,'wait','pod/'+name,'--for=condition=Ready','--timeout=60s'],check=True)
 w=yaml.safe_load((ROOT/'cluster/automation-orchestrator/workflows/omnigent-remediation.yaml').read_text())
 ids={'wait_ci','ci_iteration','ci_poll_interval','read_candidate'}
 w['name']='isolated-ci-repair-loop-'+str(int(time.time()));w['description']='Isolated CI red/fix/green control flow fixture; no application or agent access.'
 w['triggers']=[{'id':'start','name':'Start fixture','type':'manual_trigger','parameters':{},'position':{'x':0,'y':0}}]
 w['nodes']=[n for n in w['nodes']if n['id']in ids]
 w['edges']=[e for e in w['edges']if e['from']in ids and e['to']in ids]+[{'from':'start','to':'wait_ci'}]
 host=json.loads(subprocess.check_output(['oc','-n',namespace,'get','route',name,'-o','json']))['spec']['host'];url='https://'+host
 for _ in range(20):
  try:request(url+'/state');break
  except Exception:time.sleep(2)
 else:raise RuntimeError('Fixture route is not ready')
 for n in w['nodes']:
  p=n['parameters']
  if n['type']=='loop':p['max_iterations']=10
  if n['type']=='wait':p['duration']=1
  if n['type']in ['aap_job_template','http_request']:
   method='GET' if n['id']=='read_candidate' else 'POST'
   endpoint='complete' if n['id']=='read_candidate' else 'iteration'
   n['type']='http_request';n['parameters']={'method':method,'url':url+'/'+endpoint}
  if n['id']=='wait_ci':p['condition']=p['condition'].replace('ci_iteration.artifacts','ci_iteration.body.artifacts')
 validation=request(ao+'/workflows/validate',auth,{'workflow_definition':w})
 assert validation['is_valid'],validation
 project=os.environ.get('AO_PROJECT_ID') or request(ao+'/workflows?limit=100',auth)['resources'][0]['project_id']
 workflow=request(ao+'/workflows',auth,{'name':w['name'],'project_id':project,'workflow_definition':w})
 request(ao+'/workflows/'+workflow['id']+'/versions/'+str(workflow['current_version'])+'/publish',auth,{'publish_name':'Isolated CI test','change_description':'Verify red/fix/green loop'})
 execution=request(ao+'/executions',auth,{'workflow_id':workflow['id'],'trigger_node_id':'start','use_published':True,'input_data':{}})
 print('Native loop fixture execution '+execution['id'],flush=True)
 end=time.time()+180
 while time.time()<end:
  e=request(ao+'/executions/'+execution['id'],auth)
  if e['status']in ['completed','failed','completed_with_errors','cancelled','canceled']:
   (folder/'native-loop-result-private.json').write_text(json.dumps(e))
   (folder/'native-loop-all-activities-private.json').write_text(json.dumps(request(ao+'/executions/'+execution['id']+'/activities?limit=100',auth)))
   if e['status']!='completed':
    activities=request(ao+'/executions/'+execution['id']+'/activities?limit=100',auth)
    (folder/'native-loop-activities-private.json').write_text(json.dumps(activities))
    print(json.dumps([{'node':a.get('activity_name'),'status':a['status'],'error':a.get('error_message')}for a in activities['resources']if a['status']=='failed']),flush=True)
   assert e['status']=='completed',e['status'];break
  time.sleep(3)
 else:raise RuntimeError('Native fixture did not finish')
 raw=subprocess.check_output(['oc','-n',namespace,'exec',name,'--','python3','-c',"import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/state').read().decode())"],text=True)
 state=json.loads(raw);assert state=={'attempts':2,'feedback':1,'completed':1,'head':'c'*40,'green':True},state
 (folder/'native-loop-result.json').write_text(json.dumps({'passed':True,'state':state,'execution':execution['id']}))
 print(json.dumps({'passed':True,'state':state}),flush=True)
finally:
 if workflow:
  try:request(ao+'/workflows/'+workflow['id'],auth,method='DELETE')
  except Exception as error:print('Fixture workflow cleanup requires inspection',type(error).__name__,flush=True)
 subprocess.run(['oc','delete','-f',str(manifest),'--ignore-not-found','--wait=false'],stdout=subprocess.DEVNULL)
