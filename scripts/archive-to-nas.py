#!/usr/bin/env python3
"""Archive one explicitly selected inactive tree; verify before optional retirement.

Default is inspection only. Archives retain macOS tar metadata. Verification
reads every regular file back from the remote tar, then rechecks the source.
No cache classification, broad discovery, or automatic deletion is performed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import sys
import time


def digest(stream):
    value = hashlib.sha256()
    for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
        value.update(chunk)
    return value.hexdigest()


def inventory(root):
    entries = {}
    for parent, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(parent) / name
            info = path.lstat()
            entry = {"mode": stat.S_IMODE(info.st_mode), "mtime_ns": info.st_mtime_ns}
            if path.is_symlink():
                entry.update(kind="link", target=os.readlink(path))
            elif path.is_dir():
                entry.update(kind="directory")
            elif path.is_file():
                with path.open("rb") as stream:
                    entry.update(kind="file", size=info.st_size, sha256=digest(stream))
            else:
                raise RuntimeError(f"special file must be handled explicitly: {path}")
            entries[str(path.relative_to(root))] = entry
    return entries


def assert_inactive(root):
    # lsof's global listing avoids traversing hundreds of thousands of paths.
    result = subprocess.run(["lsof", "-nP", "-Fpn"], capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise RuntimeError("cannot establish inactivity with lsof: " + result.stderr[:300])
    prefix = str(root) + "/"
    for line in result.stdout.splitlines():
        if line.startswith("n") and (line[1:] == str(root) or line[1:].startswith(prefix)):
            raise RuntimeError("open file or working directory: " + line[1:])


REMOTE_VERIFY = r'''
import hashlib,json,sys,tarfile
archive,manifest=sys.argv[1:]
expected=json.load(open(manifest))
seen=set()
with tarfile.open(archive, 'r|*') as tar:
 for member in tar:
  name=member.name.removeprefix('./').rstrip('/')
  if name in ('', '.'): continue
  # BSD tar's AppleDouble records preserve resource forks, ACLs and xattrs.
  if any(p.startswith('._') for p in name.split('/')) and name not in expected: continue
  if name not in expected: raise SystemExit('unexpected archive member: '+name)
  if name in seen: raise SystemExit('duplicate archive member: '+name)
  item=expected[name]
  if member.islnk():
   target=member.linkname.removeprefix('./')
   if target not in seen or expected[target].get('sha256')!=item.get('sha256') or item['kind']!='file': raise SystemExit('hardlink mismatch: '+name)
  elif member.isfile():
   if item['kind']!='file': raise SystemExit('file type mismatch: '+name)
   h=hashlib.sha256(); size=0
   f=tar.extractfile(member)
   if f is None: raise SystemExit('unreadable archive file: '+name)
   for chunk in iter(lambda:f.read(4*1024*1024),b''): h.update(chunk); size+=len(chunk)
   if h.hexdigest()!=item['sha256'] or size!=item['size']: raise SystemExit('content mismatch: '+name)
  elif member.issym():
   if item['kind']!='link' or member.linkname!=item['target']: raise SystemExit('symlink mismatch: '+name)
  elif not (member.isdir() and item['kind']=='directory'): raise SystemExit('type mismatch: '+name)
  if member.mode!=item['mode']: raise SystemExit('mode mismatch: '+name)
  seen.add(name)
if seen!=set(expected): raise SystemExit('missing archive entries: '+repr(set(expected)-seen))
print(json.dumps({'verifiedEntries':len(seen)}))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--host", default="mackieg@newnas")
    parser.add_argument("--destination", required=True, help="new, absolute NAS archive basename (without .tar)")
    parser.add_argument("--receipts", required=True, type=Path)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--compress", action="store_true", help="gzip the archive in transit (useful for dependency caches)")
    parser.add_argument("--retire", action="store_true", help="remove only the verified inactive source after remote verification")
    args = parser.parse_args()
    source = args.source.absolute()
    if source.is_symlink() or not source.is_dir() or len(source.parts) < 5:
        raise RuntimeError("select a real, specific directory, not a symlink or broad root")
    destination = Path(args.destination)
    if not args.destination.startswith("/tank/archive/fleet-storage/") or ".." in destination.parts:
        raise RuntimeError("destination must be under /tank/archive/fleet-storage/")
    assert_inactive(source)
    original = source.stat()
    before = inventory(source)
    byte_count = sum(item.get("size", 0) for item in before.values())
    print(json.dumps({"source": str(source), "entries": len(before), "fileBytes": byte_count,
                      "destination": args.destination + ".tar", "apply": args.apply}), flush=True)
    if not args.apply:
        return
    args.receipts.mkdir(parents=True, exist_ok=True)
    tag = source.name + "-" + str(int(time.time()))
    manifest = args.receipts / (tag + ".manifest.json")
    manifest.write_text(json.dumps(before, sort_keys=True))
    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", args.host]
    remote = args.destination
    q = shlex.quote
    subprocess.run(ssh + ["umask 077; mkdir -p " + q(str(Path(remote).parent)) +
                         "; test ! -e " + q(remote + ".tar") + " && test ! -e " + q(remote + ".partial")], check=True)
    subprocess.run(["scp", "-q", str(manifest), args.host + ":" + remote + ".manifest.json"], check=True)
    # The metadata-bearing tar is streamed, so migration requires no local staging space.
    tar = subprocess.Popen(["tar", "-czf" if args.compress else "-cf", "-", "-C", str(source), "."], stdout=subprocess.PIPE)
    receiver = subprocess.Popen(ssh + ["umask 077; cat > " + q(remote + ".partial")], stdin=subprocess.PIPE)
    checksum = hashlib.sha256()
    try:
        while chunk := tar.stdout.read(4 * 1024 * 1024):
            checksum.update(chunk)
            receiver.stdin.write(chunk)
        receiver.stdin.close()
        if tar.wait() != 0 or receiver.wait() != 0:
            raise RuntimeError("archive transfer failed; source retained")
    finally:
        if tar.poll() is None:
            tar.terminate()
        if receiver.poll() is None:
            receiver.terminate()
    remote_hash = subprocess.check_output(ssh + ["python3 -c " + q(
        "import hashlib,os,sys; f=open(sys.argv[1],'rb'); os.fsync(f.fileno()); h=hashlib.sha256(); "
        "[h.update(c) for c in iter(lambda:f.read(4*1024*1024),b'')]; print(h.hexdigest())") +
        " " + q(remote + ".partial")], text=True).strip()
    if remote_hash != checksum.hexdigest():
        raise RuntimeError("archive checksum mismatch; source retained")
    verification = subprocess.check_output(ssh + ["python3 -c " + q(REMOTE_VERIFY) + " " +
        q(remote + ".partial") + " " + q(remote + ".manifest.json")], text=True).strip()
    if inventory(source) != before or (source.stat().st_dev, source.stat().st_ino) != (original.st_dev, original.st_ino):
        raise RuntimeError("source changed during archival; source retained")
    assert_inactive(source)
    subprocess.run(ssh + ["mv " + q(remote + ".partial") + " " + q(remote + ".tar") +
                         "; sync -f " + q(remote + ".tar")], check=True)
    receipt = {"source": str(source), "host": args.host, "archive": remote + ".tar",
               "archiveSha256": remote_hash, "fileBytes": byte_count, "verification": json.loads(verification),
               "retired": False, "restore": f"ssh {args.host} 'cat {remote}.tar' | tar -xpf - -C RESTORE_DIRECTORY"}
    receipt_path = args.receipts / (tag + ".receipt.json")
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    if args.retire:
        # Rename first: fail closed on a newly opened/mutated tree before deletion.
        parked = source.with_name(source.name + ".LAB-1-retiring")
        if parked.exists():
            raise RuntimeError("retirement path already exists; source retained")
        source.rename(parked)
        try:
            assert_inactive(parked)
            if inventory(parked) != before:
                raise RuntimeError("source changed before retirement")
        except BaseException:
            if not source.exists():
                parked.rename(source)
            raise
        shutil.rmtree(parked)
        receipt["retired"] = True
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    subprocess.run(["scp", "-q", str(receipt_path), args.host + ":" + remote + ".receipt.json"], check=True)
    print(json.dumps(receipt), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
