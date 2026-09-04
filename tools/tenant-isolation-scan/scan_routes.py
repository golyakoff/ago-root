#!/usr/bin/env python3
"""
22-19: mechanical re-derivation of tenant-isolation.md's routes row (row 4: "HTTP routes and hub
methods that carry tenant data") and client-supplied-siteId row (row 5), from ago-chat's
Ago.Chat.Api project plus its two SignalR hubs.

Usage: python scan_routes.py <path-to-ago-chat-checkout-root>

Method:
  1. Every `<var>.Map(Get|Post|Put|Delete|Patch)("<path>", ...)` call in src/Ago.Chat.Api, where
     <var> is either `app` (a top-level route) or a variable bound by a preceding
     `var <var> = app.MapGroup("<prefix>")` (or `.MapGroup("<prefix>")` chained off another group)
     in the same file -- resolved by simple prefix concatenation, file by file. This mirrors how a
     reader would resolve the route by eye, not a runtime route table (Minimal API route groups can
     nest in ways this does not model, but this codebase's own route files are one level deep).
  2. One row `GET /healthz/version` is excluded: it carries no tenant data by inspection (no
     handler, no site). Every other resolved route is counted as "carries tenant data" -- carrying
     forward the existing document's own judgment that even a webhook or a tenant-creating route
     counts, since the alternative (a route judged case by case) is exactly the kind of hand
     count that drifts.
  3. client_supplied = the resolved path contains a route parameter whose name is exactly `siteId`
     (`{siteId...}`), which is how every existing client-supplied-siteId route in this document is
     shaped (`/api/v1/sites/{siteId}/...`).
  4. Hub methods: every public method on OperatorHub/VisitorHub (excluding OnConnectedAsync/
     OnDisconnectedAsync, which are lifecycle callbacks already covered by SetOperatorPresenceHandler's
     own exemption, not tenant-data routes in the sense this row counts) is one more "route" in this
     row, never client-supplied (hub methods take a conversation id or nothing, per the document's own
     existing note on this).
"""
import re
import sys
from pathlib import Path

def main():
    root = Path(sys.argv[1])
    api_dir = root / "src" / "Ago.Chat.Api"

    routes = []  # (method, path, file)
    map_call_re = re.compile(r'(\w+)\.Map(Get|Post|Put|Delete|Patch)\(\s*"([^"]*)"')
    group_re = re.compile(r'(?:var\s+)?(\w+)\s*=\s*(\w+)\.MapGroup\(\s*"([^"]*)"')

    for f in sorted(api_dir.rglob("*.cs")):
        text = f.read_text(encoding="utf-8-sig")
        prefixes = {"app": ""}
        # resolve group variables to a full prefix, allowing group-on-group chaining, in file order
        for gm in re.finditer(r'(?:var\s+)?(\w+)\s*=\s*(\w+)\.MapGroup\(\s*"([^"]*)"\s*\)', text):
            var, base, suffix = gm.group(1), gm.group(2), gm.group(3)
            base_prefix = prefixes.get(base, "")
            prefixes[var] = base_prefix + suffix
        for mm in map_call_re.finditer(text):
            var, verb, path = mm.group(1), mm.group(2), mm.group(3)
            if var not in prefixes:
                continue  # not a route-mapping variable we resolved (e.g. a different fluent API)
            full_path = prefixes[var] + path
            routes.append((verb.upper(), full_path, str(f.relative_to(root))))

    # de-dup identical (verb, path) pairs (e.g. Program.cs re-listing via MapXEndpoints aggregator)
    seen = set()
    deduped = []
    for r in routes:
        key = (r[0], r[1])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(r)
    routes = deduped

    excluded = [r for r in routes if r[1] == "/healthz/version"]
    counted = [r for r in routes if r[1] != "/healthz/version"]
    client_supplied = [r for r in counted if re.search(r'\{siteId(?::[a-z]+)?\}', r[1])]

    print(f"Raw Map* calls resolved: {len(routes)}")
    print(f"Excluded (no tenant data): {len(excluded)} -> {[r[1] for r in excluded]}")
    print(f"Counted HTTP routes: {len(counted)}")
    print(f"Client-supplied siteId routes: {len(client_supplied)}")

    print("\n--- ALL COUNTED ROUTES ---")
    for verb, path, f in sorted(counted, key=lambda r: r[1]):
        marker = " [CLIENT-SUPPLIED siteId]" if re.search(r'\{siteId(?::[a-z]+)?\}', path) else ""
        print(f"  {verb:6s} {path}{marker}   ({f})")

    # ---- Hub methods ----
    hub_files = list((root / "src" / "Ago.Chat.Api").rglob("*Hub.cs"))
    if not hub_files:
        hub_files = list(root.rglob("*Hub.cs"))
    print(f"\nHub files found: {[str(h.relative_to(root)) for h in hub_files]}")
    hub_methods = []
    for f in hub_files:
        text = f.read_text(encoding="utf-8-sig")
        cm = re.search(r'class\s+(\w+)', text)
        cname = cm.group(1) if cm else f.stem
        for mm in re.finditer(r'public\s+(?:override\s+)?(?:async\s+)?[\w<>\[\],.\s?]+?\s+(\w+)\s*\(', text):
            name = mm.group(1)
            if name in ("OnConnectedAsync", "OnDisconnectedAsync", cname):
                continue
            hub_methods.append(f"{cname}.{name}")
    hub_methods = sorted(set(hub_methods))
    print(f"Hub methods counted: {len(hub_methods)}")
    for h in hub_methods:
        print(f"  {h}")

    print(f"\nTOTAL routes+hub methods (row 4): {len(counted) + len(hub_methods)}")
    print(f"TOTAL client-supplied siteId routes (row 5): {len(client_supplied)}")

if __name__ == "__main__":
    main()
