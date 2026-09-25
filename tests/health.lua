-- Exercise the actual Lua embedded in the ArgoCD resource, not a duplicate.
local check = assert(loadfile(arg[1]))
local kind = arg[2]
local cases = {
  Application = {
    {{}, "Progressing"},
    {{status = {sync = {status = "OutOfSync"}, health = {status = "Healthy"}}}, "Progressing"},
    {{status = {sync = {status = "Synced"}, health = {status = "Healthy"}, operationState = {phase = "Running"}}}, "Progressing"},
    {{status = {sync = {status = "Synced"}, health = {status = "Healthy"}, operationState = {phase = "Failed"}}}, "Degraded"},
    {{status = {sync = {status = "Synced"}, health = {status = "Progressing"}, operationState = {phase = "Succeeded"}}}, "Progressing"},
    {{status = {sync = {status = "Synced"}, health = {status = "Healthy"}, operationState = {phase = "Succeeded"}}}, "Healthy"},
  },
  Subscription = {
    {{}, "Progressing"},
    {{status = {conditions = {}}}, "Progressing"},
    {{status = {installedCSV = "old", currentCSV = "new", state = "AtLatestKnown"}}, "Progressing"},
    {{status = {conditions = {{type = "ResolutionFailed", status = "True"}}}}, "Degraded"},
    {{status = {installedCSV = "v1", currentCSV = "v1", state = "AtLatestKnown", conditions = {{type = "InstallPlanPending", status = "True"}}}}, "Progressing"},
    {{status = {installedCSV = "v1", currentCSV = "v1", state = "AtLatestKnown"}}, "Healthy"},
  },
  Cluster = {
    {{}, "Progressing"},
    {{status = {conditions = {{type = "Ready", status = "False"}}}}, "Progressing"},
    {{status = {conditions = {{type = "Ready", status = "True"}}}}, "Healthy"},
  },
  Database = {
    {{}, "Progressing"},
    {{status = {applied = false}}, "Progressing"},
    {{status = {applied = true}}, "Healthy"},
  },
  AnsibleAutomationPlatform = {
    {{}, "Progressing"},
    {{status = {conditions = {{type = "Running", status = "True"}}}}, "Progressing"},
    {{status = {conditions = {{type = "Failure", status = "True", message = "unknown playbook failure"}}}}, "Degraded"},
    {{status = {conditions = {{type = "Successful", status = "True"}}}}, "Healthy"},
  },
  AutomationOrchestrator = {
    {{}, "Progressing"},
    {{status = {conditions = {{type = "Progressing", status = "True"}}}}, "Progressing"},
    {{status = {conditions = {{type = "Degraded", status = "True"}}}}, "Degraded"},
    {{status = {conditions = {{type = "Ready", status = "True"}}}}, "Healthy"},
  },
  Keycloak = {
    {{}, "Progressing"},
    {{status = {conditions = {{type = "Ready", status = "False"}}}}, "Progressing"},
    {{status = {conditions = {{type = "Ready", status = "True"}}}}, "Healthy"},
  },
}
for i, case in ipairs(assert(cases[kind])) do
  obj = case[1]
  local result = check()
  assert(result.status == case[2], kind .. " case " .. i .. ": " .. result.status)
end
print(kind .. ": " .. #cases[kind] .. " health cases passed")
