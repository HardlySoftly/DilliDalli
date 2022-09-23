LandControl = Class({
    Init = function(self, theatre)
        self.theatre = theatre
    end,

    Run = function(self)
        self.theatre.brain:ForkThread(self, self.UnitAssignmentThread)
    end,

    UnitAssignmentThread = function(self)
        
    end,
})