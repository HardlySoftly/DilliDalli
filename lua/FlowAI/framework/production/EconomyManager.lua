local PRODUCTION_GRAPH = nil
local ADJACENCY_BUFFS = nil
local Job = import('/mods/DilliDalli/lua/FlowAI/framework/production/JobDistribution.lua').Job
local GetMarkers = import("/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua").GetMarkers

local LOOP_WAIT = 10
local TARGET_TOLERANCE = 1.1
local THEORETICAL_DOWNWEIGHT = 2
local PREDICTIONS_PERIOD = 60
local MIN_MASS_INCREASE = 10
local MASS_INCREASE_MULTIPLIER = 1.1
local MIN_MASS_PRIORITY = 1/10000 -- 10000 mass invested increases income by 1 mass/s
local MIN_ENERGY_PRIORITY = 1/100 -- 100 mass invested increases income by 1 energy/s
local STARTING_ENERGY_COST = 100/20

OptionManager = Class({
    --[[
        Interface class for various kinds of economic jobs that need managing.  In particular, we want to provide
        a consistent way for the Economy Manager to handle economic jobs of the following kinds:
            - Engineer jobs with no specific location requirement, e.g. build a mass fab.
            - Factory jobs with no specific location requirement, e.g. build an sACU
            - Marker based jobs (so location specific), e.g. new mexes and hydrocarbons
            - Adjacency based jobs (again, location specific), e.g. make storage around a mex
            - Upgrade jobs (unit specific), e.g. upgrade a mex from t2 to t3
            - Enhancement jobs, e.g. RAS for the ACU or an sACU
        Sub-classes of the OptionManager are intended to handle the implementation specifics of managing each of these cases,
        leaving the EconomyManager able to focus on the resource allocation bits.
    ]]
    Init = function(self)
        --[[
            An 'option' (corresponding to an option for increasing mass/energy income) has the following fields:
                - job - the job associated with this option if it exists
                - template - the template describing the stats for this option; templates have the following fields:
                    - bpID - the blueprint ID for the thing to be built
                    - production - the mass/energy produced by this option for mass/energy options respectively
                    - maintenance - the energy upkeep required to maintain production (mass options only)
                    - cost - the mass cost of adding a single unit of this template
                    - markerType - the marker this unit must be built on, or nil if no marker is necessary
                - canBuild - a true/false value caching whether or not this option can currently be built
                - spend - a float value caching the current mass outflow on this option
                - atCapacity - a true/false value caching whether or not the maximum spend for this job has already been reached
                - safety - a float value caching the last predicted half-life for this option, i.e. how many seconds until a 50% chance of destruction
                - priority - a float value caching the last calculated priority
        ]]
        self.options = {}
        self.nOptions = 0
    end,
    GetCurrentSpend = function(self)
        local spend = 0
        for i=1, self.nOptions do
            local option = self.options[i]
            option.spend = option.job.data.actualSpend + ((option.job.data.theoreticalSpend - option.job.data.actualSpend) / THEORETICAL_DOWNWEIGHT)
            spend = spend + option.spend
        end
        self:CheckSpends()
        return spend
    end,
    GetEconomyVector = function(self,isMassManager)
        local vector = {0, 0}
        for i=1, self.nOptions do
            local option = self.options[i]
            if isMassManager then
                vector[1] = vector[1] + (option.template.production * option.spend / option.template.cost)
                vector[2] = vector[2] - (option.maintenance * option.spend / option.template.cost)
            else
                vector[2] = vector[2] + (option.template.production * option.spend / option.template.cost)
            end
        end
        return vector
    end,
    SetPriorities = function(self,foo)
        for i=1, self.nOptions do
            self.options[i].priority = foo(self.options[i])
        end
    end,
    SortOptions = function(self,foo)
        self:SetPriorities(foo)
        table.sort(self.options,function(a,b) return a.priority > b.priority end)
    end,
    ReverseSortOptions = function(self,foo)
        self:SetPriorities(foo)
        table.sort(self.options,function(a,b) return a.priority < b.priority end)
    end,
    Run = function(self, trash)
        trash:Add(ForkThread(self.MonitorSafetyThread, self))
        trash:Add(ForkThread(self.MonitorCanBuildThread, self))
    end,
    -- Methods that can optionally be implementated in sub-classes
    PrepareOptions = function(self) end -- Do any option prep post addition of all templates
    AllocationComplete = function(self) end -- Do any tidying post an allocation round
    CheckSpends = function(self) end -- Check how well target spend matches allocation spend
    -- Methods where an implementation is required in sub-classes
    AddTemplate = function(self) end -- Add a template, and handle potential option generation
    GetNext = function(self,index,increasingSpend) end -- Fetch next option index (after provided index), or -1 if no option exists
    MaxCanSpend = function(self,option) end -- Return the max additional spend amount on the given option
    MaxCanReduce = function(self,option) end -- Return the max possible spend reduction on the given option
    IncreaseSpend = function(self,option,amount) end -- Given an option from this stack, increase spend by amount
    PauseSpend = function(self) end -- Pause all new spending
    ReduceSpend = function(self,option,amount) end -- Given an option from this stack, reduce spending by amount
    MonitorSafetyThread = function(self) end -- Continually update safety of options
    MonitorCanBuildThread = function(self) end -- Continually update canBuild status of options
})

