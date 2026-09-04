#!/usr/bin/env python3
"""
22-19: re-derive tenant-isolation.md's headline counts from a source scan of ago-chat's
Ago.Chat.Application/UseCases, approximating TenantScopeRule.Scan's IL walk with a text-level
scan of the C# source. Not a substitute for TenantScopeTests (which reads IL and is the real
gate) -- a reproducible cross-check of what that gate is currently enforcing.

Usage: python scan_tenant_scope.py <path-to-ago-chat-checkout-root>

Method, mirroring TenantScopeRule.Scan (tests/Ago.Chat.Architecture.Tests/TenantScopeRule.cs):
  1. Every file matching src/Ago.Chat.Application/UseCases/**/*Handler.cs is one handler *file*
     (may declare more than one class, though in practice each declares exactly one).
  2. Within each such class (class name ends with "Handler"), every method whose signature starts
     with "public" and is not a constructor is one *entry point*, keyed
     "<Namespace>.<Type>.<Method>" -- the same key TenantScopeExemptions.cs uses.
  3. CarriesSiteId: the entry point's first non-CancellationToken parameter is typed `SiteId`
     directly, OR is a command/query record type whose declaration (found by grepping the same
     directory tree for `record <TypeName>(`) lists a `SiteId` member. One level, no recursion --
     the same shallowness TenantScopeRule.Scan documents for itself.
  4. ChecksPermission: the method body (from its opening brace to the matching close, by naive
     brace counting) contains a call written `.HasPermissionAsync(` or `.GetPermissionsAsync(` --
     the two methods IPermissionChecker declares, confirmed unique to that interface in this
     codebase (see report). This does not follow IL into a state machine; it works because these
     handler bodies are the async method themselves in source, whatever the compiler does to them.
  5. IsRbacGated = CarriesSiteId and ChecksPermission.
  6. Cross-reference every entry point's key against TenantScopeExemptions.cs's dictionary keys
     (extracted by regex over the `["...Key..."] =` lines) to say ExemptListed.
  7. unaccounted = entry points that are neither IsRbacGated nor ExemptListed -- what
     TenantScopeTests' first assertion would fail on, if this approximation matches the real IL
     scan. Report these as findings, don't force them into a category.
"""
import re
import sys
import os
import json
from pathlib import Path

