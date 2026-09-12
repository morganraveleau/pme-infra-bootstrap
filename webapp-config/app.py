#!/usr/bin/env python3
# Bootstrap Infra PME — Configurateur web avec deploiement temps reel
import os, json, queue, threading, subprocess, ssl, urllib.request
from flask import Flask, render_template, request, Response, jsonify, redirect, url_for

app = Flask(__name__)
app.secret_key = 'bootstrap-pme-2024'

WORKSPACE  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TF_DIR     = os.path.join(WORKSPACE, 'terraform')
ANSBL_DIR  = os.path.join(WORKSPACE, 'ansible')
PACKER_DIR = os.path.join(WORKSPACE, 'packer')

state = {'running': False, 'done': False, 'success': False, 'config': {}}
log_q = queue.Queue()

STEPS = [
    {'id': 'config',    'label': 'Configuration generee',          'icon': 'settings'},
    {'id': 'prereqs',   'label': 'Verification des prerequis',     'icon': 'search'},
    {'id': 'iso',       'label': 'Telechargement ISO Windows',      'icon': 'download'},
    {'id': 'template',  'label': 'Construction template Windows',   'icon': 'build'},
    {'id': 'terraform', 'label': 'Provisionnement VMs (Terraform)', 'icon': 'dns'},
    {'id': 'k3s',       'label': 'Installation k3s + applicatif',  'icon': 'hub'},
    {'id': 'ad',        'label': 'Configuration Active Directory',  'icon': 'corporate_fare'},
    {'id': 'done',      'label': 'Infrastructure prete !',          'icon': 'check_circle'},
]

STEP_MARKERS = {
    'requis': 'prereqs', 'Verification': 'prereqs',
    'ISO': 'iso', 'Packer': 'template', 'Template Windows': 'template',
    'Terraform init': 'terraform', 'Terraform apply': 'terraform',
    'Ansible': 'k3s', 'k3s': 'k3s', 'stack applicative': 'k3s',
    'domaine': 'ad', 'Active Directory': 'ad',
    'termine': 'done', 'Infrastructure': 'done',
}

def emit(msg, level='log'):
    log_q.put(json.dumps({'type': level, 'message': msg}))

def set_step(sid):
    log_q.put(json.dumps({'type': 'step', 'step': sid}))

def detect_step(line):
    for marker, sid in STEP_MARKERS.items():
        if marker in line:
            set_step(sid)
            return

def run_cmd(cmd, cwd=None, env_extra=None):
    env = os.environ.copy()
    env['TF_DATA_DIR'] = '/root/.terraform-data/pme-infra-bootstrap'
    os.makedirs(env['TF_DATA_DIR'], exist_ok=True)
    if env_extra:
        env.update(env_extra)
    proc = subprocess.Popen(cmd, cwd=cwd or WORKSPACE, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, bufsize=1)
    for line in proc.stdout:
        line = line.rstrip()
        if line:
            detect_step(line)
            emit(line)
    proc.wait()
    return proc.returncode


