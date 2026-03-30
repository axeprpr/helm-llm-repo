#!/usr/bin/env python3
import yaml, sys
with open('packages/index.yaml') as f:
    idx = yaml.safe_load(f)
for name, versions in idx.get('entries', {}).items():
    print(name + ': ' + str([v['version'] for v in versions]))
