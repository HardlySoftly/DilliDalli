local MassMarkerManager = import('/mods/DilliDalli/lua/FlowAI/framework/economy/MarkerManagement.lua').MassMarkerManager
local PowerAreaManager = import('/mods/DilliDalli/lua/FlowAI/framework/economy/AreaManagement.lua').PowerAreaManager
local MassUpgradeManager = import('/mods/DilliDalli/lua/FlowAI/framework/economy/UpgradeManagement.lua').MassUpgradeManager

EconomyManager = Class({
    Init = function(self, brain)
        self.brain = brain
        self.budget = 0

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
        WARN("EconomyManager:BudgetAllocationThread not implemented!")
        --[[
            TODO
            while alive:
                - allocate / check on required bp spend
                - split allocation between mass / energy managers
        ]]
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