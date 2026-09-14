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
                'fresh_queries','retry_calls','native_starts','context_reprojections','reprojected_retries','reprojected_starts',
                'step_report_retries','step_report_starts',
                'slope_arms','slope_overrides','slope_climbs','slope_landings',
                'candidate_checks','raised_queries','raised_context_fallbacks','ledge_arms','ledge_climbs','ledge_attempt_expiries'}) do
                file:write(key..'='..tostring(state[key] or 0)..'\n')
            end
            file:write('last_phase='..tostring(state.phase or 'startup')..'\n')
            file:write('last_retry_reason='..tostring(state.last_retry_reason or 'none')..'\n')
            file:write('slope_status='..tostring(state.slope_status or 'startup')..'\n')
            file:write('slope_last_release='..tostring(state.slope_last_release or 'none')..'\n')
            file:write('candidate_reason='..tostring(state.candidate_reason or 'none')..'\n')
            file:write('candidate_height='..tostring(state.candidate_height or 'none')..'\n')
            file:write('candidate_normal_z='..tostring(state.candidate_normal_z or 'none')..'\n')
            file:write('last_candidate_snapshot_error='..tostring(state.candidate_error or 'none')..'\n')
            local outcomes={}
            for reason in pairs(state.candidate_results or {}) do outcomes[#outcomes+1]=reason end
            table.sort(outcomes)
            for _,reason in ipairs(outcomes) do
                file:write('candidate_result_'..reason..'='..state.candidate_results[reason]..'\n')
            end
            -- Retain the last fresh search across input release/waiting states.
            -- Its age and mover origin prevent attribution to a new position.
            local trace=state.raised_trace or state.candidate_trace
            if trace then
                file:write('probe_scope='..(state.raised_trace and 'last_raised_search' or 'last_search')..'\n')
                file:write('probe_approach_context='..tostring(trace.context or 'unknown')..'\n')
                file:write(string.format('probe_age_seconds=%.3f\nprobe_result=%s\nprobe_ground=%s\n',
                    math.max(0,now-trace.time),tostring(trace.result),tostring(trace.ground)))
                file:write(string.format('probe_native_mover=%.6f,%.6f,%.6f\n',unpack(trace.root)))
                file:write(string.format('probe_direction=%.6f,%.6f,%.6f\n',unpack(trace.direction)))
                for _,pass in ipairs({'ordinary','slope','raised'}) do
                    for _,row in ipairs(trace.passes[pass]) do
                        file:write(string.format('probe_%s_slot_%d=count:%d unit:%u height:%.6f max:%.6f normal_z:%.6f threshold:%.6f source_height:%.6f target_height:%.6f hit:%.6f,%.6f,%.6f motion:%s exit:%s veto:%s min:%s result:%s\n',
                            pass,row.slot,row.count,row.unit,row.height,row.max_height,row.normal_z,row.normal_threshold,
                            row.source_height,row.target_height,row.position[1],row.position[2],row.position[3],
                            tostring(row.motion_squared),tostring(row.exit),tostring(row.metadata_veto),tostring(row.min_height),tostring(row.result)))
                    end
                end
            end
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
    local function cleanup()
        if patch.stop then return patch.stop(api,game,exe,state) end
        local restored=patch.restore(api,state.pending)
        if restored then state.pending=nil end
        return restored
    end
    local function check(phase)
        if stopped then return end
        state.polls=state.polls+1;state.phase=phase
        local called,accepted,reason,active=pcall(patch.apply,api,game,exe,state)
        if not called then
            local restored=cleanup()
            stopped=true;report(restored and tostring(accepted) or 'local_restore_failed',false,true);return
        end
        if not accepted then
            stopped=true
            if not cleanup() then reason='local_restore_failed' end
        end
        report(tostring(reason),active==true,not accepted)
    end
    -- Poll both boundaries because other shared-loader/HUD wrappers may update
    -- data. The native engine retains ownership of query scheduling/consumption.
    local function after(called,...)
        if not called then
            local restored=cleanup()
            stopped=true
            report(restored and 'stopped_after_update_error' or 'local_restore_failed',false,true)
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
        local restored=cleanup()
        report(restored and 'stopped' or 'local_restore_failed',false,true)
        if previous_shutdown then return previous_shutdown(...) end
    end
    report('waiting_for_mission',false,true)
end
