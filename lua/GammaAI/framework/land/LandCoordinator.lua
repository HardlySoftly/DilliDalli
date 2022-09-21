local MAP = import('/mods/DilliDalli/lua/GammaAI/framework/mapping/Mapping.lua').GetMap()

local LandTheatre = import('/mods/DilliDalli/lua/GammaAI/framework/land/LandTheatre.lua').LandTheatre

LandCoordinator = Class({
    Init = function(self, brain)
        self.brain = brain
        self.theatres = {}
        self.numTheatres = 0
        self.hqLevel = 1
        local components = MAP:GetSignificantComponents(50, 1)
        for _, component in components do
            self.numTheatres = self.numTheatres + 1
            local theatre = LandTheatre()
            theatre:Init(self.brain, self, component)
            self.theatres[self.numTheatres] = theatre
        end
    end,

    TechMonitoringThread = function(self)
        -- TODO
    end,

    Run = function(self)
        self.brain:ForkThread(self, self.TechMonitoringThread)
    end,
})