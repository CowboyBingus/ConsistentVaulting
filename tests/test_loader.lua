local source=assert(arg[1])
local function environment(loader)
    local env=setmetatable({print=function()end,os={getenv=function()end},CowboyBingusModLoader=loader},{__index=_G})
    env._G=env
    env.update=function(...)return ... end
    env.shutdown=function(...)return ... end
    return env
end
local calls,restores=0,0
local api={module=function(n)return n and 1 or 2 end,module_hash=function(n)return tostring(n) end}
local patch={apply=function(_,_,_,s)calls=calls+1;s.pending={};return true,'observing',true end,
    restore=function()restores=restores+1;return true end}
local function install(env,adapter)
    local loader=setfenv(assert(loadfile(source..'/archive_loader.lua'))(),env)
    loader(adapter or function()return api end,patch,{revision='test',game_sha256='1',exe_sha256='2'})
end
for _,loader in ipairs({{api=1,version=6},{api=2,version=5},{api=2,version=6},{api=99,version=100}}) do
    local env=environment(loader);local before=calls
    install(env);local a,b,c=env.update(1,nil,3)
    assert(a==1 and b==nil and c==3 and calls==before+2 and env.ConsistentVaulting.active)
    env.shutdown()
end
for _,loader in ipairs({false,{}, {api=1,version=0},{api=1,version=4},{api=0,version=5},
    {api=2,version=4},{api='1',version=5},{api=1,version='5'},{api=1}}) do
    local env=environment(loader);local previous=env.update
    install(env);assert(env.update==previous and not env.ConsistentVaulting.active)
    assert(env.ConsistentVaulting.status:find('Bingus Shared Loader',1,true))
end
calls,restores=0,0
local env=environment({api=1,version=5});install(env)
local a,b,c=env.update('one',nil,'three')
assert(a=='one' and b==nil and c=='three' and calls==2)
assert(select('#',env.update('one',nil,'three'))==3)
local previous=env.update;install(env);assert(env.update==previous)
a,b,c=env.shutdown(1,nil,3);assert(a==1 and b==nil and c==3 and restores==1)
local before=calls;env.update();assert(calls==before)
env=environment({api=1,version=5});previous=env.update
install(env,function()error('unavailable')end);assert(env.update==previous)
env=environment({api=1,version=5});env.update=function()error('original update failure')end
install(env);local before_restore=restores
local succeeded,reason=pcall(env.update)
assert(not succeeded and tostring(reason):find('original update failure',1,true) and restores==before_restore+1)
assert(env.ConsistentVaulting.pending==nil and env.ConsistentVaulting.status=='stopped_after_update_error')
env=environment({api=1,version=5})
patch.apply=function()return false,'deliberate_failure',false end
install(env);env.update();assert(env.ConsistentVaulting.status=='deliberate_failure')

-- A constant waiting status must still produce a fresh heartbeat, while
-- per-frame transitions must not write a log file every frame.
local now,logs=0,{}
api.time=function()return now end
patch.apply=function()return true,'waiting_for_vault_query',false end
env=environment({api=1,version=5})
env.os={getenv=function()return 'fixture' end}
env.io={open=function()
    local chunks={}
    return {write=function(_,s)chunks[#chunks+1]=s end,close=function()logs[#logs+1]=table.concat(chunks)end}
end}
install(env);assert(#logs==1)
for i=1,20 do env.update() end
assert(#logs==1 and env.ConsistentVaulting.updates==20 and env.ConsistentVaulting.polls==40)
now=2.1;env.update();assert(#logs==2 and logs[2]:find('updates=21',1,true))
assert(logs[2]:find('polls=41',1,true) and logs[2]:find('last_phase=before_update',1,true))
env.shutdown();assert(#logs==3 and logs[3]:find('stopped',1,true))
print('PASS: loader version/build gates, duplicate load, update/shutdown tuples, failure isolation and throttled heartbeat')
