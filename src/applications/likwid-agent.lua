#!<PREFIX>/bin/likwid-lua
--[[
 * =======================================================================================
 *
 *      Filename:  likwid-agent.lua
 *
 *      Description:  A monitoring daemon for hardware performance counters.
 *
 *      Version:   <VERSION>
 *      Released:  <DATE>
 *
 *      Author:   Thomas Roehl (tr), thomas.roehl@gmail.com
 *      Project:  likwid
 *
 *      Copyright (C) 2015 RRZE, University Erlangen-Nuremberg
 *
 *      This program is free software: you can redistribute it and/or modify it under
 *      the terms of the GNU General Public License as published by the Free Software
 *      Foundation, either version 3 of the License, or (at your option) any later
 *      version.
 *
 *      This program is distributed in the hope that it will be useful, but WITHOUT ANY
 *      WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
 *      PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 *      You should have received a copy of the GNU General Public License along with
 *      this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * =======================================================================================
]]

package.path = '<PREFIX>/share/lua/?.lua;' .. package.path
local likwid = require("likwid")

dconfig = {}
dconfig["groupStrings"] ={}
dconfig["groupData"] ={}
dconfig["accessmode"] = 1
dconfig["duration"] = 1
dconfig["groupPath"] = "<PREFIX>/share/likwid/mongroups"
dconfig["logPath"] = nil
dconfig["logStyle"] = "log"
dconfig["gmetric"] = false
dconfig["gmetricPath"] = "gmetric"
dconfig["gmetricConfig"] = nil
dconfig["gmetricHasUnit"] = false
dconfig["gmetricHasGroup"] = false
dconfig["rrd"] = false
dconfig["rrdPath"] = "."
dconfig["syslog"] = false
dconfig["syslogPrio"] = "local0.notice"
dconfig["stdout"] = false

rrdconfig = {}


