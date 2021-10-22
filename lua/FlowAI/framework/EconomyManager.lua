local PG = import('/mods/DilliDalli/lua/FlowAI/framework/ProductionGraph.lua')
local SortTable = import('/mods/DilliDalli/lua/FlowAI/framework/PriorityQueue.lua').SortTable

-- Mass management
-- TODO

-- Energy management
-- TODO

BuildpowerManager = Class({

})

ProductionManager = Class({
    Init = function(self, brain)
        self.brain = brain
        self.priorities = {}
        self.graph = PG.CreateProductionGraph()
    end,

    LoadChains = function(self,weights)
        local chains = {}
        local n = 0
        for bpID, weight in weights do
            for _, chain in self.graph.chains[bpID] do
                n = n + 1
                chains[n] = { chain = chain, massEfficiency = 1, massRate = 1, availability = 0, weight = weight }
            end
        end
        return chains
    end,

    SetPriority = function(self, job)
        -- 'job' formatted { weights = { BP_ID = w, ... }, globalWeight = wg }.  The per-unit weights are considered static.
        _ALERT("JOB ADDED:",repr(job))
        job.chains = self:LoadChains(job.weights)
        -- TODO: job.dependencies = self:LoadDependencies(job.weights)
        table.insert(self.priorities, job)
    end,

    ReweightChains = function(self,job,t)
        for _, chainTable in job.chains do
            chainTable.massEfficiency = chainTable.chain:GetMassEfficiency(t)
            -- Don't think I use this...
            --chainTable.massRate = chainTable.chain:GetMassRate(t)
            local firstNode = chainTable.chain.first
            chainTable.availability = firstNode.count*firstNode.buildpower*firstNode.contention*firstNode.contention
            if chainTable.availability > 0 then
                chainTable.priority = 0 - chainTable.massEfficiency * chainTable.weight
            else
                chainTable.priority = 0
            end
        end
    end,

    AllocateResources = function(self,job,resource)
        local r = resource
        local k = 1
        while r > 0 and job.chains[k] and job.chains[k].priority < 0 do
            -- Allocate some resource to job.chains[k].edge
            -- TODO: handle variable mass costs (hmm, upgrades)
            local allocation = math.min(r,job.chains[k].availability*job.chains[k].chain.edge.building.massCost/job.chains[k].chain.edge.building.buildpowerCost)
            r = r - allocation
            job.chains[k].edge.allocation = job.chains[k].edge.allocation + allocation
            k = k+1
        end
    end,

    ClearAllocations = function(self)
        for _, edge in self.graph do
            edge.allocation = 0
        end
    end,

    Optimise = function(self,t)
        -- Given a set of priorities, optimise production incrementally
        local totalWeight = 0
        for _, job in self.priorities do
            totalWeight = totalWeight + job.globalWeight
        end
        self:ClearAllocations()
        for _, job in self.priorities do
            -- Recalculate chain weights
            self:ReweightChains(job,t)
            -- Sort chains
            SortTable(job.chains)
            -- Allocate resources
            -- TODO: handle resource amount better
            local income = self.brain.aiBrain:GetEconomyIncome("MASS")
            self:AllocateResources(job,income*job.globalWeight/totalWeight)
        end
        local ls = ""
        for k, v in self.graph.edges do
            if v.allocation > 0 then
                ls = ls.."("..k.." - "..tostring(v.allocation)..")"
            end
        end
        _ALERT("ALLOCATIONS:",ls)
    end,

    ProductionThread = function(self)
        while self.brain:IsAlive() do
            self:Optimise(300)
            WaitTicks(10)
        end
    end,

    Run = function(self)
        self:ForkThread(self.ProductionThread)
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


function CreateProductionManager(brain)
    pg = ProductionManager()
    pg:Init(brain)
    return pg
end
