--[[
    The superclass for top level strategies that the AI will employ.  Expected subclasses:
        - EconomyManager => economic investment
        - LandTheatre
        - Air
        - NavyTheatre
]]
Strategy = Class({
    SetBudget = function(self, budget)
        WARN("SetBudget function not implemented!")
    end,
})