local function read_daemon_config(filename)
    if filename == nil or filename == "" then
        print("Not a valid config filename")
        os.exit(1)
    end
    local f = io.open(filename, "r")
    if f == nil then
        print("Cannot open config file "..filename)
        os.exit(1)
    end
    local t = f:read("*all")
    f:close()

    for i, line in pairs(likwid.stringsplit(t,"\n")) do

        if not line:match("^#") then
            if line:match("^GROUPPATH%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                dconfig["groupPath"] = linelist[1]
            end

            if line:match("^EVENTSET%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                for i=#linelist,0,-1 do
                    if linelist[i] == "" then
                        table.remove(linelist, i)
                    else
                        table.insert(dconfig["groupStrings"], linelist[i])
                    end
                end
            end

            if line:match("^DURATION%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                dconfig["duration"] = tonumber(linelist[1])
            end

            if line:match("^ACCESSMODE%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                dconfig["accessmode"] = tonumber(linelist[1])
            end

            if line:match("^LOGPATH%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                dconfig["logPath"] = linelist[1]
            end

            if line:match("^LOGSTYLE%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                if linelist[1] ~= "log" and linelist[1] ~= "update" then
                    print("LOGSTYLE argument not valid, available are log and update. Fallback to log.")
                else
                    dconfig["logStyle"] = linelist[1]
                end
            end

            if line:match("^GMETRIC%s%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                if linelist[1] == "True" then
                    dconfig["gmetric"] = true
                end
            end

            if line:match("^GMETRICPATH%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                dconfig["gmetricPath"] = linelist[1]
            end

            if line:match("^GMETRICCONFIG%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                dconfig["gmetricConfig"] = linelist[1]
            end

            if line:match("^RRD%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                if linelist[1] == "True" then
                    dconfig["rrd"] = true
                end
            end

            if line:match("^RRDPATH%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                dconfig["rrdPath"] = linelist[1]
            end

            if line:match("^SYSLOG%s%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                if linelist[1] == "True" then
                    dconfig["syslog"] = true
                end
            end

            if line:match("^SYSLOGPRIO%a*") ~= nil then
                local linelist = likwid.stringsplit(line, "%s+", nil, "%s+")
                table.remove(linelist, 1)
                dconfig["syslogPrio"] = linelist[1]
            end
        end
    end
end

local function calc_sum(key, results)
    local sum = 0.0
    local numThreads = likwid.getNumberOfThreads()
    for thread=1, numThreads do
        sum = sum + results[thread][key]
    end
    return sum
end

local function calc_avg(key, results)
    local sum = 0.0
    local numThreads = likwid.getNumberOfThreads()
    for thread=1, numThreads do
        sum = sum + results[thread][key]
    end
    return sum/numThreads
end

local function calc_min(key, results)
    local min = math.huge
    local numThreads = likwid.getNumberOfThreads()
    for thread=1, numThreads do
        if results[thread][key] < min then
            min = results[thread][key]
        end
    end
    return min
end

local function calc_max(key, results)
    local max = 0
    local numThreads = likwid.getNumberOfThreads()
    for thread=1, numThreads do
        if results[thread][key] > max then
            max = results[thread][key]
        end
    end
    return max
end

local function check_logfile()
    local g = os.execute("cd "..dconfig["logPath"], "r")
    if g == false then
        print("Logfile path".. dconfig["logPath"].. " does not exist.")
        return false
    end
    return true
end

local function logfile(groupID, results)
    open_function = "a"
    if dconfig["logStyle"] == "update" then
        open_function = "w"
    end
    filename = "likwid."..tostring(groupID)..".log"
    local s,e = dconfig["groupData"][groupID]["GroupString"]:find(":")
    if not s then
        filename = "likwid."..dconfig["groupData"][groupID]["GroupString"]..".log"
    end
    local f = io.open(dconfig["logPath"].."/"..filename, open_function)
    if f == nil then
        print("Cannot open logfile ".. dconfig["logPath"].."/"..filename)
        return
    end
    local timestamp = results["Timestamp"]
    for k,v in pairs(results) do
        if k ~= "Timestamp" then
            f:write(timestamp..","..k:gsub("%(",""):gsub("%)","").. ","..v.."\n")
        end
    end
    f:close()
end

local function check_logger()
    cmd = "which logger"
    local f = io.popen(cmd)
    if f == nil then
        return false
    end
    f:close()
    return true
end

local function logger(results)
    cmd = "logger -t LIKWID "
    if dconfig["syslogPrio"] ~= nil then
        cm = cmd .."-p "..dconfig["syslogPrio"].." "
    end
    local timestamp = results["Timestamp"]
    for k,v in pairs(results) do
        if k ~= "Timestamp" then
            local resultcmd = cmd .. k:gsub("%(",""):gsub("%)","") .. " " ..v
            local f = io.popen(resultcmd)
            if f == nil then
                print("Cannot use logger, maybe not in $PATH")
                return
            end
            f:close()
        end
    end
    
end

local function check_gmetric()
    if dconfig["gmetricPath"] == nil then
        return false
    end
    local f = io.popen(dconfig["gmetricPath"].." -h","r")
    if f == nil then
        return false
    end
    local msg = f:read("*a")
    if msg:match("units=") then
        dconfig["gmetricHasUnit"] = true
    end
    if msg:match("group=") then
        dconfig["gmetricHasGroup"] = true
    end
    f:close()
    return true
end

local function gmetric(gdata, results)
    execList = {}
    if dconfig["gmetricPath"] == nil then
        return
    end
    table.insert(execList, dconfig["gmetricPath"])
    if dconfig["gmetricConfig"] ~= nil then
        table.insert(execList, "-c")
        table.insert(execList, dconfig["gmetricConfig"])
    end
    if dconfig["gmetricHasGroup"] and gdata["GroupString"] ~= gdata["EventString"] then
        table.insert(execList, "-g")
        table.insert(execList, gdata["GroupString"])
    end
    for k,v in pairs(results) do
        local execStr = table.concat(execList, " ")
        if k ~= "Timestamp" then
            execStr = execStr .. " -t double "

            local name = k
            local unit = nil
            local s,e = k:find("%[")
            if s ~= nil then
                name = k:sub(0,s-2):gsub("^%s*(.-)%s*$", "%1")
                unit = k:sub(s+1,k:len()-1):gsub("^%s*(.-)%s*$", "%1")
            end
            execStr = execStr .. " --name=\"" .. name .."\""
            if dconfig["gmetricHasUnit"] and unit ~= nil then
                execStr = execStr .. " --units=\"" .. unit .."\""
            end
            local value = tonumber(v)
            if v ~= nil and value ~= nil then
                execStr = execStr .. " --value=\"" .. string.format("%f", value) .."\""
            elseif v ~= nil then
                execStr = execStr .. " --value=\"" .. tostring(v) .."\""
            else
                execStr = execStr .. " --value=\"0\""
            end
            os.execute(execStr)
        end
    end
end

local function normalize_rrd_string(str)
    str = str:gsub(" ","_")
    str = str:gsub("%(","")
    str = str:gsub("%)","")
    str = str:gsub("%[","")
    str = str:gsub("%]","")
    str = str:gsub("%/","")
    str = str:sub(1,19)
    return str
end

local function check_rrd()
    local f = io.popen("rrdtool")
    if f == nil then
        return false
    end
    f:close()
    return true
end

local function create_rrd(numGroups, duration, groupData)
    local rrdname = dconfig["rrdPath"].."/".. groupData["GroupString"] .. ".rrd"
    local rrdstring = "rrdtool create "..rrdname.." --step ".. tostring(numGroups*duration)
    if rrdconfig[groupData["GroupString"]] == nil then
        rrdconfig[groupData["GroupString"]] = {}
    end
    for i, metric in pairs(groupdata["Metrics"]) do
        rrdstring = rrdstring .. " DS"..":" .. normalize_rrd_string(metric["description"]) ..":GAUGE:"
        rrdstring = rrdstring ..tostring(numGroups*duration) ..":0:U"
        table.insert(rrdconfig[groupData["GroupString"]], metric["description"])
    end
    rrdstring = rrdstring .." RRA:AVERAGE:0.5:" .. tostring(60/duration)..":10"
    rrdstring = rrdstring .." RRA:MIN:0.5:" .. tostring(60/duration)..":10"
    rrdstring = rrdstring .." RRA:MAX:0.5:" .. tostring(60/duration)..":10"
    --Average, min and max of hours of last day
    rrdstring = rrdstring .." RRA:AVERAGE:0.5:" .. tostring(3600/duration)..":24"
    rrdstring = rrdstring .." RRA:MIN:0.5:" .. tostring(3600/duration)..":24"
    rrdstring = rrdstring .." RRA:MAX:0.5:" .. tostring(3600/duration)..":24"
    --Average, min and max of day of last month
    rrdstring = rrdstring .." RRA:AVERAGE:0.5:" .. tostring(86400/duration)..":31"
    rrdstring = rrdstring .." RRA:MIN:0.5:" .. tostring(86400/duration)..":31"
    rrdstring = rrdstring .." RRA:MAX:0.5:" .. tostring(86400/duration)..":31"
    os.execute(rrdstring)
end

local function rrd(groupData, results)
    local rrdname = dconfig["rrdPath"].."/".. groupData["GroupString"] .. ".rrd"
    local rrdstring = "rrdtool update "..rrdname.." N"
    for i, id in pairs(rrdconfig[groupData["GroupString"]]) do
        rrdstring = rrdstring .. ":" .. tostring(results[id])
    end
    os.execute(rrdstring)
end

-- Read commandline arguments
if #arg ~= 1 then
    print("Usage:")
    print(arg[0] .. " <configFile>")
    os.exit(1)
end

-- Get architectural information for the current system
local cpuinfo = likwid.getCpuInfo()
local cputopo = likwid.getCpuTopology()
local affinity = likwid.getAffinityInfo()
-- Read LIKWID configuration file, mainly to avoid topology lookup
local config = likwid.getConfiguration()
-- Read LIKWID daemon configuration file
read_daemon_config(arg[1])

if #dconfig["groupStrings"] == 0 then
    print("No monitoring groups defined, exiting...")
    os.exit(1)
end
if dconfig["duration"] == 0 then
    print("Invalid value 0 for duration. Sanitizing to 1 second.")
    dconfig["duration"] = 1
end

if dconfig["syslog"] then
    if check_logger() == false then
        print("Cannot find tool logger, disabling syslog output.")
        dconfig["syslog"] = false
    end
end
if dconfig["logPath"] then
    if check_logfile() == false then
        print("Cannot create logfile path "..dconfig["logPath"]..". Deactivating logfile output.")
        dconfig["logPath"] = nil
    end
end
if dconfig["gmetric"] then
    if check_gmetric() == false then
        print("Cannot find gmetric using path "..dconfig["gmetricPath"]..". Deactivating gmetric output.")
        dconfig["gmetric"] = false
    end
end
if dconfig["rrd"] then
    if check_rrd() == false then
        print("Cannot find rrdtool. Deactivating rrd output.")
        dconfig["rrd"] = false
    end
end

-- Activate output to stdout only if no other backend is set
if dconfig["logPath"] == nil and dconfig["rrd"] == false and dconfig["gmetric"] == false and dconfig["syslog"] == false then
    dconfig["stdout"] = true
end

-- Add all cpus to the cpulist
local cpulist = {}
for i=0, cputopo["numHWThreads"]-1 do
    table.insert(cpulist, cputopo["threadPool"][i]["apicId"])
end

-- Select access mode to msr devices, try configuration file first
access_mode = dconfig["accessmode"]
if access_mode < 0 or access_mode > 1 then
    access_mode = 1
end
if likwid.setAccessClientMode(access_mode) ~= 0 then
    os.exit(1)
end

-- Select group directory for monitoring
likwid.groupfolder = dconfig["groupPath"]

-- Evaluate eventSet given on commandline. If it's a group, resolve to events
for k,v in pairs(dconfig["groupStrings"]) do
    local gdata = nil
    gdata = likwid.get_groupdata(v)
    if gdata ~= nil then
        table.insert(dconfig["groupData"], gdata)
    end
end
if #dconfig["groupData"] == 0 then
    print("None of the event strings can be added for current architecture.")
    os.exit(1)
end
power = likwid.getPowerInfo()
-- Initialize likwid perfctr
likwid.init(cputopo["numHWThreads"], cpulist)
for k,v in pairs(dconfig["groupData"]) do
    local groupID = likwid.addEventSet(v["EventString"])
    if dconfig["rrd"] then
        create_rrd(#dconfig["groupData"], dconfig["duration"], v)
    end
end

likwid.catchSignal()
while likwid.getSignalState() == 0 do

    for groupID,gdata in pairs(dconfig["groupData"]) do
        local old_mtime = likwid_getRuntimeOfGroup(groupID)
        local cur_time = os.time()
        likwid.setupCounters(groupID)

        -- Perform the measurement
        likwid.startCounters()
        sleep(dconfig["duration"])
        likwid.stopCounters()

        -- temporal array collecting counter to values for each thread for metric calculation
        threadResults = {}
        local mtime = likwid_getRuntimeOfGroup(groupID)
        local clock = likwid_getCpuClock();

        for event=1, likwid.getNumberOfEvents(groupID) do
            for thread=1, likwid.getNumberOfThreads() do
                if threadResults[thread] == nil then
                    threadResults[thread] = {}
                end
                local time = mtime - old_mtime
                threadResults[thread]["time"] = time
                threadResults[thread]["inverseClock"] = 1.0/clock;
                local result = likwid.getResult(groupID, event, thread)
                if threadResults[thread][gdata["Events"][event]["Counter"]] == nil then
                    threadResults[thread][gdata["Events"][event]["Counter"]] = 0
                end
                
                if gdata["Events"][event]["Counter"]:match("PWR%d") then
                    dname = gdata["Events"][event]["Event"]:match("PWR_(%a+)_ENERGY")
                    if power["domains"][dname]["supportInfo"] then
                        if result ~= 0 and result/time > power["domains"][dname]["maxPower"]*1E-6 then
                            result = power["domains"][dname]["tdp"]*1E-6 * time
                        end
                    end
                end
                threadResults[thread][gdata["Events"][event]["Counter"]] = result
            end
        end


        if gdata["Metrics"] then
            local threadOutput = {}
            for i, metric in pairs(gdata["Metrics"]) do
                for thread=1, likwid.getNumberOfThreads() do
                    if threadOutput[thread] == nil then
                        threadOutput[thread] = {}
                    end
                    local result = likwid.calculate_metric(metric["formula"], threadResults[thread])
                    threadOutput[thread][metric["description"]] = result
                end
            end
            output = {}
            output["Timestamp"] = os.date("%m/%d/%Y_%X",cur_time)
            for i, metric in pairs(gdata["Metrics"]) do
                itemlist = likwid.stringsplit(metric["description"], "%s+", nil, "%s+")
                func = itemlist[1]
                table.remove(itemlist, 1)
                desc = table.concat(itemlist," ")
                if func == "AVG" then
                    output[metric["description"]:gsub(" ","_")] = calc_avg(metric["description"], threadOutput)
                elseif func == "SUM" then
                    output[metric["description"]:gsub(" ","_")] = calc_sum(metric["description"], threadOutput)
                elseif func == "MIN" then
                    output[metric["description"]:gsub(" ","_")] = calc_min(metric["description"], threadOutput)
                elseif func == "MAX" then
                    output[metric["description"]:gsub(" ","_")] = calc_max(metric["description"], threadOutput)
                elseif func == "ONCE" then
                    output[metric["description"]:gsub(" ","_")] = threadOutput[1][metric["description"]]
                else
                    for thread=1, likwid.getNumberOfThreads() do
                        output["T"..cpulist[thread] .. "_" .. metric["description"]] = threadOutput[thread][metric["description"]]
                    end
                end
            end
            if dconfig["logPath"] ~= nil then
                logfile(groupID, output)
            end
            if dconfig["syslog"] then
                logger(output)
            end
            if dconfig["gmetric"] then
                gmetric(gdata, output)
            end
            if dconfig["rrd"] then
                rrd(gdata, output)
            end
            if dconfig["stdout"] then
                for i,o in pairs(output) do
                    print(i,o)
                end
                print(likwid.hline)
            end
        end
    end
end

-- Finalize likwid perfctr
likwid.catchSignal()
likwid.finalize()
likwid.putConfiguration()
likwid.putTopology()
