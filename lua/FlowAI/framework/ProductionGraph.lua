local SplitString = import('/mods/DilliDalli/lua/FlowAI/framework/utils/SplitString.lua').SplitString

-- These are global, so please don't mutate them from each AI instance.  Please.
local ENGIE_MOD_FLAG = false
local BP_DATA = nil
local PRODUCTION_CHAINS = nil

function BPHasCategory(bp,category)
    if bp and bp.Categories then
        for _, cat in bp.Categories do
            if cat == category then
                return true
            end
        end
    end
    return false
end

function HasAllCategories(unitCategories, checkCategories)
    for k0, v0 in checkCategories do
        local found = false
        for k1, v1 in unitCategories do
            if v0 == v1 then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end
    return true
end

function CanMake(id0,id1)
    bp0 = GetUnitBlueprintByName(id0)
    bp1 = GetUnitBlueprintByName(id1)
    if bp0.Economy.BuildableCategory == nil then
        return false
    end
    local i = 0
    while i < table.getn(bp0.Economy.BuildableCategory) do
        i = i+1
        if HasAllCategories(bp1.Categories,SplitString(bp0.Economy.BuildableCategory[i]," ")) then
            return true
        end
    end
    return false
end

function SetEngieModFlag()
    for k, _ in BP_DATA do
        local bp = GetUnitBlueprintByName(k)
        for _, cat in bp.Categories do
            if cat == "SUPPORTFACTORY" then
                ENGIE_MOD_FLAG = true
                return
            end
        end
    end
end

function LoadBPData()
    if BP_DATA ~= nil then
        return BP_DATA
    end
    local START = GetSystemTimeSecondsOnlyForProfileUse()
    local nodes = {}
    for k, v in __blueprints do
        local bp = GetUnitBlueprintByName(k)
        if (bp ~= nil) and (bp.Economy ~= nil) and (bp.Categories ~= nil) then
            nodes[k] = {
                builds = {}, builtBy = {},
                mass = bp.Economy.BuildCostMass, energy = bp.Economy.BuildCostEnergy, buildTime = bp.Economy.BuildTime, buildRate = bp.Economy.BuildRate
            }
            if bp.Economy.BuildRate == nil then
                nodes[k].buildRate = 0
            end
        end
    end
    for k0, v0 in nodes do
        if nodes[k0].buildRate > 0 then
            for k1, v1 in nodes do
                if CanMake(k0,k1) then
                    table.insert(nodes[k0].builds,k1)
                    table.insert(nodes[k1].builtBy,k0)
                end
            end
        end
    end
    for k, v in nodes do
        if (table.getn(nodes[k].builds) == 0) and (table.getn(nodes[k].builtBy) == 0) then
            nodes[k] = nil
        elseif table.getn(nodes[k].builds) == 0 then
            -- TODO: For some reason, stuff is getting a default build rate of 1, which I don't like because it implies all things can be used as mobile engies.
            -- TODO: This is my attempt to address that, but in the process I mess up mobile engineers like kennel drones or mantis that can't build things, but are legitimately engineers.
            nodes[k].buildRate = 0
        end
    end
    BP_DATA = nodes
    SetEngieModFlag()
    local nn = 0
    local en = 0
    for _, n in nodes do
        nn = nn + 1
        for _, _ in n.builds do
            en = en + 1
        end
    end
    LOG("Production Graph - num nodes: "..tostring(nn).." - num edges: "..tostring(en))
    local END = GetSystemTimeSecondsOnlyForProfileUse()
    LOG(string.format('FlowAI framework: Production Graph initialisation finished, runtime: %.2f seconds.', END - START ))
    return nodes
end

ProductionEdge = Class({
    Init = function(self,builderID,buildingID,builder,building,differentiate)
        -- Builder and Building nodes
        self.builder = builder
        self.building = building
        -- State for jobs this edge is managing directly
        self.jobs = {}
        self.jobN = 0
        self.allocation = 0
        self.spending = 0
        self.spendRatio = 1
        self.assists = {}
        self.assistN = 0
        -- Differentiate the cost
        self.differentiate = differentiate
    end,
})

