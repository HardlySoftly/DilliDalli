--[[
    In this file, we implement a helper class for doing easy limiting of work volumes, as well as adding in code profiling for free.
]]

local PROFILER = import('/mods/DilliDalli/lua/FlowAI/framework/utils/Profiler.lua').GetProfiler()

WorkLimiter = Class({
    Init = function(self,workRate,profilingKey)
        self.n = workRate
        self.workRate = workRate
        self.profilingKey = profilingKey
        self.start = PROFILER:Now()
    end,
    Wait = function(self)
        self.n = self.workRate
        PROFILER:Add(self.profilingKey,PROFILER:Now()-start)
        WaitTicks(1)
        self.start = PROFILER:Now()
        return true
    end,
    MaybeWait = function(self)
        self.n = self.n - 1
        if n == 0 then
            n = self.workRate
            PROFILER:Add(self.profilingKey,PROFILER:Now()-start)
            WaitTicks(1)
            self.start = PROFILER:Now()
            return true
        else
            return false
        end
    end,
    WaitTicks = function(self,numTicks)
        self.n = self.workRate
        PROFILER:Add(self.profilingKey,PROFILER:Now()-start)
        WaitTicks(numTicks)
        self.start = PROFILER:Now()
        return true
    end,
    End = function(self)
        PROFILER:Add(self.profilingKey,PROFILER:Now()-start)
        self.start = PROFILER:Now()
        return false
    end,
})

function CreateWorkLimiter(workRate)
    wl = WorkLimiter()
    wl:Init(math.max(math.round(workRate),1))
    return wl
end