def generate_configs(cfg):
    tfvars = {
        "pm_api_url": cfg['pm_api_url'],
        "pm_api_token_id": cfg['pm_api_token_id'],
        "pm_api_token_secret": cfg['pm_api_token_secret'],
        "pm_node": cfg['pm_node'],
        "pm_node_address": cfg['pm_node_address'],
        "pm_ssh_private_key_path": cfg.get('ssh_key_path', '~/.ssh/id_ed25519'),
        "company_name": cfg['company_name'],
        "network_bridge": cfg['network_bridge'],
        "datastore": cfg['datastore'],
        "k3s_vm": {"vcpu": int(cfg['k3s_vcpu']), "memory_mb": int(cfg['k3s_memory'])*1024,
                   "disk_gb": int(cfg['k3s_disk']), "ip_address": cfg['k3s_ip'], "gateway": cfg['k3s_gateway']},
        "ad_vm":  {"template_id": 9001, "vcpu": int(cfg['ad_vcpu']), "memory_mb": int(cfg['ad_memory'])*1024,
                   "disk_gb": int(cfg['ad_disk']), "ip_address": cfg['ad_ip'], "gateway": cfg['ad_gateway']},
    }
    with open(os.path.join(TF_DIR, 'terraform.tfvars.json'), 'w') as f:
        json.dump(tfvars, f, indent=2)
    pkr_lines = [
        'pm_api_url          = "' + cfg['pm_api_url'] + '"',
        'pm_api_token_id     = "' + cfg['pm_api_token_id'] + '"',
        'pm_api_token_secret = "' + cfg['pm_api_token_secret'] + '"',
        'pm_node             = "' + cfg['pm_node'] + '"',
        'network_bridge      = "' + cfg['network_bridge'] + '"',
        'datastore           = "' + cfg['datastore'] + '"',
        'windows_iso_file    = "Windows_Server_2022_x64_EN_Eval.iso"',
        'windows_admin_password = "' + cfg['windows_admin_password'] + '"',
    ]
    with open(os.path.join(PACKER_DIR, 'windows-server-2022.pkrvars.hcl'), 'w') as f:
        f.write('\n'.join(pkr_lines) + '\n')
    yml = [
        '---',
        'company_name: "' + cfg['company_name'] + '"',
        'webapp_domain: "' + cfg['webapp_domain'] + '"',
        'webapp_enable_monitoring: true',
        'postgres_db_name: "' + cfg['company_name'] + '_app"',
        'postgres_admin_password: "' + cfg['postgres_password'] + '"',
        'ad_domain_name: "' + cfg['ad_domain'] + '"',
        'ad_domain_netbios_name: "' + cfg['ad_netbios'].upper() + '"',
        'ad_safe_mode_admin_password: "' + cfg['ad_dsrm_password'] + '"',
        'vault_windows_admin_password: "' + cfg['windows_admin_password'] + '"',
        'grafana_admin_password: "' + cfg['grafana_password'] + '"',
        'prometheus_retention: "15d"',
    ]
    os.makedirs(os.path.join(ANSBL_DIR, 'group_vars'), exist_ok=True)
    with open(os.path.join(ANSBL_DIR, 'group_vars', 'all.yml'), 'w') as f:
        f.write('\n'.join(yml) + '\n')

def template_exists(cfg):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    url   = cfg['pm_api_url'] + '/nodes/' + cfg['pm_node'] + '/qemu/9001/status/current'
    token = 'PVEAPIToken=' + cfg['pm_api_token_id'] + '=' + cfg['pm_api_token_secret']
    try:
        urllib.request.urlopen(urllib.request.Request(url, headers={'Authorization': token}),
                               context=ctx, timeout=5)
        return True
    except Exception:
        return False

def get_vm_status(cfg):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    base  = cfg['pm_api_url'] + '/nodes/' + cfg['pm_node'] + '/qemu'
    token = 'PVEAPIToken=' + cfg['pm_api_token_id'] + '=' + cfg['pm_api_token_secret']
    co    = cfg.get('company_name', 'pme')
    wanted = [(9000,'debian12-cloud-init-tpl','Template Debian 12'),
              (9001,'windows-server-2022-tpl','Template Windows 2022'),
              (None, co+'-k3s-node1','k3s / Kubernetes'),
              (None, co+'-ad-dc1','Active Directory DC')]
    try:
        req = urllib.request.Request(base, headers={'Authorization': token})
        with urllib.request.urlopen(req, context=ctx, timeout=5) as r:
            all_vms = {int(v['vmid']): v for v in json.loads(r.read())['data']}
    except Exception:
        all_vms = {}
    name2id = {v.get('name',''): k for k,v in all_vms.items()}
    results = []
    for vid, vname, vrole in wanted:
        vmid = vid if vid else name2id.get(vname)
        if vmid and vmid in all_vms:
            v = all_vms[vmid]
            results.append({'id': vmid, 'name': vname, 'role': vrole,
                            'status': v.get('status','unknown'),
                            'cpu': round(v.get('cpu',0)*100,1),
                            'mem': round(v.get('mem',0)/1073741824,1),
                            'maxmem': round(v.get('maxmem',0)/1073741824,1)})
        else:
            results.append({'id': vmid, 'name': vname, 'role': vrole, 'status': 'absent'})
    return results

