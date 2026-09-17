local source=assert(arg[1])
local ffi=require('ffi')
local patch=assert(loadfile(source..'/vault_data.lua'))()
local regions={}
local function region(address,size)
    local data=ffi.new('uint8_t[?]',size)
    regions[#regions+1]={address=address,size=size,data=data}
    return data
end
local function put(data,o,kind,v) ffi.copy(data+o,ffi.new(kind..'[1]',v),ffi.sizeof(kind)) end
local function u(data,o,v) put(data,o,'uint32_t',v) end
local function p(data,o,v) put(data,o,'uint64_t',v) end
local function f(data,o,v) put(data,o,'float',v) end
local function vector(data,o,x,y,z) f(data,o,x);f(data,o+4,y);f(data,o+8,z) end
local function locate(address,size)
    for _,r in ipairs(regions) do
        if address>=r.address and address+size<=r.address+r.size then return r.data+address-r.address end
    end
    error(string.format('Unbounded fixture read %x + %x',address,size))
end
local game,exe,pm,mode,owner,manager,scheduler,movement,camera=
    0x10000000,0x20000000,0x30000000,0x31000000,0x40000000,0x50000000,0x60000000,0x70000000,0x71000000
local player_address=0x32000000
local globals={}
for _,rva in ipairs({0x276c3d0,0x276c190,0x276f0c0,0x276ca30,0x276c280,0x2770688}) do globals[rva]=region(game+rva,8) end
p(globals[0x276c3d0],0,mode);p(globals[0x276c190],0,pm);p(globals[0x276f0c0],0,owner)
p(globals[0x276ca30],0,manager);p(globals[0x276c280],0,movement);p(globals[0x2770688],0,camera)
local players,mission,player=region(pm,0x440),region(mode,0x44),region(player_address,24)
local avatars=region(manager,0x550000)
local queries=region(scheduler,0x40070)
local mv=region(movement,0x48e0)
local cam=region(camera,0x40)
local unitmap=region(owner+0xf21a88,20)
local entities=region(owner+0xf31ad8,48)
local function map(header,o,address,key,index)
    p(header,o,address);u(header,o+8,16);u(header,o+12,0xffffffff);u(header,o+16,1)
    local rows=region(address,128)
    for i=0,15 do u(rows,8*i,0xffffffff) end
    u(rows,key%16*8,key);u(rows,key%16*8+4,index)
    return rows
end
local unitrows=map(unitmap,0,0x72000000,9,1)
local avatarrows=map(avatars,0xf8,0x72100000,222,1)
u(avatarrows,111%16*8,111);u(avatarrows,111%16*8+4,0)
local overrides=map(avatars,0x547c70,0x72200000,222,1)
map(mv,0x48a0,0x72300000,222,0)
local move=region(0x72400000,132);local mover=region(0x72500000,164)
p(mv,0x48c8,0x72400000);p(mv,0x48d0,0x72500000);u(mover,76,123)
u(mission,8,1);u(mission,0x40,1);u(players,0x84,2);u(players,0x88,2)
p(players,0xe8,player_address);u(players,0x3a8,9);player[20]=1
for i=0,1 do
    ffi.copy(entities+i*24,'\151\250\077\041\077\051\028\077',8)
    u(entities,i*24+8,i==0 and 111 or 222);u(entities,i*24+12,i==0 and 333 or 444);entities[i*24+20]=1
    p(avatars,0x110+i*8,owner+0xf31ad8+i*24)
end
u(avatars,0x6c,2);p(avatars,0x28,scheduler)
local local_offset=0x53e1b8+0x1238
local controller=manager+local_offset
local control=avatars+local_offset
local remote=avatars+0x53e1b8
u(control,0x2ac,222);u(remote,0x2ac,111)
local input_offset=0x150+0xa7aec+0x1b68+14*32
avatars[input_offset]=1
local settings=avatars+0x547d24+0x354
f(settings,0x98,45);f(settings,0x104,1.95);f(settings,0x108,1.4)
local component_pointer=region(owner+0xf11778,8)
local component=region(0x72600000,1736);p(component_pointer,0,0x72600000)
ffi.copy(component,entities+24,8);u(component,8,0)
f(component+32,0x98,45);f(component+32,0x104,1.95);f(component+32,0x108,1.4)
vector(cam,0x1c,0,1,0)
local actor_flags,actor_speed,exit_calls={},{},0
local native={
    mover_position=function(unit,name)assert(unit==444 and name==123);return {0,0,0} end,
    actor=function(id)
        if id==0xffffffff then return {valid=false} end
        return {valid=true,flags=actor_flags[id] or 0,motion_squared=actor_speed[id] or 0}
    end,
    exit=function(entity,target,direction)
        assert(entity==owner+0xf31ad8+24 and direction[2]==1)
        exit_calls=exit_calls+1
        return target[1]==13 and 5 or 3
    end,
}
local writes,fail_write,partial_write,unreadable,changed_before_write=0,nil,nil,nil,nil
local api={native=function(g,e)assert(g==game and e==exe);return native end,distance=function(a,b)return a-b end}
api.read=function(address,size)
    if unreadable==address then return nil end
    return ffi.string(locate(address,size),size)
end
api.pointer=function(bytes,offset)
    if not bytes then return nil end
    local v=ffi.new('uint64_t[1]');ffi.copy(v,bytes:sub((offset or 0)+1),8)
    local n=tonumber(v[0]);if n<0x10000 or n>=0x800000000000 then return nil end
    return n
end
api.writable_data=function(address,size)
    return size==8 and address>=controller+0x4c and address<=controller+0x4c+9*44
        and (address-controller-0x4c)%44==0
end
api.write=function(address,bytes)
    assert(api.writable_data(address,#bytes),'Write escaped local query metadata')
    writes=writes+1
    if writes==changed_before_write then u(control,0x2ac,999);return false end
    if writes==partial_write then ffi.copy(locate(address,8),bytes,2);return false end
    if writes==fail_write then return false end
    ffi.copy(locate(address,8),bytes,8);return true
end
local function read32(address)
    local v=ffi.new('uint32_t[1]');ffi.copy(v,api.read(address,4),4);return tonumber(v[0])
end
local function reset(hits)
    ffi.fill(control,0x2b0);u(control,0x2ac,222);u(control,4,2)
    ffi.fill(queries,0x40070);u(queries,0x40000,10)
    u(queries,0x40004,0);u(queries,0x40008,10);u(queries,0x4000c,1)
    for i=1,7 do u(queries,0x4000c+12*i,1) end
    for slot=0,9 do
        u(control,8+slot*4,slot+1)
        local q=queries+slot*128
        p(q,0,controller+0x30+slot*44);u(q,0x68,0x05a5271a);u(q,0x70,444)
        f(q,16,1);f(q,36,1);f(q,56,1);vector(q,80,.25,.03,.05)
        put(q,0x74,'uint16_t',1);q[0x7a]=2;q[0x7b]=1;q[0x7c]=5
        if hits[slot+1] then
            local h=hits[slot+1];local data=control+0x30+slot*44
            put(q,0x76,'uint16_t',1)
            vector(data,0,h.x or 0,0,h.height or 1)
            vector(data,12,0,0,h.normal or 1)
            u(data,28,444);u(data,32,h.actor or 1)
        end
    end
    avatars[input_offset]=1;move[15]=0;u(mission,0x40,1)
    actor_flags={};actor_speed={};writes=0;exit_calls=0
    fail_write=nil;partial_write=nil;unreadable=nil;changed_before_write=nil
end
local function run(state)
    local ok,reason=patch.apply(api,game,exe,state)
    assert(ok,reason);return reason
end
local remote_before=ffi.string(remote,0x1238)
local passed=0
local function done() assert(ffi.string(remote,0x1238)==remote_before,'Remote controller changed');passed=passed+1 end
for mode=1,7 do
    reset({{actor=2},{}});actor_flags[2]=0x100000;u(mission,0x40,mode)
    local state={};run(state);assert(state.pending,'vault rejected mission mode '..mode);done()
end
for _,mode in ipairs({0,8,0xffffffff})do
    reset({{actor=2},{}});actor_flags[2]=0x100000;u(mission,0x40,mode);run({});assert(writes==0);done()
end
reset({{actor=2},{}});actor_flags[2]=0x100000;u(mission,0x40,2);u(mission,8,0);run({});assert(writes==0);u(mission,8,1)

reset({{},{actor=2}});local state={};run(state);assert(writes==0,'Working first candidate changed');done()
reset({{actor=2},{}});actor_flags[2]=0x100000;state={};run(state)
assert(state.pending and read32(controller+0x4c)==0 and read32(controller+0x4c+44)==444)
assert(state.metadata_fallbacks==nil and actor_flags[2]==0x100000);done()
avatars[input_offset]=0;run(state);assert(read32(controller+0x4c)==444 and state.pending==nil);done()
reset({{actor=2}});actor_flags[2]=0x100000;state={};run(state)
assert(state.metadata_fallbacks==1 and read32(controller+0x50)==0xffffffff)
assert(actor_flags[2]==0x100000);done()
reset({{actor=2}});actor_flags[2]=0x100000;avatars[input_offset]=0;run({});assert(writes==0 and exit_calls==0);done()
reset({{actor=2}});actor_flags[2]=0x200000;run({});assert(writes==0);done()
reset({{actor=2},{}});actor_speed[2]=1.01;run({});assert(read32(controller+0x4c)==0);done()
reset({{actor=2}});actor_speed[2]=1;run({});assert(writes==0);done()
reset({{height=2},{}});run({});assert(read32(controller+0x4c)==0);done()
reset({{height=1.6},{height=1.2}});move[15]=1;run({});assert(read32(controller+0x4c)==0);done()
reset({{x=13},{}});run({});assert(read32(controller+0x4c)==0 and exit_calls==2);done()
reset({{x=13,actor=2}});actor_flags[2]=0x100000;run({});assert(writes==0);done()
reset({{normal=0.5},{}});run({});assert(read32(controller+0x4c)==0);done()
reset({{normal=0.5}});run({});assert(writes==0);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;u(queries,0x4000c,0)
assert(run({})=='waiting_for_query_workers' and writes==0);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;p(queries,0,manager+0x53e1b8+0x30)
assert(run({}):find('waiting_for_game_data',1,true) and writes==0);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;u(control,0x2ac,111)
assert(run({}):find('waiting_for_game_data',1,true) and writes==0);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;unreadable=pm+0xe8;state={}
run(state);assert(writes==0);unreadable=nil;run(state);assert(state.pending);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;u(mission,0x40,0)
assert(run({})=='waiting_for_mission' and writes==0);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;state={};run(state)
u(control,4,3);local old_writes=writes;run(state);assert(writes==old_writes and not state.pending);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;state={};run(state)
u(control,8,20);old_writes=writes;patch.restore(api,state.pending);assert(writes==old_writes);done()
reset({{actor=2},{actor=2},{}});actor_flags[2]=0x100000;fail_write=2;state={}
local ok,reason=patch.apply(api,game,exe,state)
assert(not ok and reason=='query_write_failed' and read32(controller+0x4c)==444 and read32(controller+0x4c+44)==444);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;partial_write=1;state={}
ok,reason=patch.apply(api,game,exe,state)
assert(not ok and reason=='query_write_failed' and read32(controller+0x4c)==444);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;state={}
local original_exit=native.exit
native.exit=function(...)local result=original_exit(...);avatars[input_offset]=0;return result end
run(state);assert(writes==0);native.exit=original_exit;done()
reset({{actor=2},{}});actor_flags[2]=0x100000;state={};run(state)
local before=writes;u(control,0x2ac,999);patch.restore(api,state.pending);assert(writes==before);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;actor_speed[2]=0/0
ok,reason=patch.apply(api,game,exe,{});assert(not ok and writes==0 and reason:find('validation_failed',1,true));done()
reset({{actor=2},{}});actor_flags[2]=0x100000;u(overrides,222%16*8,0xffffffff)
run({});assert(read32(controller+0x4c)==0);u(overrides,222%16*8,222);done()
reset({{actor=2}});actor_flags[2]=0x100000;avatars[input_offset]=3
run({});assert(read32(controller+0x50)==0xffffffff);done()
reset({{actor=2},{}});actor_flags[2]=0x100000;entities[24]=0
run({});assert(writes==0);entities[24]=151;done()

-- Reproduce the observed lifecycle: Lua sees consumed stage 3 and count zero,
-- although this avatar's descriptors/result counts remain in the scheduler.
local world_pointer=region(game+0x276f0c8,8);p(world_pointer,0,0x73000000)
local flags_offset=0x53e880+0x1238
local now,retries,refreshes,refresh_miss,retry_reject=10,0,0,false,false
api.time=function()return now end
native.context_matches=function(bytes)assert(#bytes==0x2b0);return true end
native.refresh_query=function(record,world)
    assert(world==0x73000000)
    refreshes=refreshes+1
    local address=assert(api.pointer(record))
    assert(address>=controller+0x30 and address<=controller+0x30+9*44)
    return api.read(address,44),refresh_miss and 0 or 1
end
native.retry=function(address)
    assert(address==controller and read32(controller+4)==2)
    assert(read32(scheduler+0x40000)==0,'Retry modified scheduler count')
    retries=retries+1
    u(control,4,3)
    if not retry_reject then u(avatars,flags_offset+12,0x40) end
end
api.writable_data=function(address,size)
    return address==controller+4 and size==4
        or size==44 and address>=controller+0x30 and address<=controller+0x30+9*44
            and (address-controller-0x30)%44==0
        or size==8 and address>=controller+0x4c and address<=controller+0x4c+9*44
            and (address-controller-0x4c)%44==0
end
api.write=function(address,bytes)
    assert(api.writable_data(address,#bytes),'Late retry escaped local controller')
    writes=writes+1
    if writes==partial_write then ffi.copy(locate(address,#bytes),bytes,math.min(2,#bytes));return false end
    if writes==fail_write then return false end
    ffi.copy(locate(address,#bytes),bytes,#bytes);return true
end
local function late(hits)
    reset(hits);ffi.fill(avatars+flags_offset,24);u(avatars,flags_offset,2)
    u(control,4,3);u(queries,0x40000,0)
    now=now+1;retries=0;refreshes=0;refresh_miss=false;retry_reject=false
end
late({{actor=2},{}});actor_flags[2]=0x100000;state={}
local hits_before=api.read(controller+0x30,440);local scheduler_before=api.read(scheduler,1280)
assert(run(state)=='native_local_vault_started' and retries==1 and refreshes==2 and state.native_starts==1)
assert(api.read(controller+0x30,440)==hits_before and read32(controller+4)==3 and state.pending==nil)
assert(api.read(scheduler,1280)==scheduler_before and actor_flags[2]==0x100000);done()
late({{actor=2}});actor_flags[2]=0x100000;state={};run(state)
assert(state.metadata_fallbacks==1 and retries==1 and read32(controller+0x50)==2);done()
late({{actor=2}});actor_flags[2]=0x100000;refresh_miss=true;state={};run(state)
assert(refreshes==1 and retries==0 and writes==0 and not state.native_starts);done()
late({{x=13,actor=2}});actor_flags[2]=0x100000;state={};run(state)
assert(retries==0 and writes==0);done()
late({{height=3,actor=2}});actor_flags[2]=0x100000;run({});assert(retries==0 and writes==0);done()
late({{actor=2}});actor_flags[2]=0x100000;u(queries,0x40000,1)
assert(run({})=='waiting_for_idle_query_scheduler' and refreshes==0 and writes==0);done()
late({{actor=2}});actor_flags[2]=0x100000;u(queries,0x4000c,0)
assert(run({})=='waiting_for_query_workers' and refreshes==0 and writes==0);done()
late({{actor=2}});actor_flags[2]=0x100000;avatars[input_offset]=0;run({})
assert(refreshes==0 and writes==0);done()
late({{actor=2}});actor_flags[2]=0x100000;u(avatars,flags_offset+12,0x40);run({})
assert(refreshes==0 and retries==0);done()
late({{actor=2}});actor_flags[2]=0x100000;u(avatars,flags_offset,0);run({})
assert(refreshes==0 and retries==0);done()
late({{actor=2}});actor_flags[2]=0x100000;control[0x214]=1;run({})
assert(refreshes==0 and retries==0);done()
late({{actor=2}});actor_flags[2]=0x100000;f(queries,64,20)
assert(run({})=='retained_query_out_of_reach' and refreshes==0 and writes==0);done()
late({{actor=2}});actor_flags[2]=0x100000
local context_matches=native.context_matches;native.context_matches=function()return false end
assert(run({})=='native_approach_changed_or_blocked' and refreshes==0 and retries==0 and writes==0)
native.context_matches=context_matches;done()
late({{actor=2}});actor_flags[2]=0x100000;retry_reject=true;state={}
assert(run(state)=='native_local_retry_rejected' and retries==1 and not state.native_starts)
assert(run(state)=='waiting_for_retry_interval' and retries==1 and read32(controller+4)==3);done()
late({{actor=2}});actor_flags[2]=0x100000;fail_write=2;state={}
ok,reason=patch.apply(api,game,exe,state)
assert(not ok and reason=='query_write_failed' and read32(controller+0x50)==2 and read32(controller+4)==3 and retries==0);done()
late({{actor=2}});actor_flags[2]=0x100000;partial_write=2;state={}
ok,reason=patch.apply(api,game,exe,state)
assert(not ok and reason=='query_write_failed' and read32(controller+0x50)==2 and read32(controller+4)==3 and retries==0);done()
late({{actor=2}});actor_flags[2]=0x100000
local refresh=native.refresh_query
native.refresh_query=function(...)local b,n=refresh(...);avatars[input_offset]=0;return b,n end
run({});assert(writes==0 and retries==0);native.refresh_query=refresh;done()
late({{actor=2}});actor_flags[2]=0x100000
local retry=native.retry;native.retry=function()error('native fixture failure')end
ok,reason=patch.apply(api,game,exe,{})
assert(not ok and reason:find('native_retry_failed',1,true) and read32(controller+4)==3 and read32(controller+0x50)==2)
native.retry=retry;done()

-- A successful new native approach may differ from the retained geometry.
-- Rebuild its private queries rather than discarding an otherwise valid climb.
late({{actor=2}});actor_flags[2]=0x100000
local fresh_controller=ffi.new('uint8_t[0x2b0]');ffi.copy(fresh_controller,control,0x2b0)
u(fresh_controller,4,1)
vector(fresh_controller,488,0,.4,1.9);vector(fresh_controller,500,0,1,1.9)
f(fresh_controller,512,1.3);f(fresh_controller,516,.5);vector(fresh_controller,520,0,1,0)
local fresh_bytes=ffi.string(fresh_controller,0x2b0)
native.context_matches=function(bytes)
    if bytes==fresh_bytes then return true end
    return false,'native_approach_geometry_changed',fresh_bytes
end
native.query_basis=function(direction)
    assert(direction[2]==1)
    return ffi.string(ffi.new('float[16]',{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}),64)
end
native.refresh_query=function(record,world)
    local position=ffi.new('float[3]');ffi.copy(position,record:sub(65,76),12)
    assert(math.abs(position[1]-.43)<.000001,'Query did not use the new native approach')
    local b,n=refresh(record,world);local out=ffi.new('uint8_t[44]');ffi.copy(out,b,44)
    vector(out,0,0,.43,1)
    return ffi.string(out,44),n
end
state={};local original_queries=api.read(scheduler,1280);local original_controller=api.read(controller,0x2b0)
assert(run(state)=='native_local_vault_started' and retries==1,'Changed native geometry discarded a valid metadata retry')
assert(state.context_reprojections==1 and state.metadata_fallbacks==1
    and state.reprojected_retries==1 and state.reprojected_starts==1)
assert(api.read(scheduler,1280)==original_queries and api.read(controller,0x2b0)==original_controller)
assert(refreshes==1,'Reprojection filled originally empty result slots');done()
local changed_context=native.context_matches
late({{actor=2}});actor_flags[2]=0x100000;refresh_miss=true
run({});assert(refreshes==1 and retries==0 and writes==0);done()
late({{actor=2,normal=.314}});actor_flags[2]=0x100000
run({});assert(refreshes==1 and retries==0 and writes==0);done()
late({{actor=2}});actor_flags[2]=0x100000
local exit_validator=native.exit;native.exit=function()return 5 end
run({});assert(refreshes==1 and retries==0 and writes==0);native.exit=exit_validator;done()
late({{actor=2}});actor_flags[2]=0x100000
native.context_matches=function(bytes)
    if bytes==fresh_bytes then return false,'native_approach_blocked' end
    return changed_context(bytes)
end
assert(run({})=='native_context_changed_before_commit' and refreshes==1 and retries==0 and writes==0);done()
for _,edit in ipairs({
    function(b)u(b,684,111)end, -- another avatar
    function(b)u(b,4,0)end, -- failed native approach
    function(b)f(b,512,0)end,
    function(b)f(b,516,3)end,
    function(b)f(b,524,0/0)end,
    function(b)f(b,528,1)end,
}) do
    late({{actor=2}});actor_flags[2]=0x100000
    local bad=ffi.new('uint8_t[0x2b0]');ffi.copy(bad,fresh_bytes,0x2b0);edit(bad)
    native.context_matches=function()return false,'native_approach_geometry_changed',ffi.string(bad,0x2b0)end
    assert(run({})=='unsupported_fresh_approach' and refreshes==0 and retries==0 and writes==0);done()
end
native.context_matches=changed_context
late({{actor=2}});actor_flags[2]=0x100000
local fresh_query=native.refresh_query
native.refresh_query=function(...)local b,n=fresh_query(...);avatars[input_offset]=0;return b,n end
run({});assert(retries==0 and writes==0);done()
native.refresh_query=refresh
late({{actor=2}});actor_flags[2]=0x100000
local basis=native.query_basis;native.query_basis=function()return string.rep('\0',64)end
assert(run({})=='unsupported_query_basis' and refreshes==0 and retries==0 and writes==0)
native.query_basis=basis;done()
native.context_matches=context_matches;native.refresh_query=refresh;native.query_basis=nil

-- A8A710 leaves the automatic-step report (+533) set when the next lower
-- selector finds no candidate. A88160 does not treat that report as a veto.
late({{actor=2}});actor_flags[2]=0x100000;control[533]=1
state={};local step_controller=api.read(controller,0x2b0)
assert(run(state)=='native_local_vault_started' and retries==1,'Retained automatic-step report blocked manual recovery')
assert(api.read(controller,0x2b0)==step_controller and control[533]==1)
assert(state.step_report_retries==1 and state.step_report_starts==1);done()
late({{actor=2}});actor_flags[2]=0x100000;control[533]=1;refresh_miss=true
run({});assert(refreshes==1 and retries==0 and writes==0 and control[533]==1);done()
late({{actor=2}});actor_flags[2]=0x100000;control[533]=1
native.exit=function()return 5 end
run({});assert(retries==0 and writes==0 and control[533]==1);native.exit=exit_validator;done()
late({{actor=2}});actor_flags[2]=0x100000;control[533]=1;control[532]=1
run({});assert(refreshes==0 and retries==0 and writes==0);done()
late({{actor=2}});actor_flags[2]=0x100000;control[533]=1;u(avatars,flags_offset+12,0x40)
run({});assert(refreshes==0 and retries==0 and writes==0);done()
late({{actor=2}});actor_flags[2]=0x100000;control[533]=1;u(avatars,flags_offset,0)
run({});assert(refreshes==0 and retries==0 and writes==0);done()
late({{actor=2}});actor_flags[2]=0x100000;control[533]=1
native.context_matches=changed_context;native.query_basis=basis
state={};assert(run(state)=='native_local_vault_started' and state.reprojected_starts==1 and state.step_report_starts==1)
assert(control[533]==1);native.context_matches=context_matches;native.query_basis=nil;done()

-- Assistance discovery uses fresh queries, preserving the ordinary path and
-- refusing to change movement merely on manual input or a retained steep hit.
local candidate_owner={entity=owner+0xf31ad8+24}
-- A consumed scheduler slot may be reused while the controller keeps its IDs.
-- This is an expired observation, not a reason to permanently stop the mod.
late({{normal=.5}})
p(queries,0,manager+0x53e1b8+0x30)
local resumed_state={}
local survived,kind,why=pcall(patch.assist_candidate,api,game,exe,resumed_state,candidate_owner)
assert(survived and kind==nil and why=='retained_query_reused','Expired candidate query stopped discovery')
assert(writes==0 and refreshes==0 and retries==0)
p(queries,0,controller+0x30)
assert(patch.assist_candidate(api,game,exe,resumed_state,candidate_owner)=='slope','Discovery did not recover')
assert(resumed_state.candidate_results.retained_query_reused==1 and resumed_state.candidate_results.validated_steep_candidate==1)
done()
late({{normal=.5}});unreadable=pm+0xe8
local unavailable_state={}
local unavailable,unavailable_reason=patch.assist_candidate(api,game,exe,unavailable_state,candidate_owner)
assert(unavailable==nil and unavailable_reason=='candidate_snapshot_unavailable' and unavailable_state.candidate_error)
assert(writes==0 and refreshes==0)
unreadable=nil
assert(patch.assist_candidate(api,game,exe,unavailable_state,candidate_owner)=='slope')
done()
local function candidate(expected)
    local before=api.read(controller,0x2b0)
    local candidate_state={}
    local kind=patch.assist_candidate(api,game,exe,candidate_state,candidate_owner)
    assert(kind==expected,tostring(kind)..' ~= '..tostring(expected))
    assert(writes==0 and retries==0 and api.read(controller,0x2b0)==before,'Candidate probe mutated game data')
    done()
    return candidate_state
end
late({{normal=.9}});candidate(nil)
late({{normal=.5}});candidate('slope')
late({{normal=.314}});candidate(nil)
late({{normal=.5}});refresh_miss=true;candidate(nil)
late({{normal=.5}});actor_speed[1]=2;candidate(nil)
late({{normal=.5}});local saved_exit=native.exit;native.exit=function()return 5 end;candidate(nil);native.exit=saved_exit
late({{normal=.5}});native.context_matches=function()return false end
candidate(nil);assert(refreshes==10);native.context_matches=context_matches
late({{normal=.5}});candidate_owner.entity=candidate_owner.entity+24;candidate(nil);candidate_owner.entity=candidate_owner.entity-24
late({{normal=.314}})
local top_height,top_normal,raised_calls=2.2,.7852,0
native.refresh_query=function(record,world)
    local z=ffi.new('float[1]');ffi.copy(z,record:sub(73,76),4)
    if tonumber(z[0])<.29 then return refresh(record,world) end
    raised_calls=raised_calls+1
    assert(math.abs(tonumber(z[0])-2.84)<.000001,'Probe did not cover the mover-relative height plus box clearance')
    local original=api.read(scheduler+(assert(api.pointer(record))-controller-0x30)/44*128,128)
    assert(record:sub(1,72)==original:sub(1,72) and record:sub(77)==original:sub(77),'Raised cast changed other fields')
    local out=ffi.new('uint8_t[44]');ffi.copy(out,api.read(assert(api.pointer(record)),44),44)
    vector(out,0,0,0,top_height);vector(out,12,0,0,top_normal);u(out,28,555);u(out,32,1)
    return ffi.string(out,44),1
end
candidate('ledge');assert(raised_calls==10)
late({{normal=.314}});top_height=2.5;candidate('ledge')
late({{normal=.314}});top_height=.1
assert(candidate(nil).raised_trace.passes.raised[1].result=='below_ledge_minimum')
late({{normal=.314}});top_height=2.51
local height_trace=candidate(nil).candidate_trace
assert(height_trace.result=='no_usable_assisted_candidate' and #height_trace.passes.raised==10)
assert(height_trace.passes.raised[1].result=='height' and height_trace.passes.raised[1].height>2.5)
assert(math.abs(height_trace.passes.raised[1].source_height-2.84)<.000001)
late({{normal=.314}});top_height=2.2;top_normal=.45
assert(candidate(nil).candidate_trace.passes.raised[1].result=='surface_angle')
late({{normal=.314}});top_normal=.7852;native.exit=function()return 5 end
local exit_trace=candidate(nil).candidate_trace.passes.raised[1]
assert(exit_trace.result=='native_exit' and exit_trace.exit==5);native.exit=saved_exit
late({{normal=.314}});move[15]=1;raised_calls=0;candidate(nil);assert(raised_calls==0)
late({});candidate('ledge') -- A previously empty slot can reveal a top higher up.
late({{normal=.314}});local probe=native.refresh_query
native.refresh_query=function(...)local b,n=probe(...);avatars[input_offset]=0;return b,n end
candidate(nil)
native.refresh_query=refresh

-- The live search ceiling was about 1.93 above the native mover. A fixed
-- +0.41 lift still contacts the face below the nearby 2.45-2.50 top.
-- Model that initial-overlap refusal: the full query box must start clear.
late({{normal=.314}})
for slot=0,9 do f(queries+slot*128,72,1.928206) end
native.refresh_query=function(record,world)
    local z=ffi.new('float[1]');ffi.copy(z,record:sub(73,76),4)
    if tonumber(z[0])<2.75 then return refresh(record,world) end
    local out=ffi.new('uint8_t[44]')
    vector(out,0,0,0,2.48);vector(out,12,0,0,.7852);u(out,28,555);u(out,32,1)
    return ffi.string(out,44),1
end
candidate('ledge')
late({{normal=.314}})
for slot=0,9 do f(queries+slot*128,72,.52) end
assert(math.abs(candidate('ledge').raised_trace.passes.raised[1].source_height-2.84)<.000001)
late({{normal=.314}})
local mover_position=native.mover_position
native.mover_position=function()return {0,0,.125} end
local translated=candidate('ledge').raised_trace
assert(translated.root[3]==.125 and math.abs(translated.passes.raised[1].source_height-2.84)<.000001)
assert(math.abs(translated.passes.raised[1].height-2.355)<.000001)
native.mover_position=mover_position
for _,context_reason in ipairs({'native_approach_blocked','native_approach_geometry_changed'}) do
    late({{normal=.314}})
    native.context_matches=function()return false,context_reason end
    local observed=candidate('ledge')
    assert(observed.raised_context_fallbacks==1 and observed.raised_trace.context==context_reason)
    assert(#observed.raised_trace.passes.ordinary==0 and #observed.raised_trace.passes.slope==0)
end
late({{normal=.314}});f(queries,64,20)
candidate(nil);assert(refreshes==0)
late({{normal=.314}});native.exit=function()return 5 end
assert(candidate(nil).raised_trace.passes.raised[1].result=='native_exit');native.exit=saved_exit
late({{normal=.314}});native.context_matches=function()return false,'unsupported_context' end
candidate(nil);assert(refreshes==0)
-- Private discovery's relaxed context never reaches controller consumption.
late({{normal=.9}});native.context_matches=function()return false,'native_approach_blocked' end
f(settings,0x104,2.5)
assert(run({})=='native_approach_blocked' and writes==0 and retries==0 and refreshes==0)
f(settings,0x104,1.95);native.context_matches=context_matches;done()
native.refresh_query=refresh

-- A later ordinary success must not erase the last raised-search rejection.
local diagnostic_state={}
late({{normal=.314}})
assert(patch.assist_candidate(api,game,exe,diagnostic_state,candidate_owner)==nil)
local last_raised=diagnostic_state.raised_trace
assert(last_raised and #last_raised.passes.raised==10)
late({{normal=.9}})
assert(patch.assist_candidate(api,game,exe,diagnostic_state,candidate_owner)==nil)
assert(diagnostic_state.raised_trace==last_raised and diagnostic_state.candidate_trace~=last_raised)
assert(diagnostic_state.candidate_trace.result=='ordinary_candidate_retained');done()

late({{normal=.5}});actor_speed[1]=2
assert(candidate(nil).candidate_trace.passes.slope[1].result=='actor_motion')
late({{normal=.5}});refresh_miss=true
assert(candidate(nil).candidate_trace.passes.slope[1].result=='no_hit')
late({{normal=.5}});state={}
assert(patch.assist_candidate(api,game,exe,state,candidate_owner)=='slope')
local retained_trace=state.candidate_trace
avatars[input_offset]=0
assert(patch.assist_candidate(api,game,exe,state,candidate_owner)==nil and state.candidate_trace==retained_trace)
assert(state.candidate_results.waiting_for_manual_vault==1 and retained_trace.result=='validated_steep_candidate');done()
late({{normal=.5}});actor_speed[1]=0/0
local valid_call=pcall(patch.assist_candidate,api,game,exe,{},candidate_owner)
assert(not valid_call and writes==0,'Invalid native result must still reach loader cleanup');done()

-- Real Windows adapter only writes existing private PAGE_READWRITE data.
local real=assert(loadfile(source..'/windows_api.lua'))()()
local allocation=ffi.new('uint8_t[16]')
assert(real.writable_data(allocation,16) and real.write(allocation,'abcdefgh'))
assert(real.read(allocation,8)=='abcdefgh')
assert(not real.writable_data(real.module(nil),8) and not real.write(real.module(nil),'abcdefgh'))
done()
print('PASS: '..passed..' local query, native-check model, identity, worker, transition, rollback and Windows permission scenarios')
