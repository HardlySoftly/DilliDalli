local SplitString = import('/mods/DilliDalli/lua/FlowAI/framework/utils.lua').SplitString

-- These are global, so please don't mutate them from each AI instance.  Please.
local ENGIE_MOD_FLAG = false
local BP_DATA = nil

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
    return nodes
end

MobileProductionEdge = Class({
    Init = function(self,builderID,buildingID)
        self.edgeID = builderID..":M:"..buildingID
    end,
})

FactoryProductionEdge = Class({
    Init = function(self,builderID,buildingID)
        self.edgeID = builderID..":F:"..buildingID
    end,
})

UpgradeProductionEdge = Class({
    Init = function(self,builderID,buildingID)
        self.edgeID = builderID..":U:"..buildingID
    end,
})

ProductionNode = Class({
    Init = function(self,bpID)
        self.bpID = bpID
    end,
})

ProductionGraph = Class({
    Init = function(self)
        self.nodes = {}
        self.edges = {}

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
                if BPHasCategory(bp0,"MOBILE") then
                    local edge = MobileProductionEdge()
                    edge:Init(k0,k1)
                    self.edges[edge.edgeID] = edge
                elseif BPHasCategory(bp0,"STRUCTURE") and BPHasCategory(bp1,"STRUCTURE") then
                    local edge = UpgradeProductionEdge()
                    edge:Init(k0,k1)
                    self.edges[edge.edgeID] = edge
                elseif BPHasCategory(bp0,"STRUCTURE") then
                    local edge = FactoryProductionEdge()
                    edge:Init(k0,k1)
                    self.edges[edge.edgeID] = edge
                else
                    WARN("UNKNOWN PRODUCTION EDGE TYPE BETWEEN: "..k0.." "..k1)
                end
            end
        end
    end,

    
})

ProductionManager = Class({

    Run = function(self)
        WaitSeconds(1)
        self:ForkThread(self.ManageProductionThread)
    end,

    ManageProductionThread = function(self)
        local start = PROFILER:Now()
        while self.brain:IsAlive() do
            --LOG("Production Management Thread")
            self:AllocateResources()
            PROFILER:Add("ManageProductionThread",PROFILER:Now()-start)
            WaitSeconds(1)
            start = PROFILER:Now()
        end
        PROFILER:Add("ManageProductionThread",PROFILER:Now()-start)
    end,

    AllocateResources = function(self)
    end,
})