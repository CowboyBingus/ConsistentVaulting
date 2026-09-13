"""Verify the independently loadable resource, provenance and narrow payload."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from archive import ARCHIVE,resource_hash
with zipfile.ZipFile(sys.argv[1]) as package:
    names=package.namelist()
    expected={f'data/{ARCHIVE}{s}' for s in ('','.stream','.gpu_resources')}
    expected|={'manifest.json','ConsistentVaulting-manifest.json','ConsistentVaulting-README.txt'}
    assert set(names)==expected and len(names)==len(expected)
    manager=json.loads(package.read('manifest.json'))
    assert manager['Name']=='Consistent Vaulting' and manager['Options'][0]['Include']==['data']
    provenance=json.loads(package.read('ConsistentVaulting-manifest.json'))
    assert provenance['requires']==[{'name':'Bingus Shared Loader','api':1,'revision':'loader-v4'}]
    assert provenance['runtime_verified'] is False
    assert provenance['revision']=='data-v3'
    for name,digest in provenance['files'].items(): assert hashlib.sha256(package.read(name)).hexdigest().upper()==digest
    data=package.read('data/'+ARCHIVE)
    assert struct.unpack_from('<III',data)==(0xf0000011,1,1)
    entry=struct.unpack_from('<7Q6I',data,104)
    assert entry[0]==resource_hash('mods/cowboybingus/consistent_vaulting') and entry[1]==0xa14e8dfa2cd117e2
    resource=data[entry[2]:entry[2]+entry[7]]
    assert struct.unpack_from('<II',resource)==(len(resource)-8,2) and resource[8:13]==b'\x1bLJ\x02\x02'
    for suffix in ('.stream','.gpu_resources'): assert package.read('data/'+ARCHIVE+suffix)==b''
    for name in names:
        raw=package.read(name).lower()
        for forbidden in (b'virtualalloc',b'virtualprotect',b'flushinstructioncache',b'createremotethread',b'loadlibrary',b'users\\',b'users/'):
            assert forbidden not in raw,(name,forbidden)
print('PASS: sole vault resource, loader dependency, bytecode mode, hashes and no executable payload')
