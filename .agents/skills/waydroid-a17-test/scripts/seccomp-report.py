#!/usr/bin/env python3
"""Fail-closed comparison of traced calls with recursively expanded policy.

The current policy uses unconditional rules and socket equality predicates.
Unknown predicates are failures, never silently counted as covered.
"""
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
policy = {}
for line in (root / 'policy.expanded').read_text().splitlines():
    line = line.split('#', 1)[0].strip()
    if not line:
        continue
    name, expr = line.split(':', 1)
    policy.setdefault(name.strip(), []).append(expr.strip())
constants = {'AF_UNIX': 1, 'SOCK_DGRAM': 2, 'SOCK_CLOEXEC': 0x80000,
             'SOCK_NONBLOCK': 0x800}

def number(s):
    value = 0
    for atom in s.strip().split('|'):
        atom = atom.strip()
        value |= constants[atom] if atom in constants else int(atom, 0)
    return value

def covered(name, args):
    for expr in policy.get(name, []):
        if expr == '1':
            return True
        try:
            for alternative in expr.split('||'):
                ok = True
                for term in alternative.split('&&'):
                    m = re.fullmatch(r'\s*arg([0-5])\s*==\s*(\S+)\s*', term)
                    if not m:
                        raise ValueError('unsupported predicate: ' + term)
                    ok &= number(args[int(m[1])]) == number(m[2])
                if ok:
                    return True
        except (ValueError, IndexError):
            pass
    return False

result = {}
failed = False
for window in ('cold', 'steady'):
    text = (root / (window + '.strace')).read_text()
    calls = []
    installed = window == 'steady'
    pre = set()
    post = set()
    missing = set()
    for lineno, line in enumerate(text.splitlines(), 1):
        m = re.match(r'^\s*(?:\[pid\s+)?\d+\]?\s+(\w+)\((.*)', line)
        if not m:
            continue
        name, rest = m.groups()
        if not installed:
            pre.add(name)
            if re.search(r'prctl\(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, \{len=\d+,.*\}\)\s+= 0', line):
                installed = True
                result['filter_install_line'] = lineno
            continue
        post.add(name)
        # Only equality-constrained socket arguments need numeric decoding;
        # all other current rules are unconditional, including crash_dump.
        arguments = re.split(r'\)\s+=|\s+<unfinished', rest, maxsplit=1)[0]
        ok = covered(name, arguments.split(','))
        calls.append({'line': lineno, 'syscall': name, 'covered': ok, 'trace': line})
        if not ok:
            missing.add(name)
    if not installed or (window == 'cold' and not re.search(r'\bexecve\(', text)):
        raise SystemExit('cold trace lacks exec or successful non-NULL filter install')
    if window == 'cold' and 'IComponentStore/default registered' not in text:
        raise SystemExit('cold trace does not reach Store registration')
    sigsys = bool(re.search(r'--- SIGSYS|\+\+\+.*SIGSYS', text))
    result[window] = {'pre': sorted(pre), 'post': sorted(post),
                      'pre_not_listed': sorted(pre - policy.keys()),
                      'uncovered': sorted(missing), 'SIGSYS': sigsys}
    (root / (window + '-calls.json')).write_text(json.dumps(calls, indent=2) + '\n')
    for suffix, names in [('pre', pre), ('post', post), ('uncovered', missing)]:
        (root / f'{window}-{suffix}.syscalls').write_text(''.join(n + '\n' for n in sorted(names)))
    failed |= bool(missing) or sigsys
(root / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
sys.exit(int(failed))
