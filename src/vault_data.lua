local ffi, bit = require('ffi'), require('bit')
local M = {}
local INVALID = 0xffffffff
local function value(bytes, offset, kind)
    local out = ffi.new(kind .. '[1]')
    ffi.copy(out, bytes:sub(offset + 1), ffi.sizeof(out))
    return tonumber(out[0])
end
local function u32(b,o) return value(b,o,'uint32_t') end
local function u16(b,o) return value(b,o,'uint16_t') end
local function number(b,o) return value(b,o,'float') end
local function finite(n) return n == n and math.abs(n) < 100000 end
local function f32(n) return tonumber(ffi.new('float[1]',n)[0]) end
local function vector(b,o)
    local v = {number(b,o),number(b,o+4),number(b,o+8)}
    assert(finite(v[1]) and finite(v[2]) and finite(v[3]), 'Invalid vector')
    return v
end
local function normalize(v)
    local length = f32(math.sqrt(f32(f32(f32(v[1]^2)+f32(v[2]^2))+f32(v[3]^2))))
    if length < 0.0001 then return nil end
    return {f32(v[1]/length),f32(v[2]/length),f32(v[3]/length)}
end
local function pair(unit,actor)
    return ffi.string(ffi.new('uint32_t[2]',{unit,actor}),8)
end

