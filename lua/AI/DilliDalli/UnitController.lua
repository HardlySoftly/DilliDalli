local PROFILER = import('/mods/DilliDalli/lua/AI/DilliDalli/Profiler.lua').GetProfiler()
local MAP = import('/mods/DilliDalli/lua/AI/DilliDalli/Mapping.lua').GetMap()
local CreatePriorityQueue = import('/mods/DilliDalli/lua/AI/DilliDalli/PriorityQueue.lua').CreatePriorityQueue

UnitController = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.land = LandController()
        self.air = AirController()

        self.land:Init(self.brain)
        self.air:Init(self.brain)
    end,

    Run = function(self)
        self.land:Run()
        self.air:Run()
    end,
})

function CreateUnitController(brain)
    local uc = UnitController()
    uc:Initialise(brain)
    return uc
end

LandController = Class({
    Init = function(self,brain)
        self.brain = brain
        self.groups = {}
        self.groupID = 1

        self.maintainTargetBias = 1.5
        self.rematch = false
    end,

    Run = function(self)
        self:ForkThread(self.LandControlThread)
        self:ForkThread(self.LandTargetingThread)
        --self:ForkThread(self.GroupLoggingThread)
    end,

    CreateGroup = function(self,unit)
        local lg = LandGroup()
        lg:Init(self.brain,self,self.groupID)
        self.groupID = self.groupID + 1
        table.insert(self.groups,lg)
        lg:Add(unit)
        lg:Run()
    end,

    FindGroup = function(self,unit)
        -- Add this unit to a relevant group
        local best
        local bestPriority = 0
        if EntityCategoryContains(categories.SCOUT,unit) then
            for _, v in self.groups do
                if not v.scout then
                    v:Add(unit)
                    return
                end
            end
            -- Wait for a group that needs a scout
            unit.CustomData.landAssigned = false
            return
        end
        for _, v in self.groups do
            if (v.size == 0) or v.stop then
                continue
            end
            local priority = (5+v.size)/(1+v.zoneThreat)
            if (not best) or priority < bestPriority then
                best = v
                bestPriority = priority
            end
        end
        if (not best) then
            -- Huh??
            WARN("UnitController: Failed to find group...  creating a new one.")
            self:CreateGroup(unit)
        else
            best:Add(unit)
        end
    end,

    LandTargetingThread = function(self)
        local counter = 0
        while self.brain:IsAlive() do
            if self.rematch then
                counter = 0
                -- Stable matching time
                -- Zones first
                local zones = {}
                for _, z in self.brain.intel.zones do
                    if (z.intel.class == "enemy") or (z.intel.class == "contested") then
                        local retreatEdge = (z.intel.class == "contested")
                        for _, e in z.edges do
                            if (e.zone.intel.class == "neutral") or (e.zone.intel.class == "allied") then
                                retreatEdge = true
                            end
                        end
                        if retreatEdge then
                            table.insert(zones,{zone = z, assigned = false})
                        end
                    end
                end
                if table.getn(zones) == 0 then
                    for _, spawn in self.brain.intel.enemies do
                        table.insert(zones,{zone = MAP:FindZone(spawn), assigned = false})
                    end
                end
                -- Now groups
                local groups = {}
                for _, g in self.groups do
                    if g:Size() > 0 then
                        table.insert(groups,{group = g, pos = g:Position(), assigned = false, old = g.targetZone})
                    end
                end
                -- Now insert the scores
                local scoreQueue = CreatePriorityQueue()
                for _, z in zones do
                    for _, g in groups do
                        -- Higher is better
                        if MAP:CanPathTo(g.pos,z.zone.pos,"surf") then
                            local s = VDist3(g.pos,z.zone.pos)/(g.group:Size()*(z.zone.weight+z.zone.intel.importance.enemy))
                            if g.targetZone.id == z.zone.id then
                                s = s*self.maintainTargetBias
                            end
                            scoreQueue:Queue({ zone = z, group = g, priority = s})
                        end
                    end
                end
                local m = table.getn(zones)
                local n = table.getn(groups)
                -- Now draw in order of priority and assign stuff
                local k = 0
                while scoreQueue:Size() > 0 and k < n and k < m do
                    local item = scoreQueue:Dequeue()
                    if (not item.group.assigned) and (not item.zone.assigned) then
                        k = k+1
                        -- Assign this group to the zone
                        item.group.assigned = true
                        item.zone.assigned = true
                        item.group.group.targetZone = item.zone.zone
                        -- Find a staging zone
                        local bestStaging = item.zone.zone
                        local bestDistance = 1000000
                        for _, e in item.zone.zone.edges do
                            if (e.zone.intel.class == "allied") or (e.zone.intel.class == "neutral") then
                                local d = VDist3(self.brain.intel.spawn,e.zone.pos)
                                if (not bestStaging) or (d < bestDistance) then
                                    bestStaging = e.zone
                                    bestDistance = d
                                end
                            end
                        end
                        if bestStaging then
                            item.group.group.stagingZone = bestStaging
                        else
                            WARN("LandTargetingThread: Unable to identify staging zone!")
                            item.group.group.stagingZone = item.zone.zone
                        end
                    else
                    end
                end
                -- Unassigned groups should be added to the nearest assigned group
                if n > m then
                    for _, g1 in groups do
                        if g1.assigned then
                            continue
                        end
                        local bestGroup
                        local bestDist = 0
                        for _, g2 in groups do
                            if not g2.assigned then
                                continue
                            end
                            local d = VDist3(g1.pos,g2.pos)
                            if (not bestGroup) or (d < bestDist) then
                                bestGroup = g2.group
                                bestDist = d
                            end
                        end
                        g1.group.stop = true
                        bestGroup:Merge(g1.group)
                    end
                end
                -- And breathe out...
                WaitTicks(50)
            else
                counter = counter+1
                if counter > 300 then
                    self.rematch = true
                    counter = 0
                end
                WaitTicks(1)
            end
        end
    end,

    FindNewTarget = function(self,pos,layer)
        local best
        local bestPriority = 0
        local foundYet = false
        -- TODO: use layer info
        for _, v in self.brain.intel.zones do
            if (v.intel.class == "allied") or (v.intel.class == "neutral") or (not MAP:CanPathTo(pos,v.pos,"surf")) then
                continue
            end
            local retreatFound = false
            for _, e in v.edges do
                if e.zone.intel.class == "neutral" or e.zone.intel.class == "allied" then
                    retreatFound = true
                end
            end
            if not retreatFound then
                continue
            end
            local found = false
            for _, g in self.groups do
                if g.targetZone and (VDist3(g.targetZone.pos,v.pos) < 5) then
                    found = true
                end
            end
            if (not found) or (not foundYet) then
                local priority = 1/v.weight
                if table.getn(self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE,v.pos,30,'Enemy')) > 0 then
                    priority = priority/5
                end
                priority = priority * (100+VDist3(pos,v.pos))
                if (not foundYet) and (not found) then
                    best = v
                    bestPriority = priority
                    foundYet = true
                elseif (not best) or (priority < bestPriority) then
                    best = v
                end
            end
        end
        if best then
            return best
        else
            return self.brain.intel:FindZone(self.brain.intel.enemies[Random(1,table.getn(self.brain.intel.enemies))])
        end
    end,

    CheckGroups = function(self)
        -- Delete dead groups
        local i = 1
        while i <= table.getn(self.groups) do
            if (self.groups[i]:Size() == 0) or self.groups[i].stop then
                table.remove(self.groups,i)
            else
                i = i+1
            end
        end
    end,

    GroupLoggingThread = function(self)
        while self.brain:IsAlive() do
            --LOG("=========================")
            --for _, v in self.groups do
            --    LOG("Group: "..tostring(v.id)..", size: "..tostring(v.size)..", reinforcing: "..tostring(table.getn(v.reinforcing))..", units: "..tostring(table.getn(v.units)))
            --end
            LOG("Num groups: "..tostring(table.getn(self.groups)))
            local t = 0
            for _, v in self.groups do
                t = t + table.getn(v.units)
                t = t + table.getn(v.reinforcing)
            end
            LOG("Group state size: "..tostring(t))
            WaitTicks(200)
        end
    end,

    LandControlThread = function(self)
        while self.brain:IsAlive() do
            local start = PROFILER:Now()
            self:CheckGroups()
            local units = self.brain.aiBrain:GetListOfUnits(categories.LAND * categories.MOBILE - categories.ENGINEER,false,true)
            local numUnits = table.getn(units)
            local targetNumberOfGroups = math.min(math.log(math.max(numUnits-2,1)) + 2,self.brain.intel:NumLandAssaultZones())
            local numGroups = table.getn(self.groups)
            for _, unit in units do
                if not unit.CustomData then
                    unit.CustomData = {}
                end
                if (not unit.CustomData.landAssigned) and (not unit:IsBeingBuilt()) then
                    unit.CustomData.landAssigned = true
                    if EntityCategoryContains(categories.EXPERIMENTAL,unit) then
                        self:ForkThread(self.ExpThread,unit)
                    elseif numGroups < targetNumberOfGroups then
                        -- Create group
                        self:CreateGroup(unit)
                        numGroups = numGroups + 1
                    else
                        -- Add to group
                        self:FindGroup(unit)
                    end
                end
            end
            -- Multiple coms?  Pretty niche.
            if self.brain.base.isBOComplete then
                local coms = self.brain.aiBrain:GetListOfUnits(categories.COMMAND,false,true)
                for _, v in coms do
                    v.CustomData.excludeAssignment = true
                    if not v.CustomData.landAssigned and not v.CustomData.isAssigned then
                        v.CustomData.landAssigned = true
                        self:ForkThread(self.ACUThread,v)
                        --self:CreateGroup(v)
                    end
                end
            end
            PROFILER:Add("LandControlThread",PROFILER:Now()-start)
            WaitTicks(21)
        end
    end,

    BiasLocation = function(self,pos,target,dist)
        if not target then
            return pos
        elseif not pos then
            return target
        end
        local delta = VDiff(target,pos)
        local norm = math.max(VDist2(delta[1],delta[3],0,0),1)
        local x = pos[1]+dist*delta[1]/norm
        local z = pos[3]+dist*delta[3]/norm
        x = math.min(ScenarioInfo.size[1]-5,math.max(5,x))
        z = math.min(ScenarioInfo.size[2]-5,math.max(5,z))
        return {x,GetSurfaceHeight(x,z),z}
    end,

    ACUThread = function(self,acu)
        local target
        local scared = false
        while self.brain:IsAlive() and acu and (not acu.Dead) do
            if acu:GetHealth() < 6000 and (not scared) then
                target = self:BiasLocation(self.brain.intel.allies[1],self.brain.intel.enemies[1],10)
                scared = true
            elseif scared and acu:GetHealth()/acu:GetBlueprint().Defense.MaxHealth > 0.9 then
                scared = false
                target = nil
            end
            if self.brain.monitor.units.land.mass.total > 2500 then
                target = self:BiasLocation(self.brain.intel.spawn,self.brain.intel.enemies[1],10)
                scared = true
            end
            if not target then
                local best
                local bestMetric = 0
                for _, v in self.brain.intel.zones do
                    local d0 = VDist3(self.brain.intel.spawn,v.pos)
                    local d1 = 100000000
                    for _, e in self.brain.intel.enemies do
                        d1 = math.min(VDist3(e,v.pos),d1)
                    end
                    local metric = v.weight/(100+math.abs(d0-0.75*d1))
                    if d1 < 75 then
                        continue
                    end
                    if (not best) or (metric > bestMetric) then
                        best = v.pos
                        bestMetric = metric
                    end
                end
                -- Bias target towards enemy base
                target = self:BiasLocation(best,self.brain.intel.enemies[1],10)
            end
            if VDist3(acu:GetPosition(),target) > 20 then
                -- If too far away move nearer
                IssueClearCommands({acu})
                IssueMove({acu},target)
            elseif acu:IsIdleState() then
                -- Else if idle move somewhere random nearby
                local newPos = {target[1] + Random(-15,15),target[2],target[3] + Random(-15,15)}
                IssueMove({acu},newPos)
            end
            WaitTicks(20)
        end
    end,

    ExpThread = function(self,unit)
        local target = table.copy(self.brain.intel.enemies[1])
        local hurt = false
        local lastPos
        local stationary = false
        while unit and (not unit.Dead) do
            local start = PROFILER:Now()
            local myPos = unit:GetPosition()
            if hurt then
                if unit:GetHealth()/unit:GetBlueprint().Defense.MaxHealth > 0.9 then
                    hurt = false
                    target = table.copy(self.brain.intel.enemies[1])
                    IssueClearCommands({unit})
                    IssueAggressiveMove({unit},target)
                elseif unit:IsIdleState() then
                    local newPos = {target[1] + Random(-20,20),target[2],target[3] + Random(-20,20)}
                    IssueAggressiveMove({unit},newPos)
                end
            else
                if unit:GetHealth()/unit:GetBlueprint().Defense.MaxHealth < 0.4 then
                    -- Check if we are hurt
                    hurt = true
                    target = table.copy(self.brain.intel.allies[1])
                    IssueClearCommands({unit})
                    IssueMove({unit},target)
                elseif VDist3(myPos, target) < 40 then
                    -- If near the target, move randomly
                    if unit:IsIdleState() then
                        local newPos = {target[1] + Random(-20,20),target[2],target[3] + Random(-20,20)}
                        IssueAggressiveMove({unit},newPos)
                    end
                elseif lastPos and VDist3(lastPos,myPos) < 1 then
                    stationary = true
                    IssueClearCommands({unit})
                    IssueAggressiveMove({unit},target)
                elseif stationary then
                    stationary = false
                    IssueClearCommands({unit})
                    IssueAggressiveMove({unit},target)
                end
            end
            lastPos = myPos
            PROFILER:Add("ExpThread",PROFILER:Now()-start)
            WaitTicks(20)
        end
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

LandGroup = Class({
    ZONEATTACK = 1,
    RETREAT = 2,

    Init = function(self,brain,controller,id)
        self.brain = brain
        self.controller = controller
        self.id = id
        self.scout = nil
        self.stop = false

        -- Intel stuff
        self.threat = 0
        self.localThreat = 0
        self.localSupport = 0
        self.localThreatPos = nil
        self.zoneThreatAge = 0
        self.zoneThreat = 0
        self.collected = true

        self.units = {}
        self.reinforcing = {}
        self.targetZone = nil
        self.stagingZone = nil
        self.targetingCounter = 0
        self.confidence = 2.0
        self.attacking = true
        self.state = LandGroup.ZONEATTACK
        self.lastPos = nil

        self.reinforceCounter = 0
        self.radius = 30

        self.size = 0
    end,

    Merge = function(self,other)
        for _, v in other.units do
            self:Add(v)
        end
        for _, v in other.reinforcing do
            self:Add(v)
        end
        if (not self.scout) and (other.scout) then
            self.scout = other.scout
        elseif other.scout then
            other.scout.CustomData.landAssigned = false
        end
        if (not self.acu) and (other.acu) then
            self.acu = other.acu
        end
    end,

    AssaultDebuggingThread = function(self)
        local start = PROFILER:Now()
        while self.size > 0 and not self.stop do
            local myPos = self:Position()
            DrawCircle(myPos,table.getn(self.units),'aaffffff')
            if self.targetZone then
                DrawCircle(self.targetZone.pos,1+self.targetZone.intel.threat.land.enemy,'aaff4444')
                if self.attacking then
                    DrawLine(self.targetZone.pos,myPos,'aaff4444')
                else
                    DrawLine(self.targetZone.pos,myPos,'66444444')
                end
            end
            if self.stagingZone then
                DrawCircle(self.stagingZone.pos,1+self.localSupport,'aa44ff44')
                if not self.attacking then
                    DrawLine(self.stagingZone.pos,myPos,'aa44ff44')
                else
                    DrawLine(self.stagingZone.pos,myPos,'66444444')
                end
            end
            PROFILER:Add("AssaultDebuggingThread",PROFILER:Now()-start)
            WaitTicks(2)
            start = PROFILER:Now()
        end
    end,

    GetRandomMoveLoc = function(self,pos,n)
        return {pos[1]+Random(-n,n),pos[2],pos[3]+Random(-n,n)}
    end,

    RetreatFunction = function(self, t, myPos)
        -- Am I still within the necessary parameters for this state?
        if (t > 0) then
            if (not self.localThreatPos) or (self.localSupport > self.localThreat*1.0) then
                return LandGroup.ZONEATTACK
            end
        end
        local retreatPos = self.controller:BiasLocation(myPos,self.localThreatPos,-20)
        if VDist3(retreatPos,self.lastPos) > 7 then
            IssueClearCommands(self.units)
            IssueMove(self.units,self:GetRandomMoveLoc(retreatPos,3))
            self.lastPos = table.copy(retreatPos)
        end
        return 0
    end,
    ZoneAttackFunction = function(self, t, myPos)
        if (t > 0) then
            if (self.localSupport < self.localThreat*0.8) then
                return LandGroup.RETREAT
            end
        end
        if (t == 0) or (not self.lastPos) then
            if self.targetZone then
                self.attacking = (self.localSupport*self.confidence >= self.targetZone.intel.threat.land.enemy)
                if self.attacking then
                    IssueClearCommands(self.units)
                    IssueMove(self.units,self:GetRandomMoveLoc(self.targetZone.pos,3))
                    self.lastPos = table.copy(self.targetZone.pos)
                else
                    IssueClearCommands(self.units)
                    IssueMove(self.units,self:GetRandomMoveLoc(self.stagingZone.pos,3))
                    self.lastPos = table.copy(self.stagingZone.pos)
                end
            end
        else
            if self.attacking then
                self.attacking = (self.localSupport*self.confidence >= self.targetZone.intel.threat.land.enemy)
            else
                self.attacking = (self.localSupport*self.confidence*0.75 >= self.targetZone.intel.threat.land.enemy)
            end
            if self.attacking and self.targetZone then
                if VDist3(self.lastPos,self.targetZone.pos) > 10 then
                    IssueClearCommands(self.units)
                    IssueMove(self.units,self:GetRandomMoveLoc(self.targetZone.pos,3))
                    self.lastPos = table.copy(self.targetZone.pos)
                elseif (math.mod(t,5) == 0) and VDist3(myPos, self.targetZone.pos) < 10 then
                    IssueClearCommands(self.units)
                    IssueMove(self.units,self:GetRandomMoveLoc(self.targetZone.pos,15))
                end
            elseif self.stagingZone then
                if VDist3(self.lastPos,self.stagingZone.pos) > 10 then
                    IssueClearCommands(self.units)
                    IssueMove(self.units,self:GetRandomMoveLoc(self.stagingZone.pos,3))
                    self.lastPos = table.copy(self.stagingZone.pos)
                elseif (math.mod(t,5) == 0) and VDist3(myPos, self.stagingZone.pos) < 10 then
                    IssueClearCommands(self.units)
                    IssueMove(self.units,self:GetRandomMoveLoc(self.stagingZone.pos,8))
                end
            end
        end
        return 0
    end,

    AssaultControlThread = function(self)
        WaitTicks(2)
        local start = PROFILER:Now()
        local t = 1
        while self:Resize() > 0 and not self.stop do
            local myPos = self:Reinforce()
            if self.scout then
                IssueClearCommands({self.scout})
                IssueMove({self.scout},myPos)
            end
            if not self.lastPos then
                self.lastPos = table.copy(myPos)
            end
            self:IntelCheck(myPos)
            local newState = 0
            if (not self.targetZone) then
                self.controller.rematch = true
                self.attacking = false
            end
            -- Not the final form for my behaviours here, but you get the idea of how I might want to include modular behaviours with transitions between states
            if self.state == LandGroup.ZONEATTACK then
                newState = self:ZoneAttackFunction(t,myPos)
            elseif self.state == LandGroup.RETREAT then
                newState = self:RetreatFunction(t,myPos)
            end
            if (t > 0) and (newState ~= 0) and (self.state ~= newState) then
                -- Go around again to run the new behaviour
                t = 0
                self.state = newState
            else
                t = t+1
                PROFILER:Add("AssaultControlThread",PROFILER:Now()-start)
                WaitTicks(10)
                start = PROFILER:Now()
            end
        end
    end,

    DangerAt = function(self,pos,radius)
        local enemyUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,pos,radius,'Enemy')
        local neutralUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,pos,radius,'Enemy')
        local dangerEnemy = self.brain.intel:GetLandThreatAndPos(enemyUnits)
        local dangerNeutral = self.brain.intel:GetLandThreatAndPos(neutralUnits)
        if dangerEnemy.pos and dangerNeutral.pos then
            return { threat = dangerEnemy.threat + dangerNeutral.threat, pos = VMult(VAdd(dangerEnemy.pos,dangerNeutral.pos),0.5)}
        elseif dangerNeutral.pos then
            return dangerNeutral
        else
            return dangerEnemy
        end
    end,

    IntelCheck = function(self,myPos)
        local myPos = self:Position()
        local threat = self:DangerAt(myPos,40)
        self.threat = self.brain.intel:GetLandThreat(self.units)
        self.localThreat = threat.threat
        self.localThreatPos = threat.pos
        self.localSupport = math.max(self.brain.intel:GetLandThreat(self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,myPos,40,'Ally')),
                                     self.brain.intel:GetLandThreat(self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,myPos,70,'Ally'))/1.5)
        if self.acu then
            self.localSupport = self.localSupport - 15
        end
        self.collected = table.getn(self.units) > 2*table.getn(self.reinforcing)
    end,

    Add = function(self,unit)
        -- Add unit, issue initial orders
        if EntityCategoryContains(categories.SCOUT,unit) then
            self.scout = unit
            self.size = self.size + 1
            return
        elseif EntityCategoryContains(categories.COMMAND,unit) then
            self.acu = unit
        end
        table.insert(self.reinforcing,unit)
        self.size = self.size + 1
        if self.targetZone then
            IssueClearCommands({unit})
            IssueAggressiveMove({unit}, self.targetZone.pos)
        end
    end,

    Position = function(self)
        if self.acu then
            return table.copy(self.acu:GetPosition())
        end
        local x = 0
        local z = 0
        local n = 0
        for _, v in self.units do
            if v and (not v.Dead) then
                local pos = v:GetPosition()
                x = x + pos[1]
                z = z + pos[3]
                n = n+1
            end
        end
        if n == 0 then
            -- We're in our base maybe?????
            return self.brain.intel.allies[1]
        else
            return {x/n, GetSurfaceHeight(x/n,z/n), z/n}
        end
    end,

    Reinforce = function(self)
        -- Move units from reinforcing into units
        if table.getn(self.units) == 0 then
            self.units = self.reinforcing
            self.reinforcing = {}
            if self.targetZone then
                IssueClearCommands(self.units)
                IssueMove(self.units,self.targetZone.pos)
            end
            return self:Position()
        else
            local currentPos = self:Position()
            local moved = {}
            local i = 1
            while i <= table.getn(self.reinforcing) do
                if VDist3(self.reinforcing[i]:GetPosition(),currentPos) < self.radius then
                    table.insert(moved,self.reinforcing[i])
                    table.insert(self.units,self.reinforcing[i])
                    table.remove(self.reinforcing,i)
                else
                    i = i+1
                end
            end
            -- Newly arrived units should be ordered to the right place
            if self.lastPos then
                IssueClearCommands(moved)
                IssueMove(moved,self.lastPos)
            end
            local newPos = self:Position()
            -- IssueMove reinforcing to new position
            if self.reinforceCounter == 0 then
                IssueClearCommands(self.reinforcing)
                IssueAggressiveMove(self.reinforcing,newPos)
                self.reinforceCounter = 5
            else
                self.reinforceCounter = self.reinforceCounter - 1
            end
            -- Return new position
            return newPos
        end
    end,

    Resize = function(self)
        -- Eliminate dead units, return new size
        local i = 1
        while i <= table.getn(self.units) do
            if (not self.units[i]) or self.units[i].Dead then
                table.remove(self.units,i)
            else
                i = i+1
            end
        end
        local j = 1
        while j <= table.getn(self.reinforcing) do
            if (not self.reinforcing[j]) or self.reinforcing[j].Dead then
                table.remove(self.reinforcing,j)
            else
                j = j+1
            end
        end
        self.size = table.getn(self.units) + table.getn(self.reinforcing)
        if self.scout then
            self.size = self.size + 1
        end
        return self.size
    end,

    Size = function(self)
        -- Return size
        return self.size
    end,

    Run = function(self)
        self:ForkThread(self.AssaultControlThread)
        --self:ForkThread(self.AssaultDebuggingThread)
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

