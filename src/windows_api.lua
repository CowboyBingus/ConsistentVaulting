return function()
    local ffi = require('ffi')
    assert(ffi.abi('64bit'), 'Windows x64 is required')
    ffi.cdef [[
        void *GetModuleHandleA(const char *name);
        uint32_t GetModuleFileNameW(void *module, uint16_t *path, uint32_t capacity);
        void *GetCurrentProcess(void);
        uint64_t GetTickCount64(void);
        int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
        int WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);
        typedef struct {
            void *base; void *allocation_base; uint32_t allocation_protection;
            uint16_t partition; uint16_t reserved; size_t size;
            uint32_t state; uint32_t protection; uint32_t type;
        } CvMemoryRegion;
        size_t VirtualQuery(const void *address, void *region, size_t size);
        void *CreateFileW(const uint16_t *path, uint32_t access, uint32_t share, void *security,
                          uint32_t disposition, uint32_t flags, void *template_file);
        int ReadFile(void *file, void *buffer, uint32_t size, uint32_t *read, void *overlapped);
        int CloseHandle(void *handle);
        int32_t BCryptOpenAlgorithmProvider(void **algorithm, const uint16_t *name,
                                            const uint16_t *provider, uint32_t flags);
        int32_t BCryptCloseAlgorithmProvider(void *algorithm, uint32_t flags);
        int32_t BCryptCreateHash(void *algorithm, void **hash, void *object, uint32_t object_size,
                                 const void *secret, uint32_t secret_size, uint32_t flags);
        int32_t BCryptHashData(void *hash, const void *data, uint32_t size, uint32_t flags);
        int32_t BCryptFinishHash(void *hash, void *digest, uint32_t size, uint32_t flags);
        int32_t BCryptDestroyHash(void *hash);
    ]]
    local kernel, bcrypt = ffi.load('kernel32'), ffi.load('bcrypt')
    -- LuaJIT retains the first function declaration in the shared VM. Use an
    -- opaque buffer when declaring first so another mod's equivalent struct is
    -- accepted. Cast our own call as well for a typed declaration loaded first.
    local query_region = ffi.cast('size_t (*)(const void *, void *, size_t)', kernel.VirtualQuery)
    local process = kernel.GetCurrentProcess()
    local api = {}
    function api.time() return tonumber(kernel.GetTickCount64()) / 1000 end

    function api.module(name)
        local handle = kernel.GetModuleHandleA(name)
        if handle == nil then return nil end
        return ffi.cast('uint8_t *', handle)
    end

    function api.read(address, size)
        local buffer, count = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
        if kernel.ReadProcessMemory(process, address, buffer, size, count) == 0 or count[0] ~= size then
            return nil
        end
        return ffi.string(buffer, size)
    end

    function api.write(address, bytes)
        if not api.writable_data(address, #bytes) then return false end
        local count = ffi.new('size_t[1]')
        return kernel.WriteProcessMemory(process, address, bytes, #bytes, count) ~= 0 and count[0] == #bytes
    end

    function api.pointer(bytes, offset)
        offset = offset or 0
        if not bytes or offset < 0 or offset + 8 > #bytes then return nil end
        local value = ffi.new('uintptr_t[1]')
        ffi.copy(value, bytes:sub(offset + 1, offset + 8), 8)
        if value[0] < 0x10000 or value[0] >= 0x800000000000 then return nil end
        return ffi.cast('uint8_t *', value[0])
    end

    function api.distance(first, second)
        return tonumber(ffi.cast('intptr_t', first) - ffi.cast('intptr_t', second))
    end

    function api.writable_data(address, size)
        if size <= 0 then return false end
        local cursor = ffi.cast('uint8_t *', address)
        local remaining = size
        local region = ffi.new('CvMemoryRegion[1]')
        while remaining > 0 do
            if query_region(cursor, region, ffi.sizeof(region[0])) ~= ffi.sizeof(region[0]) then return false end
            -- Settings must already be writable private data, never executable or mapped module pages.
            if region[0].state ~= 0x1000 or region[0].type ~= 0x20000 or region[0].protection ~= 4 then return false end
            local available = tonumber(region[0].size) - api.distance(cursor, region[0].base)
            if available <= 0 then return false end
            local count = math.min(available, remaining)
            cursor, remaining = cursor + count, remaining - count
        end
        return true
    end

    function api.module_hash(module)
        local path = ffi.new('uint16_t[32768]')
        local length = kernel.GetModuleFileNameW(module, path, 32768)
        assert(length > 0 and length < 32768, 'Cannot resolve module file')
        local file = kernel.CreateFileW(path, 0x80000000, 7, nil, 3, 0x08000000, nil)
        assert(file ~= ffi.cast('void *', -1), 'Cannot read module file')
        local algorithm, hash = ffi.new('void *[1]'), ffi.new('void *[1]')
        local ok, result = pcall(function()
            local name = ffi.new('uint16_t[7]', {83, 72, 65, 50, 53, 54, 0})
            assert(bcrypt.BCryptOpenAlgorithmProvider(algorithm, name, nil, 0) == 0, 'SHA256 unavailable')
            assert(bcrypt.BCryptCreateHash(algorithm[0], hash, nil, 0, nil, 0, 0) == 0, 'SHA256 creation failed')
            local buffer, count = ffi.new('uint8_t[1048576]'), ffi.new('uint32_t[1]')
            while true do
                assert(kernel.ReadFile(file, buffer, 1048576, count, nil) ~= 0, 'Module file read failed')
                if count[0] == 0 then break end
                assert(bcrypt.BCryptHashData(hash[0], buffer, count[0], 0) == 0, 'SHA256 update failed')
            end
            local digest, hex = ffi.new('uint8_t[32]'), {}
            assert(bcrypt.BCryptFinishHash(hash[0], digest, 32, 0) == 0, 'SHA256 finish failed')
            for i = 0, 31 do hex[#hex + 1] = string.format('%02X', digest[i]) end
            return table.concat(hex)
        end)
        if hash[0] ~= nil then bcrypt.BCryptDestroyHash(hash[0]) end
        if algorithm[0] ~= nil then bcrypt.BCryptCloseAlgorithmProvider(algorithm[0], 0) end
        kernel.CloseHandle(file)
        if not ok then error(result) end
        return result
    end
    local native_cache
    function api.native(game,exe)
        local function pointer_at(address)
            return assert(api.pointer(api.read(address,8)), 'Native binding unavailable')
        end
        local bindings={
            {0x276c070,0x27d1830,{{0x18,0x79c290},{0x38,0x79e320},{0xa8,0x79e490}}},
            {0x276c0b8,0x27d1ad0,{{0,0x7d3280},{0x28,0x7d40b0},{0x68,0x7d4e70}}},
            {0x276c060,0x27d19e0,{{0,0x7a48f0},{0x68,0x7830c0},{0x80,0x7fe0a0}}},
        }
        for _,binding in ipairs(bindings) do
            local table_address=pointer_at(game+binding[1])
            assert(api.distance(table_address,exe)==binding[2], 'Unsupported native table')
            for _,entry in ipairs(binding[3]) do
                assert(api.distance(pointer_at(table_address+entry[1]),exe)==entry[2], 'Unsupported native function')
            end
        end
        assert(api.read(game+0xa8b8a0,12)=='\072\139\196\072\137\088\008\072\137\104\032\086',
            'Native exit validator changed')
        assert(api.read(game+0xa883f0,16)=='\064\085\083\086\087\065\084\065\086\065\087\072\141\108\036\208',
            'Native vault driver changed')
        if native_cache then return native_cache end
        local valid=ffi.cast('uint64_t (*)(uint32_t)',exe+0x79c290)
        local flags=ffi.cast('uint32_t (*)(uint32_t)',exe+0x79e320)
        local motion=ffi.cast('void (*)(uint32_t,float *,float *)',exe+0x79e490)
        local mover=ffi.cast('uint32_t (*)(uint32_t,uint32_t)',exe+0x7d3280)
        local dimensions=ffi.cast('void *(*)(uint32_t)',exe+0x7d4e70)
        local position=ffi.cast('void (*)(uint32_t,float *)',exe+0x7d40b0)
        local basis=ffi.cast('void *(*)(void *,const float *,const float *)',game+0x1490a30)
        local rotation=ffi.cast('void (*)(float *,const void *)',game+0x148c030)
        -- RCX is unused in this build; RDX is the validated avatar entity.
        local classify=ffi.cast('int32_t (*)(void *,const void *,const float *,const float *)',game+0xa8b8a0)
        local world_id=ffi.cast('uint32_t (*)(const void *)',exe+0x7a48f0)
        local query=ffi.cast('uint32_t (*)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,const void *,void *,uint32_t)',exe+0x7fe0a0)
        local drive=ffi.cast('void (*)(void *,float)',game+0xa883f0)
        local detect=ffi.cast('void (*)(void *,float)',game+0xa8a710)
        local override=ffi.cast('void (*)(void *,const void *,const void *)',game+0x832d40)
        local function aligned(size)
            local storage=ffi.new('uint8_t[?]',size+15)
            local address=tonumber(ffi.cast('uintptr_t',storage))
            return storage,storage+(16-address%16)%16
        end
        local native={}
        function native.ensure_override(manager,entity)
            assert(api.read(game+0x832d40,16)=='\072\137\092\036\008\072\137\108\036\016\072\137\116\036\024\087',
                'Native avatar override routine changed')
            -- 510370 reads start/count at +4/+8. An empty modifier leaves all
            -- fields unchanged; 832d40 creates the entity-owned record if absent.
            local empty=ffi.new('uint32_t[3]')
            override(manager,entity,empty)
        end
        local function f32(n) return tonumber(ffi.new('float[1]',n)[0]) end
        function native.actor(id)
            if id==0xffffffff or valid(id)==0 then return {valid=false} end
            local first,second=ffi.new('float[3]'),ffi.new('float[3]')
            local bits=tonumber(flags(id))
            motion(id,first,second)
            if valid(id)==0 then return nil end
            local x,y,z=tonumber(first[0]),tonumber(first[1]),tonumber(first[2])
            return {valid=true,flags=bits,motion_squared=f32(f32(f32(y*y)+f32(x*x))+f32(z*z))}
        end
        function native.mover_position(unit,name)
            local id=mover(unit,name)
            local data=dimensions(id)
            assert(data~=nil and api.read(data,20),'Local mover unavailable')
            local out=ffi.new('float[3]')
            position(id,out)
            return {tonumber(out[0]),tonumber(out[1]),tonumber(out[2])}
        end
        function native.exit(entity,target,direction)
            local matrix_owner,matrix=aligned(64)
            local rotation_owner,quat=aligned(16)
            local forward=ffi.new('float[3]',direction)
            local up=ffi.new('float[3]',{0,0,1})
            local point=ffi.new('float[3]',target)
            basis(matrix,forward,up)
            rotation(ffi.cast('float *',quat),matrix)
            local result=tonumber(classify(nil,entity,point,ffi.cast('float *',quat)))
            -- Keep the backing allocations rooted until all native reads finish.
            assert(matrix_owner~=nil and rotation_owner~=nil)
            return result
        end
        function native.context_matches(controller_bytes)
            assert(#controller_bytes==0x2b0,'Invalid local controller copy')
            local owner,copy=aligned(0x2b0)
            ffi.copy(copy,controller_bytes,0x2b0)
            ffi.cast('uint32_t *',copy+4)[0]=0
            -- Stage zero only performs the original approach search and writes
            -- its new geometry into this private copy; it cannot start a vault.
            detect(copy,0)
            if ffi.cast('uint32_t *',copy+4)[0]~=1 then return false,'native_approach_blocked' end
            for offset=0x1e8,0x210,4 do
                local previous=ffi.new('float[1]')
                ffi.copy(previous,controller_bytes:sub(offset+1,offset+4),4)
                local current=tonumber(ffi.cast('float *',copy+offset)[0])
                local delta=math.abs(current-tonumber(previous[0]))
                if delta~=delta or delta>0.02 then
                    local fresh=ffi.string(copy,0x2b0)
                    assert(owner~=nil)
                    return false,'native_approach_geometry_changed',fresh
                end
            end
            assert(owner~=nil)
            return true
        end
        function native.query_basis(direction)
            local owner,matrix=aligned(64)
            local forward=ffi.new('float[3]',direction)
            local up=ffi.new('float[3]',{0,0,1})
            basis(matrix,forward,up)
            local bytes=ffi.string(matrix,64)
            assert(owner~=nil)
            return bytes
        end
        function native.refresh_query(record,world)
            assert(#record==128,'Invalid query descriptor')
            -- Match the existing worker's 56-byte descriptor, using private
            -- copies and output storage. No scheduler records are modified.
            local record_owner,copy=aligned(128)
            local output_owner,out=aligned(48)
            ffi.copy(copy,record,128)
            local descriptor=ffi.new('uint64_t[7]')
            descriptor[2]=ffi.cast('uintptr_t',copy+16)
            descriptor[3]=ffi.cast('uintptr_t',copy+80)
            descriptor[4]=ffi.cast('uintptr_t',copy+92)
            descriptor[5]=ffi.cast('uint64_t *',copy+8)[0]
            local tail=ffi.cast('uint32_t *',descriptor)
            tail[12]=ffi.cast('uint32_t *',copy+112)[0]
            tail[13]=ffi.cast('uint32_t *',copy+108)[0]
            local count=tonumber(query(world_id(world),2,1,5,0x05a5271a,descriptor,out,1))
            local bytes=ffi.string(out,44)
            assert(record_owner~=nil and output_owner~=nil)
            return bytes,math.min(count,1)
        end
        function native.retry(controller)
            -- This is the game's original eligibility/check/start routine.
            -- Zero dt avoids advancing movement timers a second time.
            drive(controller,0)
        end
        native_cache=native
        return native
    end
    return api
end