def deploy_worker(cfg):
    try:
        state['running'] = True
        set_step('config')
        emit('==> Generation des fichiers de configuration')
        generate_configs(cfg)
        emit('    OK terraform/terraform.tfvars.json')
        emit('    OK ansible/group_vars/all.yml')
        emit('    OK packer/windows-server-2022.pkrvars.hcl')
        ssh_key = os.path.expanduser('~/.ssh/id_ed25519_bootstrap')
        if not os.path.exists(ssh_key):
            emit('==> Generation cle SSH projet')
            os.makedirs(os.path.expanduser('~/.ssh'), exist_ok=True)
            subprocess.run(['ssh-keygen','-t','ed25519','-C','bootstrap-pme',
                            '-f', ssh_key, '-N',''], check=True, capture_output=True)
        ssh_pub = open(ssh_key+'.pub').read().strip()
        extra   = {'TF_VAR_ssh_public_key': ssh_pub}
        set_step('prereqs')
        emit('==> Installation des collections Ansible')
        run_cmd(['ansible-galaxy','collection','install',
                 '-r', os.path.join(WORKSPACE,'ansible/requirements.yml'),'--force-with-deps'])
        if not template_exists(cfg):
            set_step('iso')
            emit('==> Template Windows absent - lancement packer-build.sh')
            rc = run_cmd(['bash', os.path.join(WORKSPACE,'packer-build.sh')], env_extra=extra)
            if rc != 0:
                emit('ERREUR packer-build.sh code '+str(rc), 'error'); state['success']=False; return
        else:
            emit('    OK Template Windows (vm_id 9001) present - Packer ignore')
        set_step('terraform')
        rc = run_cmd(['bash', os.path.join(WORKSPACE,'deploy.sh')], env_extra=extra)
        if rc != 0:
            emit('ERREUR deploy.sh code '+str(rc), 'error'); state['success']=False; return
        set_step('done'); state['success'] = True
    except Exception as e:
        emit('ERREUR '+str(e), 'error'); state['success'] = False
    finally:
        state['running'] = False; state['done'] = True
        log_q.put(json.dumps({'type':'done','success':state['success']}))

@app.route('/')
def index():
    return render_template('form.html')

@app.route('/configure', methods=['POST'])
def configure():
    cfg = request.form.to_dict()
    state.update({'config':cfg,'running':False,'done':False,'success':False})
    while not log_q.empty(): log_q.get()
    threading.Thread(target=deploy_worker, args=(cfg,), daemon=True).start()
    return redirect(url_for('progress'))

@app.route('/progress')
def progress():
    return render_template('deploy.html', steps=STEPS)

@app.route('/stream')
def stream():
    def gen():
        yield 'data: '+json.dumps({'type':'connected'})+'\n\n'
        while True:
            try:
                msg = log_q.get(timeout=30)
                yield 'data: '+msg+'\n\n'
                if json.loads(msg).get('type') == 'done': break
            except queue.Empty:
                yield 'data: '+json.dumps({'type':'ping'})+'\n\n'
    return Response(gen(), mimetype='text/event-stream',
                    headers={'Cache-Control':'no-cache','X-Accel-Buffering':'no'})

@app.route('/api/status')
def api_status():
    cfg = state.get('config',{})
    return jsonify({'running':state['running'],'done':state['done'],
                    'success':state['success'],'vms':get_vm_status(cfg) if cfg else []})

if __name__ == '__main__':
    print('\n  Bootstrap Infra PME -- http://localhost:5000\n')
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
