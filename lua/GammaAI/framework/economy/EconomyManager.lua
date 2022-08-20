local MassMarkerManager = import('/mods/DilliDalli/lua/GammaAI/framework/economy/MarkerManagement.lua').MassMarkerManager
local PowerAreaManager = import('/mods/DilliDalli/lua/GammaAI/framework/economy/AreaManagement.lua').PowerAreaManager
local MassUpgradeManager = import('/mods/DilliDalli/lua/GammaAI/framework/economy/UpgradeManagement.lua').MassUpgradeManager
local CreateWorkLimiter = import('/mods/DilliDalli/lua/GammaAI/framework/utils/WorkLimits.lua').CreateWorkLimiter

EconomyManager = Class({
    Init = function(self, brain)
        self.brain = brain
        self.budget = 0
        self.energyThresholdUtility = 1/10
        self.massThresholdUtility = 1/60

        -- Mex manager
        self.mexes = MassMarkerManager()
        self.mexes:Init(self.brain)
        -- Mex Upgrade managers
        self.t2Mexes = MassUpgradeManager()
        self.t2Mexes:Init(self.brain, "MEX_T1", "MEX_T2")
        self.t3Mexes = MassUpgradeManager()
        self.t3Mexes:Init(self.brain, "MEX_T2", "MEX_T3")
        -- Power managers
        self.t1Pgens = PowerAreaManager()
        self.t1Pgens:Init(self.brain, "POWER_T1")
        self.t2Pgens = PowerAreaManager()
        self.t2Pgens:Init(self.brain, "POWER_T2")
        self.t3Pgens = PowerAreaManager()
        self.t3Pgens:Init(self.brain, "POWER_T3")
    end,

    BudgetAllocationThread = function(self)
        local workLimiter = CreateWorkLimiter(1,"EconomyManager:BudgetAllocationThread")
        -- TODO: Adapt target energy per mass based on something smart
        local targetEnergyPerMass = 10
        local proximityFactor = 0.9
        local adjustmentFactor = 1.02
        local massBudget = 0
        local energyBudget = 0
        while self.brain:IsAlive() and workLimiter:WaitTicks(5) do
            -- TODO: Budget scale based on success of spend
            local massBudgetScalar = 1.0
            local energyBudgetScalar = 1.0
            -- Determine relative mass / energy budget
            massBudget = (self.budget * self.energyThresholdUtility) / (self.energyThresholdUtility + targetEnergyPerMass*self.massThresholdUtility)
            massBudget = massBudget*massBudgetScalar
            energyBudget = self.budget - massBudget
            energyBudget = energyBudget*energyBudgetScalar
            -- Move mass threshold until budget can be spent exactly (cap amount of change to something?)
            local n = 5
            while n > 0 do
                local canSpendAtThreshold = (
                    self.mexes.job:MaxSpendAtUtilityThreshold(self.massThresholdUtility) +
                    self.t2Mexes.job:MaxSpendAtUtilityThreshold(self.massThresholdUtility) +
                    self.t3Mexes.job:MaxSpendAtUtilityThreshold(self.massThresholdUtility)
                )
                if canSpendAtThreshold < massBudget*proximityFactor then
                    self.massThresholdUtility = self.massThresholdUtility/adjustmentFactor
                    n = n-1
                elseif canSpendAtThreshold > massBudget/proximityFactor then
                    self.massThresholdUtility = self.massThresholdUtility*adjustmentFactor
                    n = n-1
                else
                    n = 0
                end
            end
            -- Distribute mass budget based on can spends at threshold
            local remainingMassBudget = massBudget
            local _spend = math.min(self.mexes.job:MaxSpendAtUtilityThreshold(self.massThresholdUtility), remainingMassBudget)
            self.mexes:SetBudget(_spend)
            remainingMassBudget = remainingMassBudget - _spend
            _spend = math.min(self.t2Mexes.job:MaxSpendAtUtilityThreshold(self.massThresholdUtility), remainingMassBudget)
            self.t2Mexes:SetBudget(_spend)
            remainingMassBudget = remainingMassBudget - _spend
            _spend = math.min(self.t3Mexes.job:MaxSpendAtUtilityThreshold(self.massThresholdUtility), remainingMassBudget)
            self.t3Mexes:SetBudget(_spend)
            --Move energy threshold until budget can be spent exactly (cap amount of change to something?)
            n = 5
            while n > 0 do
                local canSpendAtThreshold = (
                    self.t1Pgens.job:MaxSpendAtUtilityThreshold(self.energyThresholdUtility) +
                    self.t2Pgens.job:MaxSpendAtUtilityThreshold(self.energyThresholdUtility) +
                    self.t3Pgens.job:MaxSpendAtUtilityThreshold(self.energyThresholdUtility)
                )
                if canSpendAtThreshold < energyBudget*proximityFactor then
                    self.energyThresholdUtility = self.energyThresholdUtility/adjustmentFactor
                    n = n-1
                elseif canSpendAtThreshold > energyBudget/proximityFactor then
                    self.energyThresholdUtility = self.energyThresholdUtility*adjustmentFactor
                    n = n-1
                else
                    n = 0
                end
            end
            -- Distribute energy budget based on can spends at threshold
            local remainingEnergyBudget = energyBudget
            local _spend = math.min(self.t3Pgens.job:MaxSpendAtUtilityThreshold(self.energyThresholdUtility), remainingEnergyBudget)
            self.t3Pgens:SetBudget(_spend)
            remainingEnergyBudget = remainingEnergyBudget - _spend
            _spend = math.min(self.t2Pgens.job:MaxSpendAtUtilityThreshold(self.energyThresholdUtility), remainingEnergyBudget)
            self.t2Pgens:SetBudget(_spend)
            remainingEnergyBudget = remainingEnergyBudget - _spend
            _spend = math.min(self.t1Pgens.job:MaxSpendAtUtilityThreshold(self.energyThresholdUtility), remainingEnergyBudget)
            self.t1Pgens:SetBudget(_spend)
            -- Update marginal energy utility
            self.mexes:SetMarginalEnergyCost(self.energyThresholdUtility)
            self.t2Mexes:SetMarginalEnergyCost(self.energyThresholdUtility)
            self.t3Mexes:SetMarginalEnergyCost(self.energyThresholdUtility)
        end
        workLimiter:End()
    end,

    Run = function(self)
        self.brain:ForkThread(self, self.BudgetAllocationThread)
        self.mexes:Run()
        self.t2Mexes:Run()
        self.t3Mexes:Run()
        self.t1Pgens:Run()
        self.t2Pgens:Run()
        self.t3Pgens:Run()
    end,

    -- External interface functions
    SetBudget = function(self, budget) self.budget = budget end,
    PredictGrowth = function(self, timePeriodSeconds) WARN("EconomyManager:PredictGrowth not implemented!") end,
})