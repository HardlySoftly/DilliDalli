CommandInterface = Class({
    Init = function(self)
        -- TODO: Some kind of command tracking, because reasons.
        -- The ambition is for all issued commands to come through this module.
    end,

    IssueBuildMobile = function(self, units, position, bpID)
        IssueBuildMobile(units,position,bpID,{})
    end,

    IssueBuildFactory = function(self, units, bpID, count)
        IssueBuildFactory(units,bpID,count)
    end,

    IssueUpgrade = function(self, units, bpID)
        IssueUpgrade(units,bpID)
    end,

    IssueRepair = function(self, units, target)
        IssueRepair(units,target)
    end,

    IssueGuard = function(self, units, target)
        IssueGuard(units,target)
    end,

    IssueReclaim = function(self, units, target)
        IssueReclaim(units,target)
    end,

    IssueStop = function(self, units)
        IssueStop(units)
    end,
})

function CreateCommandInterface()
    local ci = CommandInterface()
    ci:Init()
    return ci
end