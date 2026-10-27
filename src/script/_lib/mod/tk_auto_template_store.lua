-- Four reusable templates. Each profile carries fixed-building branches in the
-- string field "port" (written as line 0 of the file, one line per port type)
-- plus six district slots. A string field is used on purpose: the campaign save
-- serialises tables without key names for numeric keys, so an index 0 would
-- scramble the six district slots on reload.
--
-- A city can host two different port families (capital harbour and trade port),
-- so the field is a map: port[superchain] = chosen end point.
TK_AUTO_TEMPLATE_STORE = {path="tk_auto_city_templates_v1.txt"}
local T=TK_AUTO_TEMPLATE_STORE
local names={"agriculture","commerce","industry","other","recommended"}
local known={agriculture=true,commerce=true,industry=true,other=true,recommended=true}

local function port_info(key)
    if type(key)~="string" then return nil end
    for _,entry in ipairs(TK_AUTO_PORT_TARGETS or {}) do
        if entry.key==key then return entry end
    end
    return nil
end
T.port_info=port_info
T.is_port_target=function(key) return port_info(key)~=nil end

-- Returns the superchain -> end point map for a profile (never nil).
function T.port_of(profile)
    if type(profile)=="table" and type(profile.port)=="table" then return profile.port end
    return {}
end

function T.port_for(profile,superchain)
    return T.port_of(profile)[superchain]
end

function T.has_ports(profile)
    return next(T.port_of(profile))~=nil
end

function T.has_targets(profiles)
    for _,name in ipairs(names) do
        for i=1,10 do if (profiles[name] or {})[i] then return true end end
    end
    return false
end

function T.normalize(profiles,allowed)
    local result,removed={},0
    for _,name in ipairs(names) do
        local source=type(profiles)=="table" and profiles[name] or nil
        local target,seen={},{}
        -- The fixed-building branches live in the string field "port". They are
        -- not district slots, so they are validated against the port list; the
        -- map key is always rebuilt from the entry so a stale key cannot lie.
        local ports={}
        local chosen=type(source)=="table" and source.port
        if type(chosen)=="table" then
            for _,key in pairs(chosen) do
                local info=port_info(key)
                if info and not ports[info.superchain] then ports[info.superchain]=key
                else removed=removed+1 end
            end
        elseif chosen~=nil and chosen~=false then
            removed=removed+1
        end
        target.port=ports
        for i=1,10 do
            local key=type(source)=="table" and source[i] or false
            local data=key and TK_AUTO_BUILDINGS[key]
            local usable=data and data.template_slot and (not allowed or allowed(key))
            if usable and not seen[data.superchain or data.chain or key] then
                target[i]=key;seen[data.superchain or data.chain or key]=true
            else
                target[i]=false
                if key then removed=removed+1 end
            end
        end
        result[name]=target
    end
    return result,removed
end

local function token(value)
    return type(value)=="string" and #value>0 and #value<=256 and value:match("^[%w_%.%-]+$")~=nil
end

