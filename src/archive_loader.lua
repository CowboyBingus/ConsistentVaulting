return function(create_api,patch,build)
    if rawget(_G,'ConsistentVaulting') then return end
    local state={revision=build.revision,active=false,prepared=0,metadata_fallbacks=0,observed_queries=0,
        updates=0,polls=0,fresh_queries=0,retry_calls=0,native_starts=0}
    rawset(_G,'ConsistentVaulting',state)
    local api,last_report
    local function report(status,active,force)
        local changed=state.status~=status
        state.active=active
        state.status=status
        local now=api and api.time and api.time() or 0
        if not force and last_report and now-last_report<2 then return end
        if not force and not changed and not (api and api.time) then return end
        last_report=now
        print('[ConsistentVaulting] '..build.revision..': '..status)
        pcall(function()
            local directory=os.getenv('LOCALAPPDATA')
            if not directory then return end
            local file=io.open(directory..'/ConsistentVaulting.log','w')
            if not file then return end
            file:write(build.revision..'\n'..status..'\n')
            file:write('observed_queries='..state.observed_queries..'\nprepared='..state.prepared
                ..'\nmetadata_fallbacks='..state.metadata_fallbacks..'\n')
            for _,key in ipairs({'updates','polls','stage_0','stage_1','stage_2','stage_3',
                'fresh_queries','retry_calls','native_starts'}) do
                file:write(key..'='..tostring(state[key] or 0)..'\n')
            end
            file:write('last_phase='..tostring(state.phase or 'startup')..'\n')
            file:close()
        end)
    end
    local ok,adapter,game,exe=pcall(function()
        local loader=rawget(_G,'CowboyBingusModLoader')
        assert(type(loader)=='table' and type(loader.api)=='number' and loader.api>=1
            and type(loader.version)=='number' and loader.version>=5,
            'Bingus Shared Loader loader-v4 or newer / API 1 or newer is required')
        local adapter=create_api()
        local game_base,exe_base=adapter.module('game.dll'),adapter.module(nil)
        assert(game_base and exe_base,'Required modules unavailable')
        assert(adapter.module_hash(game_base)==build.game_sha256,'Unsupported game module')
        assert(adapter.module_hash(exe_base)==build.exe_sha256,'Unsupported executable')
        assert(type(update)=='function','Game update unavailable')
        return adapter,game_base,exe_base
    end)
    if not ok then report(tostring(adapter),false,true);return end
    api=adapter
    local previous,previous_shutdown,stopped=update,shutdown,false
    local function check(phase)
        if stopped then return end
        state.polls=state.polls+1;state.phase=phase
        local called,accepted,reason,active=pcall(patch.apply,api,game,exe,state)
        if not called then
            patch.restore(api,state.pending)
            state.pending=nil;stopped=true;report(tostring(accepted),false,true);return
        end
        if not accepted then stopped=true end
        report(tostring(reason),active==true,not accepted)
    end
    -- Poll both boundaries because other shared-loader/HUD wrappers may update
    -- data. The native engine retains ownership of query scheduling/consumption.
    local function after(called,...)
        if not called then
            local restored=patch.restore(api,state.pending)
            state.pending=nil;stopped=true
            report(restored and 'stopped_after_update_error' or 'query_restore_failed',false,true)
            error((...),0)
        end
        check('after_update');return ...
    end
    update=function(...)
        state.updates=state.updates+1
        check('before_update');return after(pcall(previous,...))
    end
    shutdown=function(...)
        stopped=true
        local restored=patch.restore(api,state.pending)
        state.pending=nil
        report(restored and 'stopped' or 'query_restore_failed',false,true)
        if previous_shutdown then return previous_shutdown(...) end
    end
    report('waiting_for_mission',false,true)
end