EconomyManager = Class({
    Init = function(self,brain)
        if not PRODUCTION_GRAPH then
            PRODUCTION_GRAPH = import('/mods/DilliDalli/lua/FlowAI/framework/production/ProductionGraph.lua').GetProductionGraph()
            ADJACENCY_BUFFS = import('/lua/sim/AdjacencyBuffs.lua').GetAdjacencyBuffs()
        end
        self.brain = brain
        self.allocation = 0
        self.targetRatio = 12
        self.marginalEnergyCost = STARTING_ENERGY_COST
        self.baseVector = {1, 10}

        -- Combined mass / energy projects
        self.massManagers = {
            -- TODO
        }
        for _, massManager in self.massManagers do massManager:Init() end

        -- Pure energy projects
        self.energyManagers = {
            -- TODO
        }
        for _, energyManager in self.energyManagers do energyManager:Init() end

        self:LoadBPs()
    end,

    LoadBPs = function(self)
        for bpID, node in PRODUCTION_GRAPH do
            -- Skip adjacency for now. Deal with this later. TODO
            -- Direct earning
            if node.bp.Economy.ProductionPerSecondMass and node.bp.Economy.ProductionPerSecondMass > 0 then
                -- If any mass can be produced by this unit, place into mass templates
                local netEnergy = 0
                if node.bp.Economy.ProductionPerSecondEnergy and node.bp.Economy.ProductionPerSecondEnergy > 0 then
                    netEnergy = netEnergy + node.bp.Economy.ProductionPerSecondEnergy
                end
                if node.bp.Economy.MaintenanceConsumptionPerSecondEnergy and node.bp.Economy.MaintenanceConsumptionPerSecondEnergy > 0 then
                    netEnergy = netEnergy - node.bp.Economy.MaintenanceConsumptionPerSecondEnergy
                end
                local markerType = nil
                if node.bp.Physics.BuildRestriction == 'RULEUBR_OnMassDeposit' then
                    markerType = 'Mass'
                elseif node.bp.Physics.BuildRestriction == 'RULEUBR_OnHydrocarbonDeposit' then
                    markerType = 'Hydrocarbon'
                end
                local template = {
                    bpID = bpID,
                    production = node.bp.Economy.ProductionPerSecondMass,
                    maintenance = -netEnergy,
                    cost = node.bp.Economy.BuildCostMass,
                    markerType = markerType
                }
                for _, manager in self.massManagers do manager:AddTemplate(template) end
            end
            if node.bp.Economy.ProductionPerSecondEnergy and node.bp.Economy.ProductionPerSecondEnergy > 0 then
                -- If energy can be produced by this unit, place into energy templates
                local markerType = nil
                if node.bp.Physics.BuildRestriction == 'RULEUBR_OnMassDeposit' then
                    markerType = 'Mass'
                elseif node.bp.Physics.BuildRestriction == 'RULEUBR_OnHydrocarbonDeposit' then
                    markerType = 'Hydrocarbon'
                end
                local template = {
                    bpID = bpID,
                    production = node.bp.Economy.ProductionPerSecondEnergy,
                    cost = node.bp.Economy.BuildCostMass,
                    markerType = markerType
                }
                for _, manager in self.energyManagers do manager:AddTemplate(template) end
            end
        end
        for _, manager in self.massManagers do manager:PrepareOptions() end
        for _, manager in self.energyManagers do manager:PrepareOptions() end
    end,

    ReduceSpend = function(self,currentSpend)
        -- Prevent additional spending, remove engineers that have yet to start assisting
        -- Determine current economy vector
        local economyVector = {0, 0}
        for _, manager in self.massManagers do
            local vector = manager:GetEconomyVector(true)
            economyVector[1] = economyVector[1] + vector[1]*PREDICTIONS_PERIOD
            economyVector[2] = economyVector[2] + vector[2]*PREDICTIONS_PERIOD
        end
        for _, manager in self.energyManagers do
            local vector = manager:GetEconomyVector(false)
            economyVector[1] = economyVector[1] + vector[1]*PREDICTIONS_PERIOD
            economyVector[2] = economyVector[2] + vector[2]*PREDICTIONS_PERIOD
        end
        -- Determine target ratio for spending reductions
        local ratio = math.max(0, economyVector[2] / math.max(economyVector[1], 1))
        -- Amount we can spend
        local savingsToMake = currentSpend - self.allocation
        -- Prep option managers and stack state tracking
        local massIndices = {}
        for i, manager in self.massManagers do
            manager:ReverseSortOptions(function(option) GetMassPriority(option.template, self.marginalEnergyCost, option.safety) end)
            massIndices[i] = manager:GetNext(0, false)
        end
        energyIndices = {}
        for i, manager in self.energyManagers do
            manager:ReverseSortOptions(function(option) GetEnergyPriority(option.template, option.safety) end)
            energyIndices[i] = manager:GetNext(0, false)
        end
        -- Do allocation loop
        while savingsToMake > 0 do
            -- Select best mass option
            local massOption = nil
            local massIndex = -1
            local massManager = nil
            for i, k in massIndices do
                if (k > 0) and ((massOption == nil) or (massOption.priority > self.massManagers.options[k].priority)) then
                    massOption = self.massManagers[i].options[k]
                    massIndex = k
                    massManager = self.massManagers[i]
                end
            end
            local energyOption = nil
            local energyIndex = -1
            local energyManager = nil
            for i, k in energyIndices do
                if (k > 0) and ((energyOption == nil) or (energyOption.priority > self.energyManagers.options[k].priority)) then
                    energyOption = self.energyManagers[i].options[k]
                    energyIndex = k
                    energyManager = self.energyManagers[i]
                end
            end
            if (massOption == nil) or (energyOption == nil) then
                -- Can't reduce spend any more than we currently have
                break
            end
            -- Determine spend limitations
            local mr = ratio*math.max(massOption.priority,0.0000001) -- Cache this, we use it lots
            local ep = math.max(energyOption.priority,0.0000001)
            local massToReduce = math.min(
                savingsToMake,
                math.min(
                    massManager:MaxCanReduce(massOption) * (1 + (mr / ep)),
                    energyManager:MaxCanReduce(energyOption) * (1 + (ep / mr))
                )
            )
            -- Reduce spends
            massManager:ReduceSpend(massOption, (massToReduce * ep) / (mr + ep))
            energyManager:ReduceSpend(energyOption, (massToReduce * mr) / (mr + ep))
            -- Fetch new indices
            massManager:GetNext(massIndex, false)
            energyManager:GetNext(energyIndex, false)
            -- Update allocation
            savingsToMake = savingsToMake - massToReduce
        end
        -- Post allocation tidying
        for _, manager in self.massManagers do manager:AllocationComplete() end
        for _, manager in self.energyManagers do manager:AllocationComplete() end
    end,

    PauseSpend = function(self)
        -- Restrict jobs from assigning additional engineers
        for _, massManager in self.massManagers do
            massManager:PauseSpend()
        end
        for _, energyManager in self.energyManagers do
            energyManager:PauseSpend()
        end
    end,

    IncreaseSpend = function(self,currentSpend)
        -- Increase spending on economic jobs
        -- Determine current economy vector
        local economyVector = {self.baseVector[1], self.baseVector[2]}
        for _, manager in self.massManagers do
            local vector = manager:GetEconomyVector(true)
            economyVector[1] = economyVector[1] + vector[1]*PREDICTIONS_PERIOD
            economyVector[2] = economyVector[2] + vector[2]*PREDICTIONS_PERIOD
        end
        for _, manager in self.energyManagers do
            local vector = manager:GetEconomyVector(false)
            economyVector[1] = economyVector[1] + vector[1]*PREDICTIONS_PERIOD
            economyVector[2] = economyVector[2] + vector[2]*PREDICTIONS_PERIOD
        end
        -- Determine target ratio for spending in this allocation round
        local targetMass = math.max(MIN_MASS_INCREASE+economyVector[1],economyVector[1]*MASS_INCREASE_MULTIPLIER)
        local ratio = math.max(0, (targetMass*self.targetRatio - economyVector[2])/(targetMass - economyVector[1]))
        -- Amount we can spend
        local leftToAllocate = self.allocation - currentSpend
        -- Prep option managers and stack state tracking
        local massIndices = {}
        for i, manager in self.massManagers do
            manager:SortOptions(function(option) GetMassPriority(option.template, self.marginalEnergyCost, option.safety) end)
            massIndices[i] = manager:GetNext(0, true)
        end
        energyIndices = {}
        for i, manager in self.energyManagers do
            manager:SortOptions(function(option) GetEnergyPriority(option.template, option.safety) end)
            energyIndices[i] = manager:GetNext(0, true)
        end
        -- Cache worst marginal energy cost as we go (assume at least one funding round occurs)
        local newMarginalEnergyCost = STARTING_ENERGY_COST
        -- Do allocation loop
        while leftToAllocate > 0 do
            -- Select best mass option
            local massOption = nil
            local massIndex = -1
            local massManager = nil
            for i, k in massIndices do
                if (k > 0) and ((massOption == nil) or (massOption.priority < self.massManagers.options[k].priority)) then
                    massOption = self.massManagers[i].options[k]
                    massIndex = k
                    massManager = self.massManagers[i]
                end
            end
            local energyOption = nil
            local energyIndex = -1
            local energyManager = nil
            for i, k in energyIndices do
                if (k > 0) and ((energyOption == nil) or (energyOption.priority < self.energyManagers.options[k].priority)) then
                    energyOption = self.energyManagers[i].options[k]
                    energyIndex = k
                    energyManager = self.energyManagers[i]
                end
            end
            if (massOption == nil) or (energyOption == nil) or (massOption.priority <= MIN_MASS_PRIORITY) or (energyOption.priority <= MIN_ENERGY_PRIORITY) then
                -- Can't spend any more than we currently have
                break
            end
            -- This works since the energyOption priority is actually a measure of energy gain per unit mass spent
            newMarginalEnergyCost = math.max(1/energyOption.priority, newMarginalEnergyCost)
            -- Determine spend limitations
            local mr = ratio*massOption.priority -- Cache this, we use it lots
            local massToSpend = math.min(
                leftToAllocate,
                math.min(
                    massManager:MaxCanSpend(massOption) * (1 + (mr / energyOption.priority)),
                    energyManager:MaxCanSpend(energyOption) * (1 + (energyOption.priority / mr))
                )
            )
            -- Distribute mass
            massManager:IncreaseSpend(massOption, (massToSpend * energyOption.priority) / (mr + energyOption.priority))
            energyManager:IncreaseSpend(energyOption, (massToSpend * mr) / (mr + energyOption.priority))
            -- Fetch new indices
            massManager:GetNext(massIndex, true)
            energyManager:Getnext(energyIndex, true)
            -- Update allocation
            leftToAllocate = leftToAllocate - massToSpend
        end
        -- Post allocation tidying
        for _, manager in self.massManagers do manager:AllocationComplete() end
        for _, manager in self.energyManagers do manager:AllocationComplete() end
        self.marginalEnergyCost = newMarginalEnergyCost
    end,

    SetTargetRatio = function(self,ratio)
        self.targetRatio = ratio
    end,

    SetAllocation = function(self,allocation)
        self.allocation = allocation
    end,

    ManageJobsThread = function(self)
        WaitTicks(LOOP_WAIT)
        while self.brain:IsAlive() do
            -- Get the current state
            local currentSpend = self:GetCurrentSpend()
            self:CheckCanBuild()
            -- Check state
            if self.allocation*TARGET_TOLERANCE < currentSpend then
                -- Spending too much.  Reduce spend.
                self:ReduceSpend(currentSpend)
                self.steady = false
            elseif currentSpend*TARGET_TOLERANCE < self.allocation then
                -- Could be investing more.  Increase spend.
                self:IncreaseSpend(currentSpend)
                self.steady = false
            else
                if not self.steady then
                    self:PauseSpend()
                    self.steady = true
                end
            end
            WaitTicks(LOOP_WAIT)
        end
    end,

    MonitorEconomyThread = function(self)
        WaitTicks(LOOP_WAIT)
        local temperature = 0.9
        local t1 = 1 - temperature
        self.baseVector = {self.brain.aibrain:GetEconomyIncome('MASS'), self.brain.aibrain:GetEconomyIncome('ENERGY')}
        WaitTicks(LOOP_WAIT-1)
        while self.brain:IsAlive() do
            self.baseVector = {
                self.brain.aibrain:GetEconomyIncome('MASS')*t1 + self.baseVector[1]*temperature,
                self.brain.aibrain:GetEconomyIncome('ENERGY')*t1 + self.baseVector[2]*temperature
            }
            WaitTicks(LOOP_WAIT)
        end
    end,

    Run = function(self)
        self.brain.trash:Add(ForkThread(self.ManageJobsThread, self))
        self.brain.trash:Add(ForkThread(self.MonitorEconomyThread, self))
        for _, manager in self.massManagers do manager:Run(self.brain.trash) end
        for _, manager in self.energyManagers do manager:Run(sefl.brain.trash) end
    end,
})