function T.serialize(profiles,faction)
    if not token(faction) then return nil,K.L("err_faction") end
    local lines={"TK_AUTO_CITY_TEMPLATES\t4","faction\t"..faction}
    for _,name in ipairs(names) do
        -- One line 0 per port family the player configured, in a stable order,
        -- so the file is deterministic and diffable.
        local ordered={}
        for superchain,key in pairs(T.port_of(profiles[name])) do
            ordered[#ordered+1]={superchain,key}
        end
        table.sort(ordered,function(a,b) return a[1]<b[1] end)
        for _,entry in ipairs(ordered) do
            if not token(entry[2]) then return nil,K.L("err_building") end
            lines[#lines+1]=name.."\t0\t"..entry[2]
        end
        for i=1,10 do
            local key=(profiles[name] or {})[i]
            if key and not token(key) then return nil,K.L("err_building") end
            lines[#lines+1]=name.."\t"..i.."\t"..(key or "-")
        end
    end
    return table.concat(lines,"\n").."\n"
end

function T.deserialize(value)
    if type(value)~="string" or #value>65536 then return nil,K.L("err_file_big") end
    local lines={}
    for line in (value.."\n"):gmatch("([^\n]*)\n") do
        line=line:gsub("\r$","")
        if line~="" then lines[#lines+1]=line end
    end
    -- Version 1 was the six-slot file, version 2 added a single fixed-building
    -- line, version 3 allows one line per port family. All three are readable;
    -- the structure below is what is actually validated, so the line count does
    -- not have to be pinned to a magic number.
    local header=lines[1] and lines[1]:match("^TK_AUTO_CITY_TEMPLATES\t([1234])$")
    if not header then return nil,K.L("err_file_format") end
    local faction=lines[2] and lines[2]:match("^faction\t(.+)$")
    if not token(faction) then return nil,K.L("err_file_faction") end
    local result,seen,counts={},{},{}
    for _,name in ipairs(names) do result[name]={port={}};counts[name]={} end
    for i=3,#lines do
        local name,index,key=lines[i]:match("^([^\t]+)\t([0-9]+)\t([^\t]+)$")
        if not known[name] or not key or (key~="-" and not token(key)) then return nil,K.L("err_entry") end
        index=tonumber(index)
        if index>10 then return nil,K.L("err_entry") end
        if index==0 and header=="1" then return nil,K.L("err_entry") end
        counts[name][index]=(counts[name][index] or 0)+1
        local chosen=key~="-" and key or false
        if index==0 then
            local info=chosen and port_info(chosen)
            if not info or result[name].port[info.superchain] then return nil,K.L("err_entry") end
            result[name].port[info.superchain]=chosen
        else
            local id=name..":"..index
            if seen[id] then return nil,K.L("err_duplicate") end
            seen[id]=true
            result[name][index]=chosen
        end
    end
    for _,name in ipairs(names) do
        for i=1,(header=="4" and 10 or 6) do
            if counts[name][i]~=1 and not (name=="recommended" and counts[name][i]==nil) then return nil,K.L("err_file_format") end
        end
        if (counts[name][0] or 0)>2 then return nil,K.L("err_file_format") end
    end
    return result,faction
end

local function read(path)
    if not io or not io.open then return nil end
    local file=io.open(path,"rb")
    if not file then return nil end
    local value=file:read(65537) or "";file:close()
    return value
end

function T.save(profiles,faction)
    local value,err=T.serialize(profiles,faction)
    if not value then return false,err end
    if not io or not io.open then return false,K.L("err_no_write") end
    if not os or not os.remove or not os.rename then return false,K.L("err_no_replace") end
    local pending=T.path..".tmp"
    local file,message=io.open(pending,"wb")
    if not file then return false,tostring(message or K.L("err_create")) end
    local written,write_error=file:write(value)
    local closed,close_error=file:close()
    if not written or not closed then return false,tostring(write_error or close_error or K.L("err_write")) end
    local previous=read(T.path)
    local recovery=previous
    if previous and T.deserialize(previous) then
        local backup,backup_error=io.open(T.path..".bak","wb")
        if not backup then return false,tostring(backup_error or K.L("err_backup")) end
        local ok,why=backup:write(previous)
        local complete,close_why=backup:close()
        if not ok or not complete then return false,tostring(why or close_why or K.L("err_backup_failed")) end
    else
        -- Preserve a valid backup when the primary file is already damaged.
        local backup=read(T.path..".bak")
        if backup and T.deserialize(backup) then recovery=backup end
    end
    -- Windows cannot rename over an existing destination. All paths are fixed.
    if previous then
        local removed,why=os.remove(T.path)
        if not removed then return false,tostring(why or K.L("err_replace")) end
    end
    local moved,why=os.rename(pending,T.path)
    if not moved then
        if recovery then
            local restore=io.open(T.path,"wb")
            local restored=false
            if restore then
                local written_back=restore:write(recovery)
                local closed_back=restore:close()
                restored=written_back and closed_back
            end
            if not restored then return false,K.L("err_replace_kept") end
        end
        return false,tostring(why or K.L("err_save"))
    end
    return true
end

function T.load(allowed)
    local value=read(T.path)
    local profiles,faction=T.deserialize(value)
    if not profiles then
        local backup=read(T.path..".bak")
        if backup then profiles,faction=T.deserialize(backup) end
    end
    if not profiles then return nil,value and faction or K.L("err_none") end
    local result,removed=T.normalize(profiles,allowed)
    return result,removed,faction
end