-- Only guards independent of the eight-byte query fields belong to an epoch.
-- This allows restoration after manual input is released, but not after reuse.
function M.same_epoch(api,s)
    for _,g in ipairs(s.epoch) do
        if api.read(g.address,#g.bytes) ~= g.bytes then return false end
    end
    return true
end

function M.snapshot(api,game,exe,state)
    local s = {epoch={},guards={},hits={}}
    local function read(address,size,epoch)
        local bytes = assert(api.read(address,size),'Game data unavailable')
        assert(#bytes==size,'Short game read')
        local guard={address=address,bytes=bytes}
        s.guards[#s.guards+1]=guard
        if epoch then s.epoch[#s.epoch+1]=guard end
        return bytes
    end
    local function pointer(bytes,offset)
        return assert(api.pointer(bytes,offset),'Game pointer unavailable')
    end
    local function global(rva,epoch) return pointer(read(game+rva,8,epoch)) end
    local function lookup(header,key,limit)
        local capacity,empty,mult=u32(header,8),u32(header,12),u32(header,16)
        assert(capacity<=limit and capacity>0 and bit.band(capacity,capacity-1)==0,'Unsupported map')
        local data=pointer(header)
        for probe=0,math.min(capacity,128)-1 do
            -- Keep the low product exact even for a full uint32 key/multiplier.
            local product=ffi.new('uint64_t',key)*ffi.new('uint64_t',mult)
            local slot=bit.band(tonumber(ffi.cast('uint32_t',product))+probe,capacity-1)
            local row=read(data+slot*8,8)
            if u32(row,0)==key then return u32(row,4) end
            if u32(row,0)==empty then return nil end
        end
        return nil
    end
    local mode=read(global(0x276c3d0),0x44)
    if u32(mode,8)==0 or u32(mode,0x40)~=1 then return nil,'waiting_for_mission' end
    local pm=global(0x276c190,true)
    local counts=read(pm+0x84,8)
    assert(u32(counts,0)<=4 and u32(counts,4)<=4,'Unsupported player count')
    if u32(counts,0)==0 or u32(counts,4)==0 then return nil,'waiting_for_local_player' end
    local player=read(pointer(read(pm+0xe8,8,true)),24,true)
    if bit.band(player:byte(21),1)==0 then return nil,'waiting_for_local_player' end
    local unit_ref=u32(read(pm+0x3a8,4,true),0)
    if unit_ref==0x7fff then return nil,'waiting_for_local_avatar' end
    local owner=global(0x276f0c0,true)
    local ei=lookup(read(owner+0xf21a88,20),unit_ref,1048576)
    if not ei or ei==INVALID then return nil,'waiting_for_local_avatar' end
    assert(ei<262144,'Unsupported entity index')
    local entity_address=owner+0xf31ad8+ei*24
    local entity=read(entity_address,24,true)
    -- Resource 0x4d1c334d294dfa97, kept as bytes to avoid floating-point hashing.
    assert(entity:sub(1,8)=='\151\250\077\041\077\051\028\077','Unsupported avatar resource')
    if bit.band(entity:byte(21),1)==0 then return nil,'waiting_for_local_avatar' end
    local id=u32(entity,8)
    local manager=global(0x276ca30,true)
    local ai=lookup(read(manager+0xf8,20),id,64)
    if not ai or ai==INVALID then return nil,'waiting_for_local_avatar' end
    local n=u32(read(manager+0x6c,4),0)
    assert(n<=8 and ai<n,'Unsupported avatar index')
    assert(read(pointer(read(manager+0x110+ai*8,8,true)),24,true)==entity,'Avatar registry mismatch')
    s.controller=manager+0x53e1b8+ai*0x1238
    assert(u32(read(s.controller+0x2ac,4,true),0)==id,'Controller identity mismatch')
    local epoch=read(s.controller+4,44)
    s.stage=u32(epoch,0)
    if state then
        local key='stage_'..s.stage
        state[key]=(state[key] or 0)+1
    end
    if s.stage~=2 and s.stage~=3 then return nil,'waiting_for_vault_query' end
    -- The late retry temporarily returns stage 3 to stage 2. The query IDs,
    -- entity and records still define the epoch across that native call.
    read(s.controller+8,40,true)
    if s.stage==2 then read(s.controller+4,4,true) end
    s.input_address=manager+0x150+ai*0xa7aec+0x1b68+14*32
    s.manual_bytes=read(s.input_address,1)
    if s.manual_bytes:byte()==0 then return nil,'waiting_for_manual_vault' end
    s.manual=true
    local controller=read(s.controller,0x2b0)
    s.controller_bytes=controller
    s.flags_address=manager+ai*0x1238+0x53e880
    local flags=read(s.flags_address,24)
    if s.stage==3 then
        -- Match A88020/A88160 before re-entering the original local driver.
        local climbing=bit.band(u32(flags,12),0x40)~=0
        local excluded=bit.band(u32(flags,0),0x101000)~=0
            or bit.band(u32(flags,4),0x1000000)~=0
            or bit.band(u32(flags,8),0x84010800)~=0
            or bit.band(u32(flags,12),0x2000a303)~=0
            or bit.band(u32(flags,16),1)~=0
        if climbing or excluded or bit.band(u32(flags,0),2)==0
            or controller:byte(0x215)~=0 or controller:byte(0x216)~=0 then
            return nil,'native_vault_state_retained'
        end
    end
    local scheduler=pointer(read(manager+0x28,8,true))
    local jobs=read(scheduler+0x40000,100,true)
    local total=u32(jobs,0)
    if s.stage==3 then
        -- Lua runs after consumption. Require an idle scheduler before using
        -- its retained descriptors as templates for private synchronous casts.
        if total~=0 then return nil,'waiting_for_idle_query_scheduler' end
        for job=0,7 do
            if u32(jobs,12+job*12)~=1 then return nil,'waiting_for_query_workers' end
        end
        s.world=global(0x276f0c8,true)
    else assert(total>0 and total<=2048,'Unsupported query count') end
    local seen={}
    for slot=0,9 do
        local query=u32(epoch,4+slot*4)
        assert(query>0 and query<=(s.stage==3 and 2048 or total) and not seen[query],'Unsupported query ID')
        seen[query]=true
        local completed=false
        for job=0,7 do
            local start,finish,done=u32(jobs,4+job*12),u32(jobs,8+job*12),u32(jobs,12+job*12)
            if query-1>=start and query-1<finish and done==1 then completed=true end
        end
        if s.stage==2 and not completed then return nil,'waiting_for_query_workers' end
        local record=read(scheduler+(query-1)*128,128,true)
        local hit_address=s.controller+0x30+44*slot
        assert(api.distance(pointer(record),hit_address)==0,'Query output is not local controller data')
        assert(u32(record,0x68)==0x05a5271a and u32(record,0x70)==u32(entity,12), 'Query identity mismatch')
        assert(record:byte(0x7b)==2 and record:byte(0x7c)==1 and record:byte(0x7d)==5,'Unsupported query type')
        assert(u16(record,0x74)==1 and u16(record,0x76)<=1,'Unsupported query capacity')
        if s.stage==3 then
            assert(record:sub(9,16)==string.rep('\0',8) and u32(record,0x6c)==0,
                'Unsupported retained query options')
        end
        local hit=read(hit_address,44)
        s.hits[#s.hits+1]={slot=slot,address=hit_address,bytes=hit,
            count=u16(record,0x76),position=vector(hit,0),normal_z=number(hit,20),
            unit=u32(hit,28),actor=u32(hit,32),record=record}
    end
    local override=lookup(read(manager+0x547c70,20),id,64)
    local settings
    if override and override~=INVALID then
        assert(override<8,'Unsupported settings override')
        settings=read(manager+0x547d24+override*0x354,852)
    else
        local component=pointer(read(owner+0xf11778,8))
        -- This resource's two-slot map is verified at runtime, not assumed index zero.
        local map=read(component,32)
        local index
        for slot=0,1 do
            if map:sub(slot*16+1,slot*16+8)==entity:sub(1,8) then index=u32(map,slot*16+8) end
        end
        assert(index and index<1,'Unsupported AvatarComponent map')
        settings=read(component+32+index*852,852)
    end
    local angle=number(settings,0x98)
    assert(angle>0 and angle<90,'Unsupported surface angle')
    s.normal_threshold=f32(math.cos(f32(angle*f32(math.pi/180))))
    local movement=global(0x276c280)
    local mi=lookup(read(movement+0x48a0,20),id,1048576)
    assert(mi and mi~=INVALID and mi<8192,'Movement record unavailable')
    local move=read(pointer(read(movement+0x48c8,8))+mi*132,132)
    local mover=read(pointer(read(movement+0x48d0,8))+mi*164,164)
    local ground=bit.band(u32(flags,4),0x80000000)==0
        and bit.band(u32(flags,8),0xc0000000)==0 and bit.band(u32(flags,12),4)==0 and move:byte(16)==0
    s.max_height=number(settings,ground and 0x104 or 0x108)
    assert(s.max_height>0 and s.max_height<=3,'Unsupported vault height')
    s.native=assert(api.native(game,exe),'Native validation unavailable')
    s.root=s.native.mover_position(u32(entity,12),u32(mover,76))
    assert(s.root and finite(s.root[1]) and finite(s.root[2]) and finite(s.root[3]),'Mover position unavailable')
    local camera=vector(read(global(0x2770688)+0x1c,12),0)
    camera[3]=0
    local direction=normalize(camera)
    if bit.band(u32(flags,8),0x1000)~=0 then
        -- A59C00 uses this entity's bit 76 to choose its motion direction.
        assert(u32(read(manager+ai*0x1238+0x53e15c,4),0)==id,'Direction state identity mismatch')
        direction=normalize(vector(read(manager+0x150+ai*0xa7aec+171698*4,12),0))
    end
    if not direction then return nil,'waiting_for_direction' end
    s.direction=direction
    s.entity=entity_address
    s.query_bytes=epoch
    return s
end

-- Reuse the native exit validator, then expose just one validated result to the
-- existing selector. Normal metadata is preferred; fallback is manual only.
function M.plan(s)
    if not s or not s.manual then return {} end
    local fallback,chosen
    for _,hit in ipairs(s.hits) do
        if hit.count==1 and hit.unit~=0 and finite(hit.normal_z)
            and hit.normal_z>s.normal_threshold and f32(hit.position[3]-s.root[3])<=s.max_height then
            local actor=s.native.actor(hit.actor)
            assert(actor and type(actor.valid)=='boolean','Actor validation unavailable')
            local speed=actor.motion_squared or 0
            assert(finite(speed) and speed>=0,'Invalid actor motion')
            if not actor.valid or speed<=1 then
                local veto=actor.valid and bit.band(actor.flags,0x100000)~=0
                if not veto or not fallback then
                    local exit=s.native.exit(s.entity,hit.position,s.direction)
                    assert(exit==3 or exit==4 or exit==5,'Unsupported exit result')
                    if exit~=5 then
                        if veto then fallback=hit else chosen=hit;break end
                    end
                end
            end
        end
    end
    local metadata=false
    if not chosen then chosen=fallback;metadata=chosen~=nil end
    if not chosen then return {} end
    local writes={}
    for _,hit in ipairs(s.hits) do
        local original=hit.bytes:sub(29,36)
        local replacement
        if hit==chosen then
            replacement=metadata and pair(hit.unit,INVALID) or original
        elseif hit.slot<chosen.slot and hit.count==1 and hit.unit~=0 then
            replacement=pair(0,hit.actor)
        else replacement=original end
        if replacement~=original then
            writes[#writes+1]={address=hit.address+28,before=original,after=replacement}
        end
    end
    return writes,{slot=chosen.slot,metadata=metadata}
end

function M.restore(api,pending)
    if not pending or not M.same_epoch(api,pending.snapshot) then return true end
    for i=#pending.writes,1,-1 do
        local w=pending.writes[i]
        if api.read(w.address,#w.after)==w.after then
            if not api.write(w.address,w.before) or api.read(w.address,#w.before)~=w.before then return false end
        end
    end
    return true
end

-- Stage 2 is inside native frame processing, which a Lua update can miss
-- entirely. At stage 3, cast the retained local query shapes again into private
-- storage, then let the original driver consume one freshly validated result.
function M.retry_consumed(api,s,state)
    local now=api.time()
    if state.last_retry_at and now-state.last_retry_at<0.1 then
        return true,'waiting_for_retry_interval',false
    end
    state.last_retry_at=now
    if not s.native.context_matches(s.controller_bytes) then
        return true,'native_approach_changed_or_blocked',false
    end
    local originals={}
    for i,hit in ipairs(s.hits) do
        originals[i]=hit.bytes
        if hit.count==1 then
            -- Retained geometry must remain near and in front of this avatar.
            -- A fresh cast prevents old hits from surviving removed obstacles.
            for _,offset in ipairs({64,92}) do
                local v=vector(hit.record,offset)
                local dx,dy=v[1]-s.root[1],v[2]-s.root[2]
                if dx*dx+dy*dy>2.25 or math.abs(v[3]-s.root[3])>5
                    or dx*s.direction[1]+dy*s.direction[2]<-0.15 then
                    return true,'retained_query_out_of_reach',false
                end
            end
            local bytes,count=s.native.refresh_query(hit.record,s.world)
            assert(type(bytes)=='string' and #bytes==44 and (count==0 or count==1),'Invalid refreshed query')
            state.fresh_queries=(state.fresh_queries or 0)+1
            hit.bytes,hit.count=bytes,count
            hit.position,hit.normal_z=vector(bytes,0),number(bytes,20)
            hit.unit,hit.actor=u32(bytes,28),u32(bytes,32)
        end
    end
    local _,selected=M.plan(s)
    if not selected then return true,'native_vault_checks_retained',true end
    local chosen=s.hits[selected.slot+1]
    local dx,dy=chosen.position[1]-s.root[1],chosen.position[2]-s.root[2]
    if dx*dx+dy*dy>2.25 or dx*s.direction[1]+dy*s.direction[2]<-0.15 then
        return true,'retained_query_out_of_reach',false
    end
    local writes={}
    for i,hit in ipairs(s.hits) do
        local before=originals[i]
        if hit==chosen then
            local after=hit.bytes
            if selected.metadata then after=after:sub(1,32)..pair(INVALID,0):sub(1,4)..after:sub(37) end
            if before~=after then writes[#writes+1]={address=hit.address,before=before,after=after} end
        elseif u32(before,28)~=0 then
            writes[#writes+1]={address=hit.address+28,before=before:sub(29,36),after=pair(0,u32(before,32))}
        end
    end
    writes[#writes+1]={address=s.controller+4,before=pair(3,0):sub(1,4),after=pair(2,0):sub(1,4)}
    for _,g in ipairs(s.guards) do
        if api.read(g.address,#g.bytes)~=g.bytes then return true,'query_changed_before_commit',false end
    end
    local pending={snapshot=s,writes={}}
    state.pending=pending
    local function rollback(reason)
        local restored=M.restore(api,pending)
        state.pending=nil
        return false,restored and reason or 'query_restore_failed',false
    end
    for _,w in ipairs(writes) do
        if not M.same_epoch(api,s) or api.read(s.input_address,1)~=s.manual_bytes
            or api.read(w.address,#w.before)~=w.before or not api.writable_data(w.address,#w.after) then
            local restored=M.restore(api,pending);state.pending=nil
            return restored,restored and 'query_changed_before_commit' or 'query_restore_failed',false
        end
        pending.writes[#pending.writes+1]=w
        if not api.write(w.address,w.after) or api.read(w.address,#w.after)~=w.after then
            -- Same bytewise partial-write recovery as the early query path.
            local current=api.read(w.address,#w.before)
            if current and current~=w.before and current~=w.after and M.same_epoch(api,s) then
                local partial=true
                for j=1,#current do
                    if current:byte(j)~=w.before:byte(j) and current:byte(j)~=w.after:byte(j) then partial=false end
                end
                if partial and (not api.write(w.address,w.before) or api.read(w.address,#w.before)~=w.before) then
                    return rollback('query_restore_failed')
                end
            end
            return rollback('query_write_failed')
        end
    end
    if not M.same_epoch(api,s) or api.read(s.input_address,1)~=s.manual_bytes then
        return rollback('query_changed_before_retry')
    end
    state.prepared=(state.prepared or 0)+1
    if selected.metadata then state.metadata_fallbacks=(state.metadata_fallbacks or 0)+1 end
    state.retry_calls=(state.retry_calls or 0)+1
    local called,reason=pcall(s.native.retry,s.controller)
    if not called then return rollback('native_retry_failed: '..tostring(reason)) end
    local started=false
    if M.same_epoch(api,s) then
        local flags=api.read(s.flags_address,24)
        started=flags and bit.band(u32(flags,12),0x40)~=0 or false
    end
    local restored=M.restore(api,pending);state.pending=nil
    if not restored then return false,'query_restore_failed',false end
    if started then state.native_starts=(state.native_starts or 0)+1 end
    return true,started and 'native_local_vault_started' or 'native_local_retry_rejected',started
end

function M.apply(api,game,exe,state)
    if state.pending then
        if not M.restore(api,state.pending) then return false,'query_restore_failed',false end
        state.pending=nil
    end
    local ok,s,reason=pcall(M.snapshot,api,game,exe,state)
    if not ok then return true,'waiting_for_game_data: '..tostring(s),false end
    if not s then return true,reason,false end
    state.observed_queries=(state.observed_queries or 0)+1
    if s.stage==3 then
        local called,accepted,why,active=pcall(M.retry_consumed,api,s,state)
        if not called then
            local restored=M.restore(api,state.pending);state.pending=nil
            return false,restored and 'validation_failed: '..tostring(accepted) or 'query_restore_failed',false
        end
        return accepted,why,active
    end
    local planned,writes,selected=pcall(M.plan,s)
    if not planned then return false,'validation_failed: '..tostring(writes),false end
    if #writes==0 then return true,'native_vault_checks_retained',true end
    for _,g in ipairs(s.guards) do
        if api.read(g.address,#g.bytes)~=g.bytes then return true,'query_changed_before_commit',false end
    end
    local pending={snapshot=s,writes={}}
    for _,w in ipairs(writes) do
        if not M.same_epoch(api,s) or api.read(s.input_address,1)~=s.manual_bytes
            or api.read(w.address,8)~=w.before or not api.writable_data(w.address,8) then
            local restored=M.restore(api,pending)
            return restored,restored and 'query_changed_before_commit' or 'query_restore_failed',false
        end
        -- Include the attempted write in rollback: a failed API may write partially.
        pending.writes[#pending.writes+1]=w
        if not api.write(w.address,w.after) or api.read(w.address,8)~=w.after then
            local current=api.read(w.address,8)
            if current and current~=w.before and current~=w.after and M.same_epoch(api,s) then
                local partial=true
                for j=1,8 do
                    if current:byte(j)~=w.before:byte(j) and current:byte(j)~=w.after:byte(j) then partial=false end
                end
                if partial and (not api.write(w.address,w.before) or api.read(w.address,8)~=w.before) then
                    M.restore(api,pending)
                    return false,'query_restore_failed',false
                end
            end
            local restored=M.restore(api,pending)
            return false,restored and 'query_write_failed' or 'query_restore_failed',false
        end
    end
    if not M.same_epoch(api,s) or api.read(s.input_address,1)~=s.manual_bytes then
        local restored=M.restore(api,pending)
        return restored,restored and 'query_changed_after_commit' or 'query_restore_failed',false
    end
    state.pending=pending
    state.prepared=(state.prepared or 0)+1
    if selected.metadata then state.metadata_fallbacks=(state.metadata_fallbacks or 0)+1 end
    state.last_slot=selected.slot
    return true,selected.metadata and 'local_manual_metadata_fallback_prepared' or 'local_manual_alternative_prepared',true
end
return M
