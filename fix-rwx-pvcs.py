#!/usr/bin/env python3
import yaml
import sys

def fix_rwx_pvcs(file_path):
    """Update ReadWriteMany PVCs to use nfs storage class"""
    with open(file_path, 'r') as f:
        docs = list(yaml.safe_load_all(f))
    
    modified = False
    for doc in docs:
        if (doc and doc.get('kind') == 'PersistentVolumeClaim' and 
            'ReadWriteMany' in doc.get('spec', {}).get('accessModes', []) and
            doc.get('spec', {}).get('storageClassName') == 'local-path'):
            doc['spec']['storageClassName'] = 'nfs'
            modified = True
            print(f"Updated {doc['metadata']['namespace']}/{doc['metadata']['name']} to use NFS storage")
    
    if modified:
        with open(file_path, 'w') as f:
            yaml.dump_all(docs, f, default_flow_style=False, sort_keys=False)
        return True
    return False

files = [
    'storage/network-storage.yaml',
    'media/media-stack.yaml',
    'smart-home/home-assistant.yaml'
]

for file in files:
    print(f"Processing {file}...")
    if fix_rwx_pvcs(file):
        print(f"✅ Updated {file}")
    else:
        print(f"No changes needed for {file}")

print("\n✅ All ReadWriteMany PVCs updated to use NFS storage class")
