#!/usr/bin/python3
import importlib.machinery, importlib.util, json, sys, time
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("collect_claude", sys.argv[1])
spec = importlib.util.spec_from_loader("collect_claude", loader)
claude = importlib.util.module_from_spec(spec)
loader.exec_module(claude)
claude.open_json = lambda request, timeout=10: {
    "five_hour": {"utilization": 37.0, "resets_at": "2030-01-01T00:00:00Z"},
    "seven_day": {"utilization": 60, "resets_at": "2030-01-02T00:00:00Z"},
    "seven_day_oauth_apps": {"utilization": 1, "resets_at": "2030-01-02T00:00:00Z"},
    "limits": [{"kind": "weekly_scoped", "percent": 12, "resets_at": "2030-01-02T00:00:00Z", "scope": {"model": {"display_name": "Fable"}}}],
}
print(json.dumps(claude.probe_limits("token")))
now = time.time() * 1000
print(claude.collect_limits("token", int(now - 1000), int(now + 100000), False, "a.json")["usageStatusText"])
print(claude.collect_limits("token", int(now - 1000), int(now - 500), False, "a.json")["usageStatusText"])
