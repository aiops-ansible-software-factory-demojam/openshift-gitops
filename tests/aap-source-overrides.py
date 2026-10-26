#!/usr/bin/env python3
"""Opt-in native AAP integration test; creates/deletes isolated local-only fixtures.

Requires AAP_HOST, AAP_USERNAME, AAP_PASSWORD, FORGEJO_URL and FORGEJO_TOKEN.
Run from the GitOps checkout with sibling collection checkouts. The existing
application projects, hosts, workflows and incidents are never modified.
"""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
furl = os.environ['FORGEJO_URL'].rstrip('/')
ftoken = os.environ['FORGEJO_TOKEN']
fh = {'Authorization': 'token ' + ftoken}
base = os.environ['AAP_HOST'].rstrip('/') + '/api/controller/v2/'
headers = {'Authorization': 'Basic ' + base64.b64encode(
    (os.environ['AAP_USERNAME'] + ':' + os.environ['AAP_PASSWORD']).encode()).decode(),
    'Content-Type': 'application/json'}

def request(url, auth=None, body=None, method=None):
    data = json.dumps(body).encode() if body is not None else None
    h = dict(auth or {})
    if data is not None: h['Content-Type'] = 'application/json'
    with urlopen(Request(url, headers=h, data=data, method=method), timeout=35) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}

def api(method, path, body=None):
    return request(base + path, headers, body, method)

def get(path):
    return api('GET', path)

import yaml
folder=ROOT/'.rendered/aap-source-overrides';folder.mkdir(parents=True,exist_ok=True,mode=0o700);prefix='source-guard-check-'+str(int(time.time()));created=[];runs=[];results=[]
def create(kind,body):
 r=api('POST',kind+'/',body);created.append((kind,r['id']));return r
def wait_run(kind,jid,limit=300):
 end=time.time()+limit
 while time.time()<end:
  j=get(f'{kind}/{jid}/')
  if j['status'] in ['successful','failed','error','canceled']:return j
  time.sleep(2)
 raise RuntimeError(f'Inspect {kind}/{jid} before retry')
