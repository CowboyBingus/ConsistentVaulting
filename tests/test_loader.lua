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
env.CowboyBingusDiagnostics=true
env.os={getenv=function()return 'fixture' end}
env.io={open=function()
    local chunks={}
    return {write=function(_,s)chunks[#chunks+1]=s end,close=function()logs[#logs+1]=table.concat(chunks)end}
end}
env.CowboyBingusModLoader.open_log=function(name)
    assert(name=='ConsistentVaulting.log')
    return env.io.open('fixture/CowboyBingus/Helldivers2/Logs/'..name,'w')
end
install(env);assert(#logs==1)
for i=1,20 do env.update() end
assert(#logs==1 and env.ConsistentVaulting.updates==20 and env.ConsistentVaulting.polls==40)
now=2.1;env.update();assert(#logs==2 and logs[2]:find('updates=21',1,true))
assert(logs[2]:find('polls=41',1,true) and logs[2]:find('last_phase=before_update',1,true))
-- Probe evidence survives waiting states with its original time and origin.
local fixture=env.ConsistentVaulting
fixture.context_reprojections=4;fixture.reprojected_retries=2;fixture.reprojected_starts=1
fixture.step_report_retries=3;fixture.step_report_starts=2
fixture.last_retry_reason='native_context_changed_before_commit'
fixture.candidate_results={retained_query_reused=1,no_usable_assisted_candidate=2}
fixture.candidate_trace={time=1,root={1,2,3},direction={0,1,0},ground=true,
    result='no_usable_assisted_candidate',passes={ordinary={},slope={},raised={
        {slot=2,count=1,unit=11163,height=2.35,max_height=2.25,normal_z=.7852,normal_threshold=.707107,
            source_height=2.41,target_height=.4,position={1,2,5.35},result='height'}}}}
now=4.2;env.update()
assert(#logs==3 and logs[3]:find('probe_age_seconds=3.200',1,true))
assert(logs[3]:find('context_reprojections=4\n',1,true) and logs[3]:find('reprojected_retries=2\n',1,true)
    and logs[3]:find('reprojected_starts=1\n',1,true)
    and logs[3]:find('last_retry_reason=native_context_changed_before_commit\n',1,true))
assert(logs[3]:find('step_report_retries=3\n',1,true) and logs[3]:find('step_report_starts=2\n',1,true))
assert(logs[3]:find('probe_native_mover=1.000000,2.000000,3.000000',1,true))
assert(logs[3]:find('candidate_result_retained_query_reused=1',1,true))
assert(logs[3]:find('probe_raised_slot_2=count:1 unit:11163 height:2.350000 max:2.250000',1,true))
assert(logs[3]:find('result:height',1,true))
fixture.raised_trace=fixture.candidate_trace
fixture.candidate_trace={time=4,root={10,20,30},direction={0,1,0},ground=true,
    result='ordinary_candidate_retained',passes={ordinary={},slope={},raised={}}}
now=6.3;env.update()
assert(#logs==4 and logs[4]:find('probe_scope=last_raised_search',1,true))
assert(logs[4]:find('probe_native_mover=1.000000,2.000000,3.000000',1,true))
env.shutdown();assert(#logs==5 and logs[5]:find('stopped',1,true))
-- Every terminal path must use unified cleanup, including an apply exception
-- after the assistance module has acquired a lease.
for _,failure in ipairs({'shutdown','apply_exception','apply_rejection','update_exception'}) do
    local cleaned=0
    patch.stop=function(_,_,_,s)cleaned=cleaned+1;s.slope_lease=nil;s.pending=nil;return true end
    patch.apply=function(_,_,_,s)
        s.slope_lease={};s.pending={}
        if failure=='apply_exception' then error('slope fixture failure') end
        if failure=='apply_rejection' then return false,'slope fixture rejected',false end
        return true,'observing',true
    end
    env=environment({api=2,version=6})
    if failure=='update_exception' then env.update=function()error('native update fixture failure')end end
    install(env);pcall(env.update)
    if failure=='shutdown' then env.shutdown() end
    assert(cleaned==1 and env.ConsistentVaulting.slope_lease==nil and env.ConsistentVaulting.pending==nil,failure)
end
print('PASS: loader version/build gates, duplicate load, update/shutdown tuples, failure isolation and throttled heartbeat')

-- Routine gameplay must not write diagnostics unless explicitly enabled.
for _,diagnostics in ipairs({false,true})do
    local now,opens,profiles=0,0,0
    local e=setmetatable({print=function()end},{__index=_G});e._G=e
    e.CowboyBingusDiagnostics=diagnostics
    e.CowboyBingusModLoader={api=1,version=99,open_log=function()
        opens=opens+1;return {write=function()end,close=function()end}
    end}
    e.update=function()return 1,nil,3 end;e.shutdown=function()return 4,nil,6 end
    local api={time=function()return now end,module=function(n)return n or 'exe'end,
        module_hash=function()return 'hash'end,bind=function()return {}end,read=function()return ''end}
    local patch={interval=1/30,apply=function()return true,'waiting_for_mission',false end,
        profiler={new=function()profiles=profiles+1;return {}end},stop=function()return true end,cleanup=function()return true end}
    setfenv(assert(loadfile(source..'/archive_loader.lua')),e)()(function()return api end,patch,
        {revision='fixture',game_sha256='hash',exe_sha256='hash'})
    local startup=opens
    for i=1,600 do now=i/60;local a,b,c=e.update(1/60);assert(a==1 and b==nil and c==3)end
    assert(diagnostics and opens>startup or not diagnostics and opens==startup,'routine log writes require opt-in')

    e.shutdown();assert(opens>startup,'shutdown report remains available')
end
print('PASS: silent default, opt-in diagnostics, shutdown report and callback returns')