MobileProductionEdge = Class(ProductionEdge) {
    Init = function(self,builderID,buildingID,builder,building)
        -- A unique edge ID
        self.edgeID = builderID..":M:"..buildingID
        -- Common stuff
        ProductionEdge.Init(self,builderID,buildingID,builder,building)
    end,

    Execute = function(self,unit)
        
    end,
    
    ExecuteMexJob = function(self,unit)
        
    end,
    
    ExecuteHydroJob = function(self,unit)
        
    end,
}

FactoryProductionEdge = Class(ProductionEdge) {
    Init = function(self,builderID,buildingID,builder,building)
        -- A unique edge ID
        self.edgeID = builderID..":F:"..buildingID
        -- Common stuff
        ProductionEdge.Init(self,builderID,buildingID,builder,building,false)
    end,

    Execute = function(self,unit)
    end,
}

UpgradeProductionEdge = Class(ProductionEdge) {
    Init = function(self,builderID,buildingID,builder,building)
        -- A unique edge ID
        self.edgeID = builderID..":U:"..buildingID
        -- Common stuff
        ProductionEdge.Init(self,builderID,buildingID,builder,building,true)
    end,
    
    Execute = function(self,unit)
    end,
}

ProductionNode = Class({
    Init = function(self,bpID)
        self.bpID = bpID
        -- Edges that start at this node
        self.sources = {}
        -- Edges that terminate at this node
        self.sinks = {}
        -- Edges indexed by bpID of destination
        self.edges = {}
        -- Some common stats
        local bp = GetUnitBlueprintByName(bpID)
        self.massCost = bp.Economy.BuildCostMass
        self.energyCost = bp.Economy.BuildCostEnergy
        self.buildpowerCost = bp.Economy.BuildTime
        self.buildpower = bp.Economy.BuildRate
        self.count = 0
        self.contention = 1.0
    end,
    AddSourceEdge = function(self,edge)
        table.insert(self.sources,edge)
        self.edges[edge.building.bpID] = edge
    end,
    AddSinkEdge = function(self,edge)
        table.insert(self.sinks,edge)
    end,
})

ProductionChain = Class({
    Init = function(self,nodes)
        -- TODO: Dependencies
        self.edge = nodes[1].edges[nodes[2].bpID]
        self.nodes = nodes
        self.first = nodes[1]
        self.last = nil
        self.size = 0
        for k, _ in nodes do
            self.last = nodes[k]
            self.size = self.size + 1
        end
        self.investmentRates = { 1/nodes[2].buildpowerCost }
        for k, _ in nodes do
            if k > 2 then
                self.investmentRates[k-1] = nodes[k-1].buildpower/(nodes[k].buildpowerCost*(k-1))
            end
        end
    end,

    GetMassRate = function(self,t)
        local res = 1
        for _, rate in self.investmentRates do
            res = res*rate*t
        end
        return res
    end,

    GetMassEfficiency = function(self,t)
        local costRate = 1
        local cumulativeCost = 0
        for k, rate in self.investmentRates do
            costRate = costRate*rate*t
            -- TODO: handle variable mass costs (hmm, upgrades)
            cumulativeCost = cumulativeCost + costRate*self.nodes[k+1].massCost
        end
        -- TODO: handle variable mass costs (hmm, upgrades)
        return costRate*self.last.massCost/cumulativeCost
    end,
})