request(furl+'/api/v1/admin/users/demo-owner/repos',fh,{'name':prefix,'private':False,'auto_init':False})
try:
 with tempfile.TemporaryDirectory() as tmp:
  d=Path(tmp);src=d/'source';src.mkdir();subprocess.run(['git','init','-qb','main',str(src)],check=True)
  def git(*args):return subprocess.check_output(['git','-C',str(src),*args],text=True).strip()
  git('config','user.name','Source Guard Fixture');git('config','user.email','fixture@example.test');git('config','core.hooksPath','/dev/null')
  for label,repo,file in [('web','ansible-collection-demo.webapp','validate-promotion.yml'),('python','ansible-collection-demo.pythonapp','validate-source.yml')]:
   (src/(label+'-guard.yml')).write_text((ROOT.parent/repo/'playbooks/tasks'/file).read_text())
   tasks=[{'name':'Execute the real collection source guard','ansible.builtin.import_tasks':label+'-guard.yml'},
    {'name':'Require the actual exported candidate bytes','ansible.builtin.assert':{'that':"lookup('ansible.builtin.file', playbook_dir ~ '/fixture-marker.txt') == 'candidate checkout'"}},
    {'name':'Publish actual protected source context','ansible.builtin.set_stats':{'data':{'fixture_source':{'job_branch':'{{ awx_job_scm_branch }}','project_revision':'{{ awx_project_revision }}','marker':"{{ lookup('ansible.builtin.file', playbook_dir ~ '/fixture-marker.txt') }}"}}}}]
   (src/(label+'.yml')).write_text(yaml.safe_dump([{'name':'Exercise source guards without touching application hosts','hosts':'webapps' if label=='web' else 'localhost','connection':'local','gather_facts':False,'tasks':tasks}]))
  (src/'noop.yml').write_text(yaml.safe_dump([{'name':'Trusted fixture gate','hosts':'localhost','connection':'local','gather_facts':False,'tasks':[{'name':'Keep the fixture local','ansible.builtin.assert':{'that':'inventory_hostname == "localhost"'}}]}]))
  (src/'fixture-marker.txt').write_text('candidate checkout');git('add','.');git('commit','-qm','Candidate fixture with actual source guards');sha=git('rev-parse','HEAD')
  (src/'fixture-marker.txt').write_text('default merge checkout');git('add','.');git('commit','-qm','Advance default branch beyond tested commit');default=git('rev-parse','HEAD')
  ask=d/'askpass';ask.write_text('#!/bin/sh\ncase "$1" in *Username*) echo demo-admin ;; *) printf "%s\\n" "$GUARD_FIXTURE_TOKEN" ;; esac\n');ask.chmod(0o700)
  subprocess.run(['git','-C',str(src),'-c','credential.helper=','push','-q',furl+'/demo-owner/'+prefix+'.git','main'],env=dict(os.environ,GIT_ASKPASS=str(ask),GIT_TERMINAL_PROMPT='0',GUARD_FIXTURE_TOKEN=ftoken),check=True)
 org=create('organizations',{'name':prefix});inv=create('inventories',{'name':prefix,'organization':org['id']})
 host=api('POST','hosts/',{'name':'localhost','inventory':inv['id'],'variables':'ansible_connection: local'})
 group=api('POST','groups/',{'name':'webapps','inventory':inv['id']});api('POST',f"groups/{group['id']}/hosts/",{'id':host['id']})
 ee=get('execution_environments/?name=demo-aap-ee')['results'][0]
 project=create('projects',{'name':prefix,'organization':org['id'],'scm_type':'git','scm_url':furl+'/demo-owner/'+prefix+'.git','scm_branch':'main','allow_override':True,'scm_clean':True,'scm_update_on_launch':False})
 end=time.time()+180
 while get(f"projects/{project['id']}/")['status']!='successful':
  assert time.time()<end;time.sleep(2)
 common={'organization':org['id'],'inventory':inv['id'],'project':project['id'],'execution_environment':ee['id'],'ask_variables_on_launch':True}
 guard=create('job_templates',{**common,'name':prefix+'-gate','playbook':'noop.yml'})
 for label,wname in [('web','webapp_promote'),('python','invoice_promote')]:
  deploy=create('job_templates',{**common,'name':prefix+'-'+label,'playbook':label+'.yml','ask_scm_branch_on_launch':True})
  w=create('workflow_job_templates',{'name':wname,'organization':org['id'],'inventory':inv['id'],'ask_scm_branch_on_launch':True,'ask_variables_on_launch':True,'allow_simultaneous':False})
  nodes={}
  for ident,jt in [('validate-release',guard['id']),('production-approval',None),('recheck-release',guard['id']),('deploy',deploy['id'])]:
   body={'workflow_job_template':w['id'],'identifier':ident}
   if jt:body['unified_job_template']=jt
   n=create('workflow_job_template_nodes',body);nodes[ident]=n
   if jt is None:api('POST',f"workflow_job_template_nodes/{n['id']}/create_approval_template/",{'name':prefix+'-'+label+'-approval','timeout':180})
  for first,last in [('validate-release','production-approval'),('production-approval','recheck-release'),('recheck-release','deploy')]:api('POST',f"workflow_job_template_nodes/{nodes[first]['id']}/success_nodes/",{'id':nodes[last]['id']})
  for attempt,branch in [('pinned',sha),('wrong-source',default),('mutable','main')]:
   values={'webapp_candidate_sha':sha,'webapp_issue_number':1,'webapp_pr_number':2,'webapp_release_contract':{'schema_version':1,'repository':'demo-owner/ansible-collection-demo.webapp','source_revision':sha,'issue_number':1,'pr_number':2,'hosts':['localhost']}} if label=='web' else {'invoice_candidate_sha':sha,'invoice_release_channel':'baseline'}
   # A forged prompt must not replace Controller's protected job context.
   if attempt!='pinned':values['awx_job_scm_branch']=sha
   run=api('POST',f"workflow_job_templates/{w['id']}/launch/",{'scm_branch':branch,'extra_vars':values});rid=run.get('workflow_job') or run['id'];runs.append(rid);approved=False;end=time.time()+300
   while time.time()<end:
    state=get(f'workflow_jobs/{rid}/');ns={n['identifier']:n for n in get(f'workflow_jobs/{rid}/workflow_nodes/?page_size=20')['results']}
    aid=ns['production-approval'].get('job')
    if not approved and aid and get(f'workflow_approvals/{aid}/')['status']=='pending':
     assert not ns['deploy'].get('job');api('POST',f'workflow_approvals/{aid}/approve/',{});approved=True
    if state['status'] in ['successful','failed','error','canceled']:
     assert state['status']==('successful' if attempt=='pinned' else 'failed'),state['status']
     j=get(f"jobs/{ns['deploy']['job']}/")
     proof=j.get('artifacts',{}).get('fixture_source',{})
     if attempt=='pinned':assert proof=={'job_branch':sha,'project_revision':default,'marker':'candidate checkout'},proof
     result={'application':label,'attempt':attempt,'status':state['status'],'job':j['id'],'scm_revision':j['scm_revision'],'actual_context':proof};results.append(result);print(json.dumps(result),flush=True);break
    time.sleep(2)
   else:raise RuntimeError('Inspect isolated workflow '+str(rid))
 (folder/'native-source-results.json').write_text(json.dumps({'passed':True,'tested_sha':sha,'default_merge_sha':default,'results':results},indent=2)+'\n')
finally:
 for rid in runs:
  try:
   if get(f'workflow_jobs/{rid}/')['status'] not in ['successful','failed','error','canceled']:api('POST',f'workflow_jobs/{rid}/cancel/',{})
  except Exception:pass
 for kind,jid in reversed(created):
  try:api('DELETE',f'{kind}/{jid}/')
  except Exception as e:print('Fixture cleanup inspection needed',kind,jid,type(e).__name__,flush=True)
 req=Request(furl+'/api/v1/repos/demo-owner/'+prefix,headers=fh,method='DELETE')
 try:
  with urlopen(req,timeout=20):pass
 except Exception as e:print('Fixture repo cleanup requires inspection',type(e).__name__,flush=True)
 print('Source guard fixture cleanup finished.',flush=True)