local function GetMassPriority(template, marginalEnergyCost, safety)
    -- Formula for calculating the relative priority of building some mass producing thing.
    --[[
        So what does this formula mean, and how did we get to it?
        Firstly, to explain the arguments:
            - production (template.production) - the amount of mass the 'thing' will produce per second once it is constructed.
            - cost (template.cost) - the amount of mass the 'thing' costs directly to build.
            - maintenance (template.maintenance) - the amount of energy the 'thing' will cost to run (without which no mass is produced).
            - marginalEnergyCost - the current expected mass cost of getting +1 additional power generation capacity.
            - safety - the expected half life of the 'thing' in seconds (i.e. time by which we estimate it has a 50% chance of being destroyed).

        The simplest version of this formula would be:
            production / cost
        i.e. per unit mass spent, how much production can we get.

        Unfortunately, this doesn't account for the ongoing associated energy costs, which can be really high for things like mass fabricators!
        Here though we can exploit that fact that power generators don't come with an ongoing mass cost, and so we can get a much better estimate for
        actual costs by including the mass cost of the pgens we build to help run the 'thing'.  This changes through the game (t3 pgens are much more
        mass efficient per unit power produced than t1 pgens for example), and so we get the AI to tell us how much a unit of energy costs.

        Our AI can find this out using a simple forumla:
            marginalEnergyCost = massCostOfPgen / energyProducedByPgen
        This needs to be calculated for each pgen, with the lowest marginalEnergyCost indicating the best pgen (subject to tech level availability).

        So our updated cost estimate is:
            actualCost = cost + maintenance * marginalEnergyCost
        Giving a formula of:
            production / (cost + maintenance * marginalEnergyCost)

        This is an improvement, but it still misses something, namely that the enemy will try to blow your buildings up.  Mass points further away
        from your base are more vulnerable, and intuitively we know this means we should upgrade them later than safer mass extractors.  The key
        thing we're estimating as humans can be summed up with the 'saftey' parameter - which gives an estimate of how long until a thing is lost.

        For simplicity, we assume that the probability of losing the 'thing' we build is constant (which we don't actually know, but estimating the
        chance of losing something to a greater degree of precision is excessively hard), and so the chance of losing it on any given second is:
            probabilityOfDestructionPerSecond = math.pow(0.5,1/safety)

        How do we use that to influence our priority?  Well, if a 'thing' is lost, then the natural action to take is to rebuild it.  We calculated
        the 'actualCost' earlier, and so we can use that to generate a per second estimate of the resources spent rebuilding the 'thing':
            perSecondRebuildCost = probabilityOfDestructionPerSecond * actualCost

        This 'perSecondRebuildCost' is like negative production; it's a thing we have to spend to maintain 'production' of mass per second.  This
        means our net mass per second from building the 'thing' is more like:
            netProduction = production - perSecondRebuildCost

        So our improved estimate is now:
            priority = netProduction / actualCost
                     = (production - perSecondRebuildCost) / actualCost
                     = (production - probabilityOfDestructionPerSecond * actualCost) / actualCost
                     = (production / actualCost) - probabilityOfDestructionPerSecond
                     = (production / (cost + maintenance * marginalEnergyCost)) - (1 - math.pow(0.5,1/safety))
                     = production / (cost + maintenance * marginalEnergyCost) - 1 + math.pow(0.5,1/safety)
    ]]
    return template.production / (template.cost + template.maintenance * marginalEnergyCost) - 1 + math.pow(0.5, 1 / safety)
end

local function GetEnergyPriority(template, safety)
    -- Formula for calculating the relative priority of building some mass producing thing.
    -- See mass version for explanation; energy case is simpler since there isn't any maintenance required to run pgens.
    return template.production / template.cost - 1 + math.pow(0.5, 1 / safety)
end
