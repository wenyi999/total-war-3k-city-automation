#!/usr/bin/env python3
"""Extract PFH5 pack records for audit; no extraction path escapes allowed."""
import sys, struct
from pathlib import Path
pack=Path(sys.argv[1]); dest=Path(sys.argv[2]); data=pack.read_bytes()
assert data[:3]==b'PFH', 'Invalid pack signature'
n,size=struct.unpack_from('<II',data,16);idx=28;entries=[]
for _ in range(n):
 length=struct.unpack_from('<I',data,idx)[0];idx+=5
 end=data.index(0,idx);path=data[idx:end].decode();idx=end+1;entries.append((path,length))
assert idx==28+size
offset=idx
for name,length in entries:
 target=dest.joinpath(*name.replace('\\','/').split('/'))
 assert target.resolve().is_relative_to(dest.resolve())
 target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data[offset:offset+length]);offset+=length
assert offset==len(data)
print(f'Extracted {n} files from {pack}')