def main():
    root = Path(sys.argv[1])
    usecases_dir = root / "src" / "Ago.Chat.Application" / "UseCases"
    exemptions_file = root / "tests" / "Ago.Chat.Architecture.Tests" / "TenantScopeExemptions.cs"

    handler_files = sorted(usecases_dir.rglob("*Handler.cs"))
    print(f"Handler.cs files under UseCases: {len(handler_files)}")

    # ---- Step A: collect every `record TypeName(...)` and `class TypeName` / `record TypeName` with
    # a body, across the whole UseCases tree, to resolve parameter types' SiteId membership.
    record_members = {}  # TypeName -> set of member type-annotations (raw text) for positional records
    class_body_members = {}  # TypeName -> set of property types, for block-bodied records/classes
    all_cs = list(usecases_dir.rglob("*.cs"))
    for f in all_cs:
        text = f.read_text(encoding="utf-8-sig")
        # positional record: record Name(Type1 Name1, Type2 Name2, ...)
        for m in re.finditer(r'\brecord\s+(\w+)\s*\(([^)]*)\)', text, re.DOTALL):
            tname, params = m.group(1), m.group(2)
            members = set()
            for p in params.split(','):
                p = p.strip()
                if not p:
                    continue
                # "Type Name" possibly with default; take first token(s) before the last identifier
                pm = re.match(r'^(.+?)\s+(\w+)(\s*=.*)?$', p)
                if pm:
                    members.add(pm.group(1).strip())
            record_members.setdefault(tname, set()).update(members)
        # block-bodied class/record with { get; } properties
        for m in re.finditer(r'\b(?:record|class)\s+(\w+)\s*(?::[^{]*)?\{', text):
            tname = m.group(1)
            start = m.end() - 1
            depth = 0
            end = None
            for i in range(start, len(text)):
                if text[i] == '{':
                    depth += 1
                elif text[i] == '}':
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
            if end is None:
                continue
            body = text[start:end]
            for pm in re.finditer(r'public\s+([\w<>\[\],.\s]+?)\s+(\w+)\s*\{\s*get;', body):
                class_body_members.setdefault(tname, set()).add(pm.group(1).strip())

    def type_carries_site_id(type_name):
        type_name = type_name.strip().lstrip('@')
        if type_name == 'SiteId':
            return True
        members = record_members.get(type_name, set()) | class_body_members.get(type_name, set())
        return any(t.split('<')[0].split('.')[-1].strip() == 'SiteId' for t in members)

    # ---- Step B: scan handler files for entry points.
    entry_points = []  # (key, file, carries_site_id, checks_permission)
    class_re = re.compile(r'\b(?:public|internal)\s+(?:sealed\s+|abstract\s+)?class\s+(\w+)')
    # method signature: public [async] ReturnType Name(Params), followed by either a block body `{`
    # or an expression body `=>` -- both are legal C# and this codebase uses both (e.g.
    # ProcessYooKassaWebhookHandler.HandleAsync, GetAttachmentDownloadUrlHandler.HandleAsVisitorAsync).
    method_re = re.compile(
        r'public\s+(?:async\s+)?[\w<>\[\],.\s?]+?\s+(\w+)\s*\(([^)]*)\)\s*(?=\{|\n?\s*\{|=>)'
    )

    for f in handler_files:
        text = f.read_text(encoding="utf-8-sig")
        ns_m = re.search(r'namespace\s+([\w.]+);', text)
        namespace = ns_m.group(1) if ns_m else "?"
        # find class blocks (handle possibly >1 class per file, though none expected)
        for cm in class_re.finditer(text):
            cname = cm.group(1)
            if not cname.endswith("Handler"):
                continue
            # find this class's body span by brace counting from its first '{' after the match
            brace_start = text.find('{', cm.end())
            # class declared with primary constructor may have '(' before '{' -- find the '{' that
            # opens the class body, i.e. skip the primary-constructor parens
            scan_pos = cm.end()
            depth_paren = 0
            i = scan_pos
            while i < len(text):
                if text[i] == '(':
                    depth_paren += 1
                elif text[i] == ')':
                    depth_paren -= 1
                elif text[i] == '{' and depth_paren <= 0:
                    brace_start = i
                    break
                i += 1
            depth = 0
            class_end = None
            for i in range(brace_start, len(text)):
                if text[i] == '{':
                    depth += 1
                elif text[i] == '}':
                    depth -= 1
                    if depth == 0:
                        class_end = i
                        break
            if class_end is None:
                continue
            class_body = text[brace_start:class_end]

            for mm in method_re.finditer(class_body):
                mname = mm.group(1)
                params_raw = mm.group(2)
                if mname == cname:
                    continue  # constructor
                if mname in ("ToString", "Equals", "GetHashCode", "Deconstruct"):
                    continue
                # find method body span -- block body `{ ... }` or expression body `=> ...;`
                tail_pos = mm.end()
                while tail_pos < len(class_body) and class_body[tail_pos] in ' \t\r\n':
                    tail_pos += 1
                if class_body[tail_pos:tail_pos + 2] == '=>':
                    depth = 0
                    mend = None
                    for i in range(tail_pos, len(class_body)):
                        c = class_body[i]
                        if c in '([{':
                            depth += 1
                        elif c in ')]}':
                            depth -= 1
                        elif c == ';' and depth == 0:
                            mend = i
                            break
                    if mend is None:
                        continue
                    mbody = class_body[tail_pos:mend]
                else:
                    mbrace = class_body.find('{', mm.end() - 1)
                    if mbrace == -1:
                        continue
                    depth = 0
                    mend = None
                    for i in range(mbrace, len(class_body)):
                        if class_body[i] == '{':
                            depth += 1
                        elif class_body[i] == '}':
                            depth -= 1
                            if depth == 0:
                                mend = i
                                break
                    if mend is None:
                        continue
                    mbody = class_body[mbrace:mend]

                checks_permission = bool(re.search(r'\.(HasPermissionAsync|GetPermissionsAsync)\s*\(', mbody))

                carries_site_id = False
                for p in params_raw.split(','):
                    p = p.strip()
                    if not p:
                        continue
                    pm = re.match(r'^(.+?)\s+(\w+)$', p)
                    if not pm:
                        continue
                    ptype = pm.group(1).strip()
                    if ptype == 'CancellationToken':
                        continue
                    if type_carries_site_id(ptype):
                        carries_site_id = True
                        break

                key = f"{namespace}.{cname}.{mname}"
                entry_points.append({
                    "key": key,
                    "file": str(f.relative_to(root)),
                    "carries_site_id": carries_site_id,
                    "checks_permission": checks_permission,
                })

    # de-dup (shouldn't be needed, but safety)
    seen = {}
    for e in entry_points:
        seen[e["key"]] = e
    entry_points = list(seen.values())

    # ---- Step C: exemptions.
    exemptions_text = exemptions_file.read_text(encoding="utf-8-sig")
    exempt_keys = set(re.findall(r'\["([\w.]+)"\]\s*=', exemptions_text))

    classes = sorted(set(e["key"].rsplit('.', 1)[0] for e in entry_points))

    gated = [e for e in entry_points if e["carries_site_id"] and e["checks_permission"]]
    exempt = [e for e in entry_points if e["key"] in exempt_keys]
    gated_keys = set(e["key"] for e in gated)
    unaccounted = [e for e in entry_points if e["key"] not in gated_keys and e["key"] not in exempt_keys]
    exempt_but_also_looks_gated = [e for e in exempt if e["key"] in gated_keys]
    exempt_keys_missing_from_scan = exempt_keys - set(e["key"] for e in entry_points)

    print(f"Entry points found:        {len(entry_points)}")
    print(f"Handler classes:           {len(classes)}")
    print(f"Approx RBAC-gated:         {len(gated)}")
    print(f"Listed in exemptions:      {len(exempt)}")
    print(f"Unaccounted (neither):     {len(unaccounted)}")
    print(f"Exempt but approx-gated:   {len(exempt_but_also_looks_gated)}")
    print(f"Exemption keys not found in scan (renamed/removed?): {len(exempt_keys_missing_from_scan)}")
    print(f"Total exemption entries in TenantScopeExemptions.cs: {len(exempt_keys)}")

    print("\n--- UNACCOUNTED (neither approx-gated nor exempt-listed) ---")
    for e in unaccounted:
        print(f"  {e['key']}  (carries_site_id={e['carries_site_id']}, checks_permission={e['checks_permission']})  [{e['file']}]")

    print("\n--- EXEMPT BUT ALSO LOOKS GATED (approximation mismatch to check by hand) ---")
    for e in exempt_but_also_looks_gated:
        print(f"  {e['key']}  [{e['file']}]")

    print("\n--- EXEMPTION KEYS NOT FOUND IN SCAN ---")
    for k in sorted(exempt_keys_missing_from_scan):
        print(f"  {k}")

    out = {
        "handler_files": len(handler_files),
        "entry_points": len(entry_points),
        "handler_classes": len(classes),
        "approx_gated": len(gated),
        "exempt_listed": len(exempt),
        "unaccounted": [e["key"] for e in unaccounted],
        "exempt_but_also_looks_gated": [e["key"] for e in exempt_but_also_looks_gated],
        "exempt_keys_missing_from_scan": sorted(exempt_keys_missing_from_scan),
        "all_entry_points": entry_points,
    }
    out_path = root.parent / "tenant_scope_scan_output.json"
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    print(f"\nFull data written to {out_path}")

if __name__ == "__main__":
    main()
