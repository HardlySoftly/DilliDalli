Scheduler = Class({
    Init = function(self)
        -- Edit these two flags as you see fit
        self.trainingWheels = true
        self.logging = true

        -- Internal state, be careful when touching.  I highly recommend just using the interface functions.
        self.lastTick = 0
        self.totalCost = 0
        self.totalWait = 0
        self.meanCost = 0
        self.workQueue = {}
        self.workQueueLength = 0
        self.logs = {}
        self.numLogs = 0

        -- Behaviour modification stuff
        self.safetyModifier = 1.1
        self.loggingRate = 50
    end,

    AddStats = function(self, numItems, totalCost)
        self.numLogs = self.numLogs + 1
        self.logs[self.numLogs] = {totalCost, numItems}
    end,

    LogStats = function(self)
        -- Log Queue Length, Remaining Cost, Queue Waits, Min/Mean/Max work in logs, Min/Mean/Max items in logs
        local work = {self.logs[1][1],self.logs[1][1],self.logs[1][1]}
        local items = {self.logs[1][2],self.logs[1][2],self.logs[1][2]}
        for i=2, self.numLogs do
            local w = self.logs[i][1]
            local k = self.logs[i][2]
            work[2] = work[2] + w
            items[2] = items[2] + k
            if w > work[3] then
                work[3] = w
            elseif w < work[1] then
                work[1] = w
            end
            if k > items[3] then
                items[3] = k
            elseif k < items[1] then
                items[1] = k
            end
        end
        _ALERT("Scheduler Stats - Size:", self.workQueueLength, "In the last "..tostring(self.loggingRate).." ticks:",
               "Work (Min/Mean/Max/Total):", tostring(work[1]).."/"..tostring(work[2]/self.numLogs).."/"..tostring(work[3]).."/"..tostring(work[2]),
               "Items (Min/Mean/Max/Total):", tostring(items[1]).."/"..tostring(items[2]/self.numLogs).."/"..tostring(items[3]).."/"..tostring(items[2]))
        self.logs = {}
        self.numLogs = 0
    end,

    RemoveWork = function(self, i)
        local item = self.workQueue[i]
        -- Update own state
        self.workQueue[i] = self.workQueue[self.workQueueLength]
        self.workQueue[self.workQueueLength] = nil
        self.workQueueLength = self.workQueueLength - 1
        self.totalCost = self.totalCost - cost
        self.totalWait = self.totalWait - item[2] + item[1] - 1
    end,

    CheckTick = function(self)
        -- If the tick hasn't changed, then skip.
        if self.lastTick == GetGameTick() then
            return
        end
        -- New tick, firstly update our own state
        self.lastTick = GetGameTick()
        if self.logging and (math.mod(self.lastTick, self.loggingRate) == 0) then
            self:LogStats()
        end
        -- Sort work items, makes choosing stuff to do this tick more efficient later.
        table.sort(self.workQueue, function(a,b) return a[3] < b[3] end)

        -- Determine how much work we need to do to keep up.
        local desiredWork = self.safetyModifier * self.meanCost

        -- Now pick things to run this tick.  The algorithm here is pretty basic, but works as a quick starter.
        local workThisTick = 0
        local itemsThisTick = 0
        -- Step 1: Whatever has to be done this tick specifically
        local i = 1
        while i <= self.workQueueLength do
            if self.workQueue[i][2] == self.lastTick then
                self.workQueue[i][4] = true
                workThisTick = workThisTick + self.workQueue[i][3]
                itemsThisTick = itemsThisTick + 1
            end
            i = i+1
        end
        -- Step 2: Fill up to desired work amount with most expensive items first
        i = 1
        while (i <= self.workQueueLength) do
            local item = self.workQueue[i]
            if (not item[4]) and (self.lastTick >= item[1]) and (item[3] + workThisTick < desiredWork) then
                item[4] = true
                workThisTick = workThisTick + item[3]
                itemsThisTick = itemsThisTick + 1
            end
            i = i+1
        end
        -- Step 3: Clean up items we've completed
        i = 1
        while (i <= self.workQueueLength) do
            if self.workQueue[i][4] then
                local item = self.workQueue[i]
                self.workQueue[i] = self.workQueue[self.workQueueLength]
                self.workQueue[self.workQueueLength] = nil
                self.workQueueLength = self.workQueueLength - 1
                self.totalCost = self.totalCost - item[3]
                self.totalWait = self.totalWait - item[2] + item[1] - 1
                self.meanCost = self.meanCost - item[5]
            else
                i = i+1
            end
        end
        if self.logging then
            self:AddStats(itemsThisTick, workThisTick)
        end
    end,

    AddWork = function(self, earliest, latest, cost)
        -- Add an item of work
        item = {earliest, latest, cost, false, cost/(latest-earliest+1)}
        self.workQueueLength = self.workQueueLength + 1
        self.workQueue[self.workQueueLength] = item
        self.totalCost = self.totalCost + cost
        self.totalWait = self.totalWait + latest - earliest + 1
        self.meanCost = self.meanCost + item[5]
        return item
    end,

    WaitTicks = function(self, minTicksToWait, maxTicksToWait, costOfFunction)
        -- Wait at least minTicksToWait, and at most maxTicksToWait.
        if self.trainingWheels and ((minTicksToWait > maxTicksToWait) or (minTicksToWait <= 0) or (costOfFunction <= 0)) then
            -- Bad things might happen, so handle these cases gracefully (or throw a tantrum, idk).
            WARN("Scheduler.WaitTicks called with bad arguments, waiting 100 ticks and returning in order to punish you.")
            WaitTicks(100)
            return 100
        end
        local ticksWaited = 0
        self:CheckTick()
        local item = self:AddWork(self.lastTick+minTicksToWait, self.lastTick+maxTicksToWait, costOfFunction)
        while not item[4] do
            WaitTicks(1)
            ticksWaited = ticksWaited+1
            self:CheckTick()
        end
        return ticksWaited
    end,
})

_G.MyScheduler = Scheduler()
_G.MyScheduler:Init()

function Test()
    -- Stick this function into sim init to test the scheduler
    ForkThread(
        function()
            coroutine.yield(10)
            -- Spawn 30 random cost things
            for i=1, 30 do
                ForkThread(
                    function()
                        local w0 = Random(1,10)
                        local w1 = Random(1,10)
                        local cost = Random(1,10)
                        while true do
                            _G.MyScheduler:WaitTicks(math.min(w0,w1),math.max(w0,w1),cost)
                        end
                    end
                )
            end
            -- Spawn 10 slightly more expensive, fixed time things
            for i=1, 10 do
                ForkThread(
                    function()
                        local w = Random(5,10)
                        while true do
                            _G.MyScheduler:WaitTicks(w,w,20)
                        end
                    end
                )
            end
            -- Spawn 1 very expensive thing
            ForkThread(
                function()
                    while true do
                        _G.MyScheduler:WaitTicks(1,Random(5,10),200)
                    end
                end
            )
        end
    )
end