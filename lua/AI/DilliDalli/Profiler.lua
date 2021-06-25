local CreatePriorityQueue = import('/mods/DilliDalli/lua/AI/DilliDalli/PriorityQueue.lua').CreatePriorityQueue

Profiler = Class({
    Init = function(self)
        self.Trash = TrashBag()
        self.last = 0
        self.times = {}
    end,

    Now = function(self)
        return GetSystemTimeSecondsOnlyForProfileUse()
    end,

    Add = function(self,key,amount)
        if self.times[key] then
            self.times[key] = self.times[key] + amount
        else
            self.times[key] = amount
        end
    end,

    LogOut = function(self)
        local pq = CreatePriorityQueue()
        for k, v in self.times do
            pq:Queue({k = k, priority = -v})
        end
        local s = ""
        if not self.last then
            s = "Top Costs: "
        else
            s = "Top Costs("..tostring(math.round(20*(GetSystemTimeSecondsOnlyForProfileUse()-self.last))).."): "
        end
        local i = 0
        while (i < 5) and (pq:Size() > 0) do
            i = i+1
            local item = pq:Dequeue()
            -- Logs 1/100000 of a second per tick
            s = s..item.k.."-"..tostring(math.round(-item.priority*20000))..", "
        end
        LOG(s)
        self.last = GetSystemTimeSecondsOnlyForProfileUse()
        self.times = {}
    end,

    MonitorThread = function(self)
        while true do
            self:LogOut()
            WaitTicks(50)
        end
    end,

    Run = function(self)
        self:ForkThread(self.MonitorThread)
    end,

    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
            self.Trash:Add(thread)
            return thread
        else
            return nil
        end
    end,
})

ProdProfiler = Class({
    Now = function(self)
        return 0
    end,
    Add = function(self,k,v)
    end,
})

function CreateProfiler()
    local dev = false
    if dev then
        local p = Profiler()
        p:Init()
        p:Run()
        return p
    else
        return ProdProfiler()
    end
end

local profiler = CreateProfiler()

function GetProfiler()
    return profiler
end