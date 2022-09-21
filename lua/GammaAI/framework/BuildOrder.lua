BuildOrder = Class({
    Init = function(self, brain)
        self.brain = brain
        self:CreateJobs()
    end,
    CreateJobs = function(self)
        WARN("BuilderOrder:CreateJobs not implemented!")
    end,
    BuildOrderThread = function(self)
        WARN("BuilderOrder:BuildOrderThread not implemented!")
    end,
    Run = function(self)
        self.brain:ForkThread(self, self.BuildOrderThread)
    end,
})

function PickBuildOrder(brain)
    -- TODO
    return BuildOrder
end