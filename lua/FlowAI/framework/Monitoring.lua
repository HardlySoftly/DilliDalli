local WORK_RATE = 30

local CreateWorkLimiter = import('/mods/DilliDalli/lua/FlowAI/framework/utils/WorkLimits.lua').CreateWorkLimiter

UnitList = Class({
    Init = function(self)
        self.size = 0
        self.units = {}
    end,

    AddUnit = function(self, unit)
        self.size = self.size + 1
        self.units[self.size] = unit
    end,

    FetchUnit = function(self)
        while self.size > 0 do
            local unit = self.units[self.size]
            self.units[self.size] = nil
            self.size = self.size - 1
            if unit and (not unit.Dead) then
                return unit
            end
        end
        return nil
    end,
})

function CreateUnitList()
    local ul = UnitList()
    ul:Init()
    return ul
end

UnitMonitoring = Class({
    Init = function(self,brain)
        self.brain = brain
        self.registrations = {}
        self.units = {}
    end,

    AddUnit = function(self, unit)
        local bpID = unit.UnitId
        if not self.units[bpID] then
            self.units[bpID] = { num = 0, units = {} }
        end
        self.units[bpID].num = self.units[bpID].num + 1
        self.units[bpID].units[self.units[bpID].num] = unit
    end,

    FindingThread = function(self)
        local workLimiter = CreateWorkLimiter(WORK_RATE,"UnitMonitoring:FindingThread")
        while self.brain:IsAlive() and workLimiter:Wait() do
            local allUnits = self.brain.aiBrain:GetListOfUnits(categories.ALLUNITS,false,true)
            workLimiter:Wait()
            for i, unit in allUnits do
                workLimiter:MaybeWait()
                if unit and (not unit.Dead) and (not unit.FlowAI) then
                    self:AddUnit(unit)
                    unit.FlowAI = {}
                    local bpID = unit.UnitId
                    if self.registrations[bpID] then
                        local j = 1
                        while j <= self.registrations[bpID].count do
                            self.registrations[bpID].lists[j]:AddUnit(unit)
                            j = j+1
                        end
                    end
                end
                
            end
        end
        workLimiter:End()
    end,

    MonitoringThread = function(self)
        local workLimiter = CreateWorkLimiter(WORK_RATE,"UnitMonitoring:MonitoringThread")
        while self.brain:IsAlive() and workLimiter:Wait() do
            for bpID, item in self.units do
                local i = 1
                while i <= item.num do
                    if (not item.units[i]) or item.units[i].Dead then
                        item.units[i] = item.units[item.num]
                        item.units[item.num] = nil
                        item.num = item.num - 1
                    else
                        i = i+1
                    end
                    workLimiter:MaybeWait()
                end
            end
        end
        workLimiter:End()
    end,

    RegisterInterest = function(self, blueprintID, unitList)
        if not self.registrations[blueprintID] then
            self.registrations[blueprintID] = { count = 0, lists = {} }
        end
        self.registrations[blueprintID].count = self.registrations[blueprintID].count + 1
        self.registrations[blueprintID].lists[self.registrations[blueprintID].count] = unitList
    end,

    Run = function(self)
        self.brain:ForkThread(self, self.FindingThread)
        self.brain:ForkThread(self, self.MonitoringThread)
    end,
})