AirController = Class({
    Init = function(self,brain)
        self.brain = brain
        self.groups = {}
        self.groupID = 1
    end,

    Run = function(self)
        self:ForkThread(self.AirControlThread)
    end,

    CreateGroup = function(self,unit)
        local ag = IntieGroup()
        ag:Init(self.brain,self,self.groupID)
        self.groupID = self.groupID + 1
        self.groups = {}
        table.insert(self.groups,ag)
        ag:Add(unit)
        ag:Run()
    end,

    CheckGroups = function(self)
        -- Delete dead groups
        local i = 1
        while i <= table.getn(self.groups) do
            if self.groups[i]:Size() == 0 then
                table.remove(self.groups,i)
            else
                i = i+1
            end
        end
    end,

    FindGroup = function(self,unit)
        -- Add this unit to a relevant group
        local best
        local bestPriority = 0
        for _, v in self.groups do
            local priority = v.size
            if (not best) or priority < bestPriority then
                best = v
                bestPriority = priority
            end
        end
        if (not best) then
            -- Huh??
            WARN("UnitController: Failed to find group...  creating a new one.")
            self:CreateGroup(unit)
        else
            best:Add(unit)
        end
    end,

    ScoutingThread = function(self,scout)
        local targetZone
        self.brain.intel.controlSpreadSpeed = 0
        while scout and (not scout.Dead) do
            local myPos = scout:GetPosition()
            if (not targetZone) or (VDist2(myPos[1],myPos[3],targetZone.pos[1],targetZone.pos[3]) < 30) or scout:IsIdleState() then
                targetZone = nil
                local bestScore = 0
                for _, v in self.brain.intel.zones do
                    local dist = VDist2(myPos[1],myPos[3],v.pos[1],v.pos[3])
                    local r = Random(100,1000)
                    if (r > bestScore) and (dist >= 50) then
                        targetZone = v
                        bestScore = r
                    elseif (not targetZone) and (dist < 50) then
                        targetZone = v
                    end
                end
                -- Select new target zone and move there
                IssueClearCommands({scout})
                IssueMove({scout},targetZone.pos)
            end
            WaitTicks(10)
        end
    end,

    AirControlThread = function(self)
        while self.brain:IsAlive() do
            self:CheckGroups()
            --LOG("Air Controller - num groups: "..tostring(table.getn(self.groups)))
            local units = self.brain.aiBrain:GetListOfUnits(categories.AIR * categories.MOBILE - categories.ENGINEER,false,true)
            local numUnits = table.getn(units)
            local targetNumberOfGroups = math.max(2*math.log(math.max(numUnits-3,1)),1)
            local numGroups = table.getn(self.groups)
            for _, unit in units do
                if not unit.CustomData then
                    unit.CustomData = {}
                end
                if (not unit.CustomData.airAssigned) and (not unit:IsBeingBuilt()) then
                    unit.CustomData.airAssigned = true
                    if EntityCategoryContains(categories.SCOUT,unit) then
                        self:ForkThread(self.ScoutingThread,unit)
                    elseif numGroups < targetNumberOfGroups then
                        -- Create group
                        self:CreateGroup(unit)
                        numGroups = numGroups + 1
                    else
                        -- Add to group
                        self:FindGroup(unit)
                    end
                end
            end
            WaitTicks(20)
        end
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

IntieGroup = Class({
    Init = function(self,brain,controller,id)
        self.brain = brain
        self.controller = controller
        self.id = id

        self.units = {}
        self.size = 0
        self.targetZone = nil
    end,

    InterceptionThread = function(self)
        while self:Resize() > 0 do
            if (not self.targetZone) or self.units[1]:IsIdleState() or (self.targetZone.intel.threat.land.allied < self.targetZone.intel.threat.land.enemy) then
                local oldZone = self.targetZone
                self.targetZone = nil
                local bestThreat = 0
                local bestSafety = 0
                for _, v in self.brain.intel.zones do
                    local r = Random(1,100)
                    if v.id == oldZone.id then
                        r = 100
                    end
                    if (v.intel.threat.land.allied > v.intel.threat.land.enemy) and v.intel.threat.air.enemy > bestThreat then
                        self.targetZone = v
                        bestThreat = v.intel.threat.air.enemy
                    elseif (bestThreat == 0) and (r > bestSafety) then
                        bestSafety = r
                        self.targetZone = v
                    end
                end
                if self.targetZone and (self.targetZone.id ~= oldZone.id) then
                    IssueClearCommands(self.units)
                    IssueAggressiveMove(self.units,self.targetZone.pos)
                end
            end
            WaitTicks(20)
        end
    end,

    Add = function(self,unit)
        table.insert(self.units,unit)
        self.size = self.size + 1
        if self.targetZone then
            IssueClearCommands({unit})
            IssueAggressiveMove({unit},self.targetZone.pos)
        end
    end,

    Run = function(self)
        self:ForkThread(self.InterceptionThread)
    end,

    Resize = function(self)
        local i = 1
        while i <= table.getn(self.units) do
            if self.units[i] and (not self.units[i].Dead) then
                i = i+1
            else
                table.remove(self.units,i)
            end
        end
        self.size = table.getn(self.units)
        return self.size
    end,

    Size = function(self)
        return self.size
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