ProductionGraph = Class({
    -- Provides a wrapper on the raw data from 'LoadBPData()'
    Init = function(self)
        self.nodes = {}
        self.edges = {}
        self.chains = {}

        local bpData = LoadBPData()

        for k, _ in bpData do
            local node = ProductionNode()
            node:Init(k)
            self.nodes[k] = node
        end

        for k0, _ in bpData do
            for _, k1 in bpData[k0].builtBy do
                local bp0 = GetUnitBlueprintByName(k0)
                local bp1 = GetUnitBlueprintByName(k1)
                -- TODO: Handle factory like things better than using structure -> structure
                if BPHasCategory(bp0,"STRUCTURE") and (not BPHasCategory(bp1,"STRUCTURE")) then
                    local edge = FactoryProductionEdge()
                    edge:Init(k1,k0,self.nodes[k1],self.nodes[k0])
                    self.edges[edge.edgeID] = edge
                    self.nodes[k0]:AddSinkEdge(edge)
                    self.nodes[k1]:AddSourceEdge(edge)
                elseif BPHasCategory(bp0,"MOBILE") then
                    local edge = MobileProductionEdge()
                    edge:Init(k1,k0,self.nodes[k1],self.nodes[k0])
                    self.edges[edge.edgeID] = edge
                    self.nodes[k0]:AddSinkEdge(edge)
                    self.nodes[k1]:AddSourceEdge(edge)
                elseif BPHasCategory(bp0,"STRUCTURE") and BPHasCategory(bp1,"STRUCTURE") then
                    local edge = UpgradeProductionEdge()
                    edge:Init(k1,k0,self.nodes[k1],self.nodes[k0])
                    self.edges[edge.edgeID] = edge
                    self.nodes[k0]:AddSinkEdge(edge)
                    self.nodes[k1]:AddSourceEdge(edge)
                else
                    WARN("UNKNOWN PRODUCTION EDGE TYPE BETWEEN: "..k0.." "..k1)
                end
            end
        end

        -- ~0.8 seconds right now.  May need to think about some pre-loading or something
        self:LoadChains()
    end,

    LoadChains = function(self)
        local numChains = 0
        for bpID, _ in self.nodes do
            self.chains[bpID] = {}
        end
        for bpID, node in self.nodes do
            local nodeChains = self:LoadNodeChains(node)
            for _, ns in nodeChains do
                local chain = ProductionChain()
                chain:Init(ns)
                table.insert(self.chains[chain.last.bpID],chain)
                numChains = numChains + 1
            end
        end
    end,

    CanAdd = function(self,nodes,nodesLen,node)
        local nodeBP = GetUnitBlueprintByName(node.bpID)
        -- No duplicate units
        for k, n in nodes do
            if (k > 1) and (node.bpID == n.bpID) then
                return false
            end
        end
        -- At most one fac -> engie edge and at most one engie -> fac edge
        -- TODO: handle chains including gates better (right now the code unfairly eliminates engie -> fac -> engie -> structure because gates aren't factories and we need to exclude them)
        local feCount = 0
        local efCount = 0
        for k, n in nodes do
            if k > 1 then
                local bp0 = GetUnitBlueprintByName(nodes[k-1].bpID)
                local bp1 = GetUnitBlueprintByName(nodes[k].bpID)
                if BPHasCategory(bp0,"ENGINEER") and BPHasCategory(bp1,"STRUCTURE") then
                    efCount = efCount + 1
                end
                if BPHasCategory(bp0,"STRUCTURE") and BPHasCategory(bp1,"ENGINEER") then
                    efCount = efCount + 1
                end
            else
                local bp0 = GetUnitBlueprintByName(nodes[nodesLen].bpID)
                if BPHasCategory(bp0,"ENGINEER") and BPHasCategory(nodeBP,"STRUCTURE") then
                    efCount = efCount + 1
                end
                if BPHasCategory(bp0,"STRUCTURE") and BPHasCategory(nodeBP,"ENGINEER") then
                    efCount = efCount + 1
                end
            end
        end
        if efCount > 1 or feCount > 1 then
            return false
        end
        -- Terminate on upgrades
        local isUpgradeChain = false
        for k, n in nodes do
            if k > 1 then
                local bp0 = GetUnitBlueprintByName(nodes[k-1].bpID)
                local bp1 = GetUnitBlueprintByName(nodes[k].bpID)
                if BPHasCategory(bp0,"FACTORY") and BPHasCategory(bp1,"FACTORY") then
                    isUpgradeChain = true
                end
            end
        end
        if isUpgradeChain and (not BPHasCategory(nodeBP,"FACTORY")) then
            return false
        end
        return true
    end,

    LoadNodeChains = function(self,node)
        local work = {{nodes = {node}, size = 1}}
        local res = {}
        local n = 0
        local k = 1
        while k > 0 do
            local c = work[k]
            k = k - 1
            if c.size > 1 then
                n = n+1
                res[n] = c.nodes
            end
            for _, edge in c.nodes[c.size].sources do
                if self:CanAdd(c.nodes,c.size,edge.building) then
                    local newWork = { nodes = table.copy(c.nodes), size = c.size + 1 }
                    newWork.nodes[newWork.size] = edge.building
                    k = k + 1
                    work[k] = newWork
                end
            end
        end
        return res
    end,

    
})

function CreateProductionGraph()
    pg = ProductionGraph()
    pg:Init()
    return pg
end