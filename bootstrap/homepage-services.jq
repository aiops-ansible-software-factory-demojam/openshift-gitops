def link($name;$url;$icon;$description):
  {($name):{href:$url,icon:$icon,description:$description}};
def widget($name;$url;$icon;$description;$fields):
  ($fields[0][0]|split(".")[0]) as $section |
  link($name;$url;$icon;$description) | .[$name].widget = {
    type:"customapi",url:("http://127.0.0.1:3001/status/" + $section),refreshInterval:30000,display:"list",
    mappings:($fields|map(select(.[0]|endswith(".error")|not)|{field:(.[0]|split(".")[1:]|join(".")),label:.[1]}))};
def listwidget($name;$url;$icon;$description;$items;$namefield;$label;$target):
  ($items|split(".")[0]) as $section |
  link($name;$url;$icon;$description) | .[$name].widget = {
    type:"customapi",url:("http://127.0.0.1:3001/status/" + $section),refreshInterval:30000,display:"dynamic-list",
    mappings:{items:($items|split(".")[1:]|join(".")),name:$namefield,label:$label,limit:5,target:$target}};
($source + "/blob/" + $branch + "/") as $docs |
[
  {"Environment":[
    widget("Current environment";($console + "/dashboards");"openshift";"The cluster serving this demo";
      [["environment.cluster","Cluster"],["environment.backend","Guests"],["environment.ingress","Ingress"],["environment.branch","Branch"]]),
    widget("Bootstrap and deployment";($source + "/tree/" + $branch);"github";"Last successful bootstrap and reconciled Git revision";
      [["environment.bootstrapCompleted","Bootstrap completed"],["environment.revision","Git revision"],["environment.refreshed","Status refreshed"]])
  ]},
  {"Demo walkthrough":[
    link("1. Trigger the outage";($aap + "/execution/templates");"ansible";"Run webapp_selinux_enable once"),
    link("2. Follow the issue";($forgejo + "/demo-owner/ansible-collection-demo.webapp/issues");"forgejo";"The alert and RCA open the issue automatically"),
    link("3. Follow the workflow";($ao + "/executions");"mdi-sitemap";"Forgejo webhook → EDA → Omnigent handoff"),
    link("4. Follow the agent";$omnigent;"mdi-robot";"Watch the coding session and its progress"),
    link("5. Merge after tests";($forgejo + "/demo-owner/ansible-collection-demo.webapp/pulls");"mdi-source-pull";"Merge when lint, build and every Molecule scenario pass"),
    link("6. Deploy the fix";($aap + "/execution/templates");"ansible";"Run webapp_nginx once after merge; SELinux stays Enforcing")
  ]},
  {"Automation":([
    $routes[0][] | .Automation // empty | .[]
  ] + [
    link("EDA rulebook activations";($aap + "/decisions/rulebook-activations");"ansible";"Inspect the webapp alert handler")
  ])}
] + ($routes[0] | map(select(has("Automation") | not))) + [
  {"Git repositories":($repos[0]|map(link(.name;.href;(if .href|contains("github.com") then "github" else "forgejo" end);.description)))},
  {"Useful shortcuts":[
    link("Demo guide";($docs + "README.md");"mdi-book-open-page-variant";"Setup, demo flow and maintenance commands"),
    link("Homepage guide";($docs + "cluster/homepage/README.md");"homepage";"Dashboard configuration and refresh"),
    link("Workflow guide";($docs + "cluster/automation-orchestrator/workflows/README.md");"mdi-sitemap";"How issue-to-PR dispatch works"),
    link("Alerting guide";($docs + "cluster/user-workload-monitoring/README.md");"prometheus";"Blackbox → Alertmanager → EDA → issue"),
    link("Golden paths";($rhdh + "/create");"backstage";"Create a collection or dispatch a feature"),
    (if env.DEMO_BACKEND == "aws" then
      link("Webapp EC2 instance";("https://" + env.AWS_DEMO_REGION + ".console.aws.amazon.com/ec2/home?region=" + env.AWS_DEMO_REGION + "#Instances:tag:demojam%3Apurpose=webapp");"aws";"Monitored guest status and lifecycle")
    else
      link("Webapp virtual machine";($console + "/k8s/ns/webapp-vms/kubevirt.io~v1~VirtualMachine/webapp");"mdi-desktop-classic";"VM status, console and lifecycle")
    end),
    link("Monitoring alerts";($console + "/monitoring/alerts");"prometheus";"Inspect WebappDown and other alerts")
  ]},
  {"Live status":[
    widget("GitOps health";($console + "/k8s/ns/openshift-gitops/argoproj.io~v1alpha1~Application");"argo-cd";"Application reconciliation";
      [["gitops.apps","Apps"],["gitops.synced","Synced"],["gitops.healthy","Healthy"],["gitops.outOfSync","Out of sync"],["gitops.degraded","Degraded"],["gitops.error","Source error"]]),
    widget("Webapp monitoring";($console + "/monitoring/alerts");"prometheus";"Existing blackbox probes and firing demo alerts";
      [["monitoring.webapp","Webapp"],["monitoring.response","Response"],["monitoring.forgejo","Forgejo"],["monitoring.alerts","Alerts"],["monitoring.error","Source error"]]),
    widget("Cluster resources";($console + "/dashboards");"openshift";"Usage relative to allocatable node resources";
      [["cluster.cpu","CPU"],["cluster.memory","Memory"],["cluster.ready","Ready nodes"],["cluster.nodes","Nodes"],["cluster.error","Source error"]]),
    listwidget("Node resources";($console + "/k8s/cluster/nodes");"mdi-server";"Individual node readiness and usage";"cluster.details";"name";"usage";($console + "/k8s/cluster/nodes/{name}")),
    widget("Latest AAP job";($aap + "/execution/jobs");"ansible";"Most recent Controller job";
      [["aap.latestJob","Job"],["aap.status","Result"],["aap.error","Source error"]]),
    widget("EDA activation";($aap + "/decisions/rulebook-activations");"ansible";"Webapp alert-to-issue automation";
      [["eda.state","State"],["eda.enabled","Enabled"],["eda.restarts","Restarts"],["eda.error","Source error"]]),
    widget("Issue-to-PR workflow";($ao + "/workflows");"mdi-sitemap";"Published workflow and latest execution";
      [["orchestrator.workflow","Workflow"],["orchestrator.latest","Latest result"],["orchestrator.error","Source error"]]),
    listwidget("Recent AAP jobs";($aap + "/execution/jobs");"ansible";"Five most recent jobs";"aap.jobs";"name";"status";($aap + "/execution/jobs/playbook/{id}/output")),
    listwidget("Recent workflow executions";($ao + "/executions");"mdi-sitemap";"Five most recent workflow runs";"orchestrator.executions";"name";"status";($ao + "/executions/{id}"))
  ]}
]
