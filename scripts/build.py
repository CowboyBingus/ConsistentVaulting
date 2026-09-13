"""Build the local query-data module; never install or launch the game."""
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
if 'HD2_LUAJIT' not in os.environ and not (ROOT/'tools/src/LuaJIT/src/luajit.exe').exists():
    os.environ['HD2_LUAJIT']=str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe')
from archive import GAME,LUA,EXE_SHA,GAME_DLL_SHA,ARCHIVE,sha,make_archive
from module import build_module
from package import package_release

MODULE='mods/cowboybingus/consistent_vaulting'
REVISION='data-v3'
FORBIDDEN=('VirtualAlloc','VirtualProtect','FlushInstructionCache','CreateRemoteThread',
           'RtlAddFunctionTable','RtlDeleteFunctionTable','LoadLibrary')
def run(args,**kwargs):
    result=subprocess.run(list(map(str,args)),capture_output=True,text=True,**kwargs)
    if result.returncode: raise RuntimeError(result.stdout+result.stderr)
    return result.stdout

def main():
    build=ROOT/'build';build.mkdir(exist_ok=True)
    for relative,expected in [('bin/helldivers2.exe',EXE_SHA),('data/game/game.dll',GAME_DLL_SHA)]:
        if sha((GAME/relative).read_bytes())!=expected: raise ValueError('Unsupported game build')
    for path in (ROOT/'src').glob('*.lua'):
        if any(api in path.read_text(encoding='utf-8') for api in FORBIDDEN):
            raise ValueError('Unsupported executable modification API in '+path.name)
    resources=build_module(ROOT,build,MODULE,'vault_data.lua',REVISION)
    env=dict(os.environ,LUA_PATH=str(LUA.parent/'?.lua')+';;')
    tests=run([LUA,ROOT/'tests/test_vault.lua',ROOT/'src'],env=env)
    tests+=run([LUA,ROOT/'tests/test_loader.lua',ROOT/'src'],env=env)
    (build/ARCHIVE).write_bytes(make_archive(resources))
    for suffix in ('.stream','.gpu_resources'): (build/(ARCHIVE+suffix)).write_bytes(b'')
    files={f'data/{ARCHIVE}{suffix}':f'build/{ARCHIVE}{suffix}' for suffix in ('','.stream','.gpu_resources')}
    report={'name':'Consistent Vaulting','slug':'ConsistentVaulting','revision':REVISION,
        'guid':'d4710210-3515-4f69-b6c5-b1d3c653e784',
        'description':'Local manual-vault retries with refreshed collision queries and original native validation. Requires Bingus Shared Loader loader-v4 or newer / API 1 or newer. data-v3 gameplay validation pending.',
        'game_exe_sha256':EXE_SHA,'game_dll_sha256':GAME_DLL_SHA,'deployment_files':files,
        'files':{p:sha((ROOT/p).read_bytes()) for p in files.values()},
        'requires':[{'name':'Bingus Shared Loader','api':1,'revision':'loader-v4'}],
        'module':MODULE,'runtime_verified':False,'status':'offline_verified_native_retry_pending',
        'executable_memory_changed':False,'custom_dlls':0,'boot_replaced':False,
        'write':{'target':'local avatar query results and temporary query phase only','max_records':10,
                 'max_bytes':120,'fields':['selected fresh hit (44 bytes)','other query unit/actor pairs (8 bytes each)','temporary query phase (4 bytes)'],
                 'protection':'existing MEM_PRIVATE/PAGE_READWRITE only'},
        'native_calls':'Existing build-locked getters, math, approach check in private copy, synchronous physics queries, exit validator and local vault driver with zero dt; no custom executable payload',
        'offline_tests':tests.strip(),
        'source_sha256':{p.relative_to(ROOT).as_posix():sha(p.read_bytes())
            for folder,pattern in [('src','*.lua'),('tests','*.*'),('scripts','*.py')]
            for p in (ROOT/folder).glob(pattern)}}
    release=package_release(ROOT,build,report)
    tests+=run([sys.executable,ROOT/'tests/test_package.py',release])
    report['release']={'path':Path(os.path.relpath(release,ROOT)).as_posix(),'sha256':sha(release.read_bytes())}
    (build/'build-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    (build/'offline-tests.txt').write_text(tests,encoding='utf-8')
    print(tests.strip());print('Built '+str(release)+'; in-game validation pending.')
if __name__=='__main__': main()
