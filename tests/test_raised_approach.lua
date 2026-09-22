local source=assert(arg[1])
local ffi=require('ffi')
local file=assert(io.open(source..'/windows_api.lua','rb'));local code=file:read('*a');file:close()
local first=assert(code:find('        function native.raised_approach(',1,true))
local last=assert(code:find('        function native.query_basis(',first,true))
local native={}
local shape=ffi.new('float[5]',{0,0,1.8,.3,.5})
local origin={10,20,30};local calls=0;local missing=false
local env={ffi=ffi,native=native,api={read=function(p,n)assert(p==shape and n==20);return ffi.string(p,n)end},
    mover=function(unit,name)assert(unit==444 and name==123);return 456 end,
    dimensions=function(id)assert(id==456);return shape end,
    position=function(id,out)assert(id==456);for i=1,3 do out[i-1]=origin[i] end end,
    aligned=function(n)local b=ffi.new('uint8_t[?]',n);return b,b end,
    approach=function(unused,args,a,b,span,width)
        assert(unused==nil);calls=calls+1
        assert(ffi.cast('uint32_t *',args)[0]==444)
        local p=ffi.cast('float *',args)
        for i=1,3 do assert(p[i]==origin[i])end
        assert(math.abs(p[4]-.3)<.00001 and math.abs(p[5]-1.8)<.00001)
        assert(p[6]==0 and p[7]==1 and p[8]==0)
        assert(p[9]==.5 and p[10]==2.5 and math.abs(p[11]-.6)<.00001)
        if missing then return 0 end
        a[0]=10;a[1]=20.4;a[2]=32.4;b[0]=10;b[1]=21;b[2]=32.4;span[0]=2;width[0]=.3
        return 1
    end}
setmetatable(env,{__index=_G})
setfenv(assert(loadstring(code:sub(first,last-1))),env)()
local original=ffi.new('uint8_t[0x2b0]');ffi.cast('uint32_t *',original+684)[0]=222
local bytes=ffi.string(original,0x2b0)
local fresh=assert(native.raised_approach(bytes,444,123,{0,1,0},.6))
local out=ffi.new('uint8_t[0x2b0]');ffi.copy(out,fresh,#fresh)
assert(ffi.cast('uint32_t *',out+4)[0]==1 and ffi.cast('uint32_t *',out+684)[0]==222)
assert(ffi.cast('float *',out+512)[0]==2 and ffi.cast('float *',out+524)[0]==1)
assert(ffi.string(original,0x2b0)==bytes,'Private approach changed its input')
origin={11,21,31};assert(native.raised_approach(bytes,444,123,{0,1,0},.6))
missing=true;local _,why=native.raised_approach(bytes,444,123,{0,1,0},.6)
assert(why=='raised_approach_no_ledge' and calls==3)
for _,reach in ipairs({0,-1,1.6,0/0})do
    assert(native.raised_approach(bytes,444,123,{0,1,0},reach)==nil)
end
for _,direction in ipairs({{0,0,0},{0,1,.1},{0,0/0,0}})do
    assert(native.raised_approach(bytes,444,123,direction,.6)==nil)
end
shape[3]=.6;assert(native.raised_approach(bytes,444,123,{0,1,0},.6)==nil)
shape[3]=.3;shape[4]=2.5;assert(native.raised_approach(bytes,444,123,{0,1,0},.6)==nil)
assert(calls==3,'Invalid geometry reached native search')
print('PASS: native raised-approach parameter layout, current mover refresh, private outputs, no-ledge and invalid geometry')
