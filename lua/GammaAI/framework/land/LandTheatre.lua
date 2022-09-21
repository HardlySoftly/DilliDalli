local LandTheatre = import('/mods/DilliDalli/lua/GammaAI/framework/land/LandTheatre.lua').LandProduction
local LandTheatre = import('/mods/DilliDalli/lua/GammaAI/framework/land/LandTheatre.lua').LandControl
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
        
    end,
}