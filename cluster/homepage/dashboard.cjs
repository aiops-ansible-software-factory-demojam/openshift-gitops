// Fixed, read-only dashboard queries. Credentials never enter the response or Homepage config.
const fs = require('node:fs');
const http = require('node:http');
const https = require('node:https');
const sa = '/var/run/dashboard/kubernetes';
const credentials = '/var/run/dashboard/credentials';
const read = (path) => fs.readFileSync(path, 'utf8').trim();
const settings = () => JSON.parse(read('/var/run/dashboard/environment/environment.json'));

function request(url, { headers = {}, body, ca } = {}) {
  return new Promise((resolve, reject) => {
    const target = new URL(url);
    const client = target.protocol === 'https:' ? https : http;
    const req = client.request(target, {
      method: body ? 'POST' : 'GET', headers, ca, timeout: 10000,
    }, (response) => {
      let data = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => { data += chunk; });
      response.on('end', () => {
        if (response.statusCode < 200 || response.statusCode >= 300) {
          reject(new Error(`HTTP ${response.statusCode}`));
        } else {
          try { resolve(JSON.parse(data)); } catch { reject(new Error('Invalid JSON')); }
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('Timeout')));
    req.on('error', () => reject(new Error('Connection unavailable')));
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

const kube = (path) => request(`https://kubernetes.default.svc${path}`, {
  headers: { Authorization: `Bearer ${read(`${sa}/token`)}` }, ca: read(`${sa}/ca.crt`),
});
const quantity = (value) => {
  const match = String(value).match(/^([\d.]+)([a-zA-Z]*)$/);
  if (!match) throw new Error('Invalid resource quantity');
  const scale = { n: 1e-9, u: 1e-6, m: 1e-3, '': 1, k: 1e3, K: 1e3,
    M: 1e6, G: 1e9, T: 1e12, Ki: 1024, Mi: 1024 ** 2, Gi: 1024 ** 3, Ti: 1024 ** 4 };
  if (!(match[2] in scale)) throw new Error('Unknown resource unit');
  return Number(match[1]) * scale[match[2]];
};

async function gitops() {
  const apps = (await kube('/apis/argoproj.io/v1alpha1/namespaces/openshift-gitops/applications')).items;
  const count = (key, value) => apps.filter((app) => app.status?.[key]?.status === value).length;
  const root = apps.find((app) => app.metadata.name === 'cluster');
  return { apps: apps.length, synced: count('sync', 'Synced'), healthy: count('health', 'Healthy'),
    revision: root?.status?.sync?.revision, branch: root?.spec?.source?.targetRevision,
    outOfSync: count('sync', 'OutOfSync'), degraded: count('health', 'Degraded') };
}

async function cluster() {
  const [nodes, metrics] = await Promise.all([kube('/api/v1/nodes'), kube('/apis/metrics.k8s.io/v1beta1/nodes')]);
  if (nodes.items.some((node) => !metrics.items.some((metric) => metric.metadata.name === node.metadata.name))) {
    throw new Error('Node metrics incomplete');
  }
  let cpu = 0, memory = 0, cpuTotal = 0, memoryTotal = 0;
  const details = nodes.items.map((node) => {
    const usage = metrics.items.find((metric) => metric.metadata.name === node.metadata.name)?.usage;
    const ready = node.status.conditions.some((condition) => condition.type === 'Ready' && condition.status === 'True');
    const capacity = node.status.allocatable;
    cpuTotal += quantity(capacity.cpu); memoryTotal += quantity(capacity.memory);
    if (usage) { cpu += quantity(usage.cpu); memory += quantity(usage.memory); }
    return { name: node.metadata.name, usage: usage
      ? `${ready ? 'Ready' : 'Not ready'} · CPU ${(100 * quantity(usage.cpu) / quantity(capacity.cpu)).toFixed(1)}% · RAM ${(100 * quantity(usage.memory) / quantity(capacity.memory)).toFixed(1)}%`
      : 'Metrics unavailable' };
  });
  return { cpu: `${(100 * cpu / cpuTotal).toFixed(1)}%`, memory: `${(100 * memory / memoryTotal).toFixed(1)}%`,
    nodes: nodes.items.length, ready: nodes.items.filter((node) => node.status.conditions.some((c) => c.type === 'Ready' && c.status === 'True')).length,
    details };
}

async function monitoring() {
  const query = async (expression) => {
    const result = await request(`https://thanos-querier.openshift-monitoring.svc:9091/api/v1/query?query=${encodeURIComponent(expression)}`, {
      headers: { Authorization: `Bearer ${read(`${sa}/token`)}` }, ca: read(`${sa}/service-ca.crt`),
    });
    if (result.status !== 'success') throw new Error('Metrics query failed');
    return result.data.result;
  };
  const [probes, durations, alerts] = await Promise.all([
    query('probe_success{namespace="blackbox-exporter",job=~"webapp|forgejo"}'),
    query('probe_duration_seconds{namespace="blackbox-exporter",job="webapp"}'),
    query('ALERTS{namespace="blackbox-exporter",alertstate="firing"}'),
  ]);
  const state = (job) => {
    const result = probes.find((probe) => probe.metric.job === job);
    return result ? (Number(result.value[1]) === 1 ? 'Up' : 'Down') : 'No probe data';
  };
  return { webapp: state('webapp'), forgejo: state('forgejo'), alerts: alerts.length,
    response: durations.length ? `${(Number(durations[0].value[1]) * 1000).toFixed(1)} ms` : 'Unavailable' };
}

const aapGet = (path) => request(`${settings().aapUrl}${path}`, {
  headers: { Authorization: `Basic ${Buffer.from(`homepage-reader:${read(`${credentials}/aap-password`)}`).toString('base64')}` },
});
async function aap() {
  const jobs = (await aapGet('/api/controller/v2/jobs/?order_by=-id&page_size=5')).results;
  return { latestJob: jobs[0] ? `#${jobs[0].id} ${jobs[0].name}` : 'No jobs yet', status: jobs[0]?.status || 'Idle',
    jobs: jobs.map((job) => ({ id: job.id, name: `#${job.id} ${job.name}`, status: job.status })) };
}
async function eda() {
  const activations = (await aapGet('/api/eda/v1/activations/?name=demojam-webapp-issues')).results;
  const activation = activations[0];
  return { state: activation?.status || 'Not configured', enabled: activation ? (activation.is_enabled ? 'Yes' : 'No') : 'No',
    restarts: activation?.restart_count ?? 0 };
}

let aoToken, aoExpiry = 0;
async function aoGet(path) {
  const base = `${settings().aoUrl}/api/v1`;
  if (!aoToken || Date.now() >= aoExpiry) {
    const auth = await request(`${base}/auth/login`, { headers: { 'Content-Type': 'application/json' },
      body: { username: 'homepage-reader', password: read(`${credentials}/ao-password`) } });
    aoToken = auth.access_token;
    const claims = JSON.parse(Buffer.from(aoToken.split('.')[1], 'base64url'));
    aoExpiry = claims.exp * 1000 - 60000;
  }
  try { return await request(`${base}${path}`, { headers: { Authorization: `Bearer ${aoToken}` } }); }
  catch (error) { if (error.message === 'HTTP 401') aoExpiry = 0; throw error; }
}
async function orchestrator() {
  const workflows = await aoGet('/workflows?name=omnigent-dispatch&limit=100');
  const workflow = workflows.resources.find((item) => item.name === 'omnigent-dispatch');
  const executions = workflow ? await aoGet(`/executions?workflow_id=${workflow.id}&sort=-created_at&limit=5`) : { resources: [] };
  return { workflow: workflow?.published_version_number ? `Published v${workflow.published_version_number}` : 'Not published',
    latest: executions.resources[0]?.status || 'No executions yet',
    executions: executions.resources.map((item) => ({ id: item.id, name: item.workflow_name || item.id.slice(0, 8), status: item.status })) };
}

const sources = { gitops, cluster, monitoring, aap, eda, orchestrator };
const snapshot = {};
let refreshing = false;
async function refresh() {
  if (refreshing) return;
  refreshing = true;
  await Promise.all(Object.entries(sources).map(async ([name, collect]) => {
    try { snapshot[name] = { ...await collect(), available: true, updated: new Date().toISOString() }; }
    catch (error) {
      // Replace failed data instead of showing an old successful state.
      snapshot[name] = { available: false, error: error.message, updated: new Date().toISOString() };
      console.error(`${name}: ${error.message}`);
    }
  }));
  refreshing = false;
}
const server = http.createServer((req, res) => {
  if (req.method !== 'GET') { res.writeHead(405).end(); return; }
  if (req.url === '/health') { res.writeHead(200).end('ok'); return; }
  if (req.url !== '/status' && !/^\/status\/(gitops|cluster|monitoring|aap|eda|orchestrator|environment)$/.test(req.url)) {
    res.writeHead(404).end(); return;
  }
  let environment;
  try { environment = settings(); } catch { environment = { cluster: 'Not configured' }; }
  res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  const data = { ...snapshot, environment: { ...environment,
    revision: snapshot.gitops?.revision || environment.revision,
    branch: snapshot.gitops?.branch || environment.branch, refreshed: new Date().toISOString() } };
  const section = req.url.split('/')[2];
  res.end(JSON.stringify(section ? (data[section] || { error: 'Collecting data' }) : data));
});
server.listen(3001, '127.0.0.1');
refresh();
setInterval(refresh, 30000);
