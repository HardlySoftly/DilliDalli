ArmyMonitor = Class({
    Initialise = function(self,brain)
        self.brain = brain

        self.bufs = {
            mass = { income=CreateStatBuffer(10), reclaim=CreateStatBuffer(10), earn=CreateStatBuffer(10), spend=CreateStatBuffer(10) },
            energy = { income=CreateStatBuffer(10), reclaim=CreateStatBuffer(10), earn=CreateStatBuffer(10), spend=CreateStatBuffer(10) },
        }
        self.mass = { income=0, reclaim=0, earn=0, spend=0, storage=0, efficiency=1.0 }
        self.energy = { income=0, reclaim=0, earn=0, spend=0, storage=0, efficiency=1.0 }
        self:ResetUnitCounts()
        self.mexes = {}

        self.bufs.mass.income:Init(10)
        self.bufs.mass.reclaim:Init(10)
        self.bufs.mass.earn:Init(10)
        self.bufs.mass.spend:Init(10)
        self.bufs.energy.income:Init(10)
        self.bufs.energy.reclaim:Init(10)
        self.bufs.energy.earn:Init(10)
        self.bufs.energy.spend:Init(10)
    end,

    LogEconomy = function(self)
        LOG(" ===== ArmyMonitor Economy Output ===== ")
        LOG("Mass: { income = "..tostring(self.mass.income:Get())..", spend = "..tostring(self.mass.spend:Get())..", storage = "..tostring(self.mass.storage)..", efficiency = "..tostring(self.mass.efficiency).." }")
        LOG("Energy: { income = "..tostring(self.energy.income:Get())..", spend = "..tostring(self.energy.spend:Get())..", storage = "..tostring(self.energy.storage)..", efficiency = "..tostring(self.energy.efficiency).." }")
    end,

    MonitoringThread = function(self)
        local i = 0
        while self.brain:IsAlive() do
            -- This will fail after roughly 2^53 ticks.  I find this fact to be amusing, and will not be fixing it.
            i = i+1
            local units
            if math.mod(i,2) == 0 then
                if not units then
                    units = self.brain.aiBrain:GetListOfUnits(categories.ALLUNITS - categories.WALL,false,true)
                end
                self:EconomyMonitoring(units)
            end
            if math.mod(i,10) == 0 then
                if not units then
                    units = self.brain.aiBrain:GetListOfUnits(categories.ALLUNITS - categories.WALL,false,true)
                end
                self:UnitMonitoring(units)
            end
            if math.mod(i,2) == 0 then
                self:JobMonitoring(units)
            end
            if math.mod(i,10) == 0 then
                --self:LogEconomy()
            end
            WaitTicks(1)
        end
    end,

    EconomyMonitoring = function(self,units)
        -- TODO: reclaim income monitoring / non-reclaim income monitoring
        local massIncome = 0
        local energyIncome = 0
        local massSpend = 0
        local energySpend = 0
        for _, unit in units do
            if unit:IsBeingBuilt() then
                continue
            end
            -- Update income/spend
            massIncome = massIncome + unit:GetProductionPerSecondMass()
            energyIncome = energyIncome + unit:GetProductionPerSecondEnergy()
            massSpend = massSpend + unit:GetConsumptionPerSecondMass()
            energySpend = energySpend + unit:GetConsumptionPerSecondEnergy()
            -- Mex income stuff
        end
        self.mass.income = self.bufs.mass.income:Add(massIncome)
        self.energy.income = self.bufs.energy.income:Add(energyIncome)
        self.mass.spend = self.bufs.mass.spend:Add(massSpend)
        self.energy.spend = self.bufs.energy.spend:Add(energySpend)
        -- Update storage values
        self.mass.storage = self.brain.aiBrain:GetEconomyStored('MASS')
        self.energy.storage = self.brain.aiBrain:GetEconomyStored('ENERGY')
        -- Update efficiency values
        self.energy.efficiency = 1.0
        if self.energy.storage < 1 and self.energy.income < self.energy.spend then
            self.energy.efficiency = self.energy.income / math.max(self.energy.spend,1)
        end
        self.mass.efficiency = 1.0
        if self.mass.storage < 1 and self.mass.income < self.mass.spend then
            self.mass.efficiency = self.mass.income / math.max(self.mass.spend,1)
        end
        
    end,

    ResetUnitCounts = function(self)
        self.units = {
            engies = { t1=0, t2=0, t3=0 },
            facs = {
                land = { total = { t1=0, t2=0, t3=0 }, idle = { t1=0, t2=0, t3=0 }},
                air = { total = { t1=0, t2=0, t3=0 }, idle = { t1=0, t2=0, t3=0 }},
            },
        }
    end,

    UnitMonitoring = function(self,units)
        self:ResetUnitCounts()
        for _, unit in units do
            local isEngie = EntityCategoryContains(categories.ENGINEER,unit)
            if isEngie then
                if EntityCategoryContains(categories.TECH1,unit) then
                    self.units.engies.t1 = self.units.engies.t1 + 1
                elseif EntityCategoryContains(categories.TECH2,unit) then
                    self.units.engies.t2 = self.units.engies.t2 + 1
                elseif EntityCategoryContains(categories.TECH3,unit) then
                    self.units.engies.t3 = self.units.engies.t3 + 1
                end
            end
            
            local isLandFac = EntityCategoryContains(categories.FACTORY*categories.LAND,unit)
            if isLandFac then
                local isIdle = unit:IsIdleState()
                if EntityCategoryContains(categories.TECH1,unit) then
                    self.units.facs.land.total.t1 = self.units.facs.land.total.t1 + 1
                    if isIdle then
                        self.units.facs.land.idle.t1 = self.units.facs.land.idle.t1 + 1
                    end
                elseif EntityCategoryContains(categories.TECH2,unit) then
                    self.units.facs.land.total.t2 = self.units.facs.land.total.t2 + 1
                    if isIdle then
                        self.units.facs.land.idle.t2 = self.units.facs.land.idle.t2 + 1
                    end
                elseif EntityCategoryContains(categories.TECH3,unit) then
                    self.units.facs.land.total.t3 = self.units.facs.land.total.t3 + 1
                    if isIdle then
                        self.units.facs.land.idle.t3 = self.units.facs.land.idle.t3 + 1
                    end
                end
            end
            local isAirFac = EntityCategoryContains(categories.FACTORY*categories.AIR,unit)
            if isAirFac then
                local isIdle = unit:IsIdleState()
                if EntityCategoryContains(categories.TECH1,unit) then
                    self.units.facs.air.total.t1 = self.units.facs.air.total.t1 + 1
                    if isIdle then
                        self.units.facs.air.idle.t1 = self.units.facs.air.idle.t1 + 1
                    end
                elseif EntityCategoryContains(categories.TECH2,unit) then
                    self.units.facs.air.total.t2 = self.units.facs.air.total.t2 + 1
                    if isIdle then
                        self.units.facs.air.idle.t2 = self.units.facs.air.idle.t2 + 1
                    end
                elseif EntityCategoryContains(categories.TECH3,unit) then
                    self.units.facs.air.total.t3 = self.units.facs.air.total.t3 + 1
                    if isIdle then
                        self.units.facs.air.idle.t3 = self.units.facs.air.idle.t3 + 1
                    end
                end
            end
        end
    end,

    JobMonitoring = function(self)
        for _, job in self.brain.base.mobileJobs do
            if not job.meta.spendBuf then
                -- Average over 5 seconds
                job.meta.spendBuf = CreateStatBuffer(25)
            end
            local actualSpend = 0
            for _, v in job.meta.assigned do
                if v.unit and not v.unit.Dead then
                    actualSpend = actualSpend + v.unit:GetConsumptionPerSecondMass()
                end
            end
            job.job.actualSpend = job.meta.spendBuf:Add(actualSpend)
        end
        for _, job in self.brain.base.factoryJobs do
            if not job.meta.spendBuf then
                -- Average over 5 seconds
                job.meta.spendBuf = CreateStatBuffer(25)
            end
            local actualSpend = 0
            for _, v in job.meta.assigned do
                if v.unit and not v.unit.Dead then
                    actualSpend = actualSpend + v.unit:GetConsumptionPerSecondMass()
                end
            end
            job.job.actualSpend = job.meta.spendBuf:Add(actualSpend)
        end
    end,

    Run = function(self)
        self:ForkThread(self.MonitoringThread)
    end,

    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
            self.brain.Trash:Add(thread)
            return thread
        else
            return nil
        end
    end,
})

function CreateArmyMonitor(brain)
    local am = ArmyMonitor()
    am:Initialise(brain)
    return am
end

StatBuffer = Class({
    Init = function(self,size)
        self.size = size
        self.items = {}
        for i=1,self.size do
            table.insert(self.items,0)
        end
        self.avg = 0
        self.index = 1
    end,

    Add = function(self,item)
        -- I assume the skew from accumulated floating point errors is negligible.
        self.avg = self.avg + (item - self.items[self.index])/self.size
        self.items[self.index] = item
        self.index = self.index + 1
        if self.index > self.size then
            self.index = 1
        end
        return self.avg
    end,

    Get = function(self)
        return self.avg
    end,
})

function CreateStatBuffer(size)
    local sb = StatBuffer()
    sb:Init(size)
    return sb
end


