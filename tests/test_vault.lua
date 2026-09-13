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
late({{actor=2}});actor_flags[2]=0x100000;control[0x215]=1;run({})
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

-- Real Windows adapter only writes existing private PAGE_READWRITE data.
local real=assert(loadfile(source..'/windows_api.lua'))()()
local allocation=ffi.new('uint8_t[16]')
assert(real.writable_data(allocation,16) and real.write(allocation,'abcdefgh'))
assert(real.read(allocation,8)=='abcdefgh')
assert(not real.writable_data(real.module(nil),8) and not real.write(real.module(nil),'abcdefgh'))
done()
print('PASS: '..passed..' local query, native-check model, identity, worker, transition, rollback and Windows permission scenarios')
