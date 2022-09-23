local LandProduction = import('/mods/DilliDalli/lua/GammaAI/framework/land/LandProduction.lua').LandProduction
local LandControl = import('/mods/DilliDalli/lua/GammaAI/framework/land/LandControl.lua').LandControl
local Strategy = import('/mods/DilliDalli/lua/GammaAI/framework/Strategy.lua').Strategy

LandTheatre = Class(Strategy){
    Init = function(self, brain, landCoordinator, component)
        self.brain = brain
        self.coordinator = landCoordinator
        self.component = component

        self.production = LandProduction()
        self.production:Init(self)
        self.control = LandControl()
        self.control:Init(self)
    end,

    Run = function(self)
        self.production:Run()
        self.control:Run()
    end,
}