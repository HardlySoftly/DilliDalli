local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')
local PROFILER = import('/mods/DilliDalli/lua/AI/DilliDalli/Profiler.lua').GetProfiler()
local CreatePriorityQueue = import('/mods/DilliDalli/lua/AI/DilliDalli/PriorityQueue.lua').CreatePriorityQueue

GameMap = Class({
    InitMap = function(self)
        local doDilliDalliMapAnalysis = true
        local drawStuffz = false
        if doDilliDalliMapAnalysis then
            -- Credit to Uveso for this timing code
            LOG('DilliDalli: Function CreateMapMarkers() started!')
            local START = GetSystemTimeSecondsOnlyForProfileUse()
            self:CreateMapMarkers()
            self:InitZones()
            local END = GetSystemTimeSecondsOnlyForProfileUse()
            LOG(string.format('DilliDalli: Function CreateMapMarkers() finished, runtime: %.2f seconds.', END - START  ))
            if drawStuffz then
                ForkThread(
                    function()
                        coroutine.yield(100)
                        while true do
                            --self:DrawComponentsLand()
                            self:DrawZoning()
                            self:DrawZones()
                            WaitTicks(2)
                        end
                    end
                )
            end
        end
    end,

    CreateMapMarkers = function(self)
        -- TODO: inspect the results of GetTerrainType for context
        -- Step 1: Calculate marker positions
        self.border = 5
        local effectiveXSize = ScenarioInfo.size[1]-2*self.border
        local effectiveZSize = ScenarioInfo.size[2]-2*self.border
        -- Max number of markers limited to ~200x200 = 40k (a lot, but oh well)
        self.gap = math.max(5, math.max(math.round(effectiveXSize/120),math.round(effectiveZSize/120)))
        self.xNum = math.ceil(effectiveXSize/self.gap)+1
        self.zNum = math.ceil(effectiveZSize/self.gap)+1
        self.xOffset = (ScenarioInfo.size[1] - (self.xNum-1)*self.gap)/2
        self.zOffset = (ScenarioInfo.size[2] - (self.zNum-1)*self.gap)/2
        -- Step 2: Initialize markers
        self.markers = {}
        for i=1,self.xNum do
            self.markers[i] = {}
            for j=1,self.zNum do
                self.markers[i][j] = {
                    pos = self:GetPosition(i,j),
                    -- Order is (x,z): [+1][+1], [+1][0], [+1][-1], [0][-1], [-1][-1], [-1][0], [-1][+1], [0][+1]
                    land = { complete = false, component = -1, connections = { -1, -1, -1, -1, -1, -1, -1, -1} },
                    bed = { complete = false, component = -1, connections = { -1, -1, -1, -1, -1, -1, -1, -1} },
                    water = { complete = false, component = -1, connections = { -1, -1, -1, -1, -1, -1, -1, -1} },
                    surf = { complete = false, component = -1, connections = { -1, -1, -1, -1, -1, -1, -1, -1} },
                    subs = { complete = false, component = -1, connections = { -1, -1, -1, -1, -1, -1, -1, -1} },
                }
            end
        end
        -- Step 3: Check local connectivity
        for i=1,self.xNum do
            for j=1,self.zNum do
                self:GetConnections(i,j)
            end
        end
        -- Step 4: Generate connected components
        self.componentNums = { land = 0, bed = 0, water = 0, surf = 0, subs = 0 }
        self.componentSizes = { land = {}, bed = {}, water = {}, surf = {}, subs = {} }
        for i=1,self.xNum do
            for j=1,self.zNum do
                self:GenerateComponents(i,j)
            end
        end
    end,

    GetPosition = function(self,i,j)
        local x = self.xOffset + (i-1)*self.gap
        local z = self.xOffset + (j-1)*self.gap
        return {x, GetSurfaceHeight(x,z), z}
    end,

    GetConnections = function(self,i,j)
        local pos = self.markers[i][j].pos
        if i < self.xNum and j < self.zNum then
            local k = 1
            self.markers[i][j].land.connections[k] = self:CheckConnectivityLand(pos,1,1,1,0,0,1)
            self.markers[i][j].bed.connections[k] = self:CheckConnectivityAmphibian(pos,1,1,1,0,0,1)
            self.markers[i][j].surf.connections[k] = self:CheckConnectivitySurface(pos,1,1,1,0,0,1)
            -- Now fill in the reverse to save time
            self.markers[i+1][j+1].land.connections[k+4] = self.markers[i][j].land.connections[k]
            self.markers[i+1][j+1].bed.connections[k+4] = self.markers[i][j].bed.connections[k]
            self.markers[i+1][j+1].surf.connections[k+4] = self.markers[i][j].surf.connections[k]
        end
        if i < self.xNum then
            local k = 2
            self.markers[i][j].land.connections[k] = self:CheckConnectivityLand(pos,1,0,0.5,0.5,0.5,-0.5)
            self.markers[i][j].bed.connections[k] = self:CheckConnectivityAmphibian(pos,1,0,0.5,0.5,0.5,-0.5)
            self.markers[i][j].surf.connections[k] = self:CheckConnectivitySurface(pos,1,0,0.5,0.5,0.5,-0.5)
            -- Now fill in the reverse to save time
            self.markers[i+1][j].land.connections[k+4] = self.markers[i][j].land.connections[k]
            self.markers[i+1][j].bed.connections[k+4] = self.markers[i][j].bed.connections[k]
            self.markers[i+1][j].surf.connections[k+4] = self.markers[i][j].surf.connections[k]
        end
        if i < self.xNum and j > 1 then
            local k = 3
            self.markers[i][j].land.connections[k] = self:CheckConnectivityLand(pos,1,-1,1,0,0,-1)
            self.markers[i][j].bed.connections[k] = self:CheckConnectivityAmphibian(pos,1,-1,1,0,0,-1)
            self.markers[i][j].surf.connections[k] = self:CheckConnectivitySurface(pos,1,-1,1,0,0,-1)
            -- Now fill in the reverse to save time
            self.markers[i+1][j-1].land.connections[k+4] = self.markers[i][j].land.connections[k]
            self.markers[i+1][j-1].bed.connections[k+4] = self.markers[i][j].bed.connections[k]
            self.markers[i+1][j-1].surf.connections[k+4] = self.markers[i][j].surf.connections[k]
        end
        if j > 1 then
            local k = 4
            self.markers[i][j].land.connections[k] = self:CheckConnectivityLand(pos,0,-1,0.5,-0.5,-0.5,-0.5)
            self.markers[i][j].bed.connections[k] = self:CheckConnectivityAmphibian(pos,0,-1,0.5,-0.5,-0.5,-0.5)
            self.markers[i][j].surf.connections[k] = self:CheckConnectivitySurface(pos,0,-1,0.5,-0.5,-0.5,-0.5)
            -- Now fill in the reverse to save time
            self.markers[i][j-1].land.connections[k+4] = self.markers[i][j].land.connections[k]
            self.markers[i][j-1].bed.connections[k+4] = self.markers[i][j].bed.connections[k]
            self.markers[i][j-1].surf.connections[k+4] = self.markers[i][j].surf.connections[k]
        end
    end,

    GenerateComponents = function(self,i,j)
        for _, s in {"surf", "bed", "land"} do --, "water", "subs", "land"} do
            -- TODO: optimisation - don't create a component for disconnected nodes (e.g. land node over water)
            if self.markers[i][j][s].component < 0 then
                self.componentNums[s] = self.componentNums[s] + 1
                local component = self.componentNums[s]
                self.componentSizes[s][component] = 0
                work = {{i=i, j=j}}
                while table.getn(work) > 0 do
                    local i0 = work[1].i
                    local j0 = work[1].j
                    table.remove(work,1)
                    if i0 <= 0 or j0<= 0 or i0 > self.xNum or j0 > self.zNum or self.markers[i0][j0][s].component > 0 then
                        continue
                    end
                    self.markers[i0][j0][s].component = component
                    self.componentSizes[s][component] = self.componentSizes[s][component]+1
                    if self.markers[i0][j0][s].connections[1] > 0 then
                        table.insert(work,{i=i0+1, j=j0+1})
                    end
                    if self.markers[i0][j0][s].connections[2] > 0 then
                        table.insert(work,{i=i0+1, j=j0})
                    end
                    if self.markers[i0][j0][s].connections[3] > 0 then
                        table.insert(work,{i=i0+1, j=j0-1})
                    end
                    if self.markers[i0][j0][s].connections[4] > 0 then
                        table.insert(work,{i=i0, j=j0-1})
                    end
                    if self.markers[i0][j0][s].connections[5] > 0 then
                        table.insert(work,{i=i0-1, j=j0-1})
                    end
                    if self.markers[i0][j0][s].connections[6] > 0 then
                        table.insert(work,{i=i0-1, j=j0})
                    end
                    if self.markers[i0][j0][s].connections[7] > 0 then
                        table.insert(work,{i=i0-1, j=j0+1})
                    end
                    if self.markers[i0][j0][s].connections[8] > 0 then
                        table.insert(work,{i=i0, j=j0+1})
                    end
                end
            end
        end
    end,

    DrawComponentsLand = function(self)
        local colours = { 'aa1f77b4', 'aaff7f0e', 'aa2ca02c', 'aad62728', 'aa9467bd', 'aa8c564b', 'aae377c2', 'aa7f7f7f', 'aabcbd22', 'aa17becf' }
        for i=1,self.xNum do
            for j=1,self.zNum do
                local connections = 0
                for _, v in self.markers[i][j].land.connections do
                    connections = connections + v
                end
                if connections == 8 then
                    continue
                end
                for k=1,8 do
                    if self.markers[i][j].land.connections[k] == 1 then
                        local i1 = i
                        local j1 = j
                        if k == 1 then
                            i1 = i+1
                            j1 = j+1
                        elseif k == 2 then
                            i1 = i+1
                        elseif k == 3 then
                            i1 = i+1
                            j1 = j-1
                        elseif k == 4 then
                            j1 = j-1
                        elseif k == 5 then
                            i1 = i-1
                            j1 = j-1
                        elseif k == 6 then
                            i1 = i-1
                        elseif k == 7 then
                            i1 = i-1
                            j1 = j+1
                        else
                            j1 = j+1
                        end
                        if i1 > 0 and j1 > 0 and i1 <= self.xNum and j1 <= self.zNum and (self.componentSizes.land[self.markers[i][j].land.component] > 10) then
                            DrawLine(self.markers[i][j].pos,self.markers[i1][j1].pos,colours[math.mod(self.markers[i][j].land.component-1,table.getn(colours))+1])
                        end
                    end
                end
            end
        end
    end,

    CheckConnectivitySurface = function(self,pos,xdelta,zdelta,orthX0,orthZ0,orthX1,orthZ1)
        local maxSlope = 0.5 -- Slope = ydiff/distance
        local num = math.ceil(3*self.gap)
        local length = self.gap*math.sqrt(xdelta*xdelta + zdelta*zdelta)
        local step = length/num
        local dist = math.sqrt(xdelta*xdelta + zdelta*zdelta)*step
        -- TODO: this isn't actually symmetrical for diagonals (which is making my connectivity graph directed, which is bad) - Now fixed??
        for i=step,length,step do
            local y0 = GetSurfaceHeight(pos[1]+(i-step)*xdelta,pos[3]+(i-step)*zdelta)
            local y1 = GetSurfaceHeight(pos[1]+i*xdelta,pos[3]+i*zdelta)
            local y2 = GetSurfaceHeight(pos[1]+(i-step)*xdelta+step*orthX0,pos[3]+(i-step)*zdelta+step*orthZ0)
            local y3 = GetSurfaceHeight(pos[1]+(i-step)*xdelta+step*orthX1,pos[3]+(i-step)*zdelta+step*orthZ1)
            if math.abs(y1-y0)/dist > maxSlope or math.abs(y3-y2)/dist > maxSlope then
                return 0
            end
        end
        return 1
    end,

    CheckConnectivityLand = function(self,pos,xdelta,zdelta,orthX0,orthZ0,orthX1,orthZ1)
        local maxSlope = 0.5 -- Slope = ydiff/distance
        local num = math.ceil(3*self.gap)
        local length = self.gap*math.sqrt(xdelta*xdelta + zdelta*zdelta)
        local step = length/num
        local dist = math.sqrt(xdelta*xdelta + zdelta*zdelta)*step
        -- TODO: this isn't actually symmetrical for diagonals (which is making my connectivity graph directed, which is bad) - Now fixed??
        for i=step,length,step do
            local y0 = GetTerrainHeight(pos[1]+(i-step)*xdelta,pos[3]+(i-step)*zdelta)
            local y1 = GetTerrainHeight(pos[1]+i*xdelta,pos[3]+i*zdelta)
            local y2 = GetTerrainHeight(pos[1]+(i-step)*xdelta+step*orthX0,pos[3]+(i-step)*zdelta+step*orthZ0)
            local y3 = GetTerrainHeight(pos[1]+(i-step)*xdelta+step*orthX1,pos[3]+(i-step)*zdelta+step*orthZ1)
            local y0s = GetSurfaceHeight(pos[1]+(i-step)*xdelta,pos[3]+(i-step)*zdelta)
            local y1s = GetSurfaceHeight(pos[1]+i*xdelta,pos[3]+i*zdelta)
            local y2s = GetSurfaceHeight(pos[1]+(i-step)*xdelta+step*orthX0,pos[3]+(i-step)*zdelta+step*orthZ0)
            local y3s = GetSurfaceHeight(pos[1]+(i-step)*xdelta+step*orthX1,pos[3]+(i-step)*zdelta+step*orthZ1)
            if math.abs(y1-y0)/dist > maxSlope or math.abs(y3-y2)/dist > maxSlope then
                return 0
            elseif y0 < y0s or y1 < y1s or y2 < y2s or y3 < y3s then
                return 0
            end
        end
        return 1
    end,

    CheckConnectivityAmphibian = function(self,pos,xdelta,zdelta,orthX0,orthZ0,orthX1,orthZ1)
        local maxSlope = 0.5 -- Slope = ydiff/distance
        local num = math.ceil(3*self.gap)
        local length = self.gap*math.sqrt(xdelta*xdelta + zdelta*zdelta)
        local step = length/num
        local dist = math.sqrt(xdelta*xdelta + zdelta*zdelta)*step
        -- TODO: this isn't actually symmetrical for diagonals (which is making my connectivity graph directed, which is bad) - Now fixed??
        for i=step,length,step do
            local y0 = GetTerrainHeight(pos[1]+(i-step)*xdelta,pos[3]+(i-step)*zdelta)
            local y1 = GetTerrainHeight(pos[1]+i*xdelta,pos[3]+i*zdelta)
            local y2 = GetTerrainHeight(pos[1]+(i-step)*xdelta+step*orthX0,pos[3]+(i-step)*zdelta+step*orthZ0)
            local y3 = GetTerrainHeight(pos[1]+(i-step)*xdelta+step*orthX1,pos[3]+(i-step)*zdelta+step*orthZ1)
            if math.abs(y1-y0)/dist > maxSlope or math.abs(y3-y2)/dist > maxSlope then
                return 0
            end
        end
        return 1
    end,

    GetIndices = function(self,x,z)
        local i = math.round((x-self.xOffset)/self.gap) + 1
        local j = math.round((z-self.zOffset)/self.gap) + 1
        return {math.min(math.max(1,i),self.xNum), math.min(math.max(1,j),self.zNum)}
    end,

    CanPathTo = function(self,pos0,pos1,layer)
        local indices0 = self:GetIndices(pos0[1],pos0[3])
        local indices1 = self:GetIndices(pos1[1],pos1[3])
        return self.markers[indices0[1]][indices0[2]][layer].component == self.markers[indices1[1]][indices1[2]][layer].component
    end,

    -- Now for section dealing with map zoning
    InitZones = function(self)
        self.zoneRadius = 35
        self.astar = 1
        self:GenerateMapZones()
        self:GenerateMapEdges()
    end,

    CreateZone = function(self,pos,weight,id)
        return { pos = table.copy(pos), weight = weight, edges = {}, id = id }
    end,

    -- TODO: respect component
    FindZone = function(self,pos)
        local best = nil
        local bestDist = 0
        for _, v in self.zones do
            if (not best) or VDist3(pos,v.pos) < bestDist then
                best = v
                bestDist = VDist3(pos,v.pos)
            end
        end
        return best
    end,

    GenerateMapZones = function(self)
        self.zones = {}
        local massPoints = {}
        local zoneID = 1
        for _, v in ScenarioUtils.GetMarkers() do
            if v.type == "Mass" or v.type == "Hydrocarbon" then
                table.insert(massPoints, { pos=v.position, claimed = false, weight = 1, aggX = v.position[1], aggZ = v.position[3] })
            end
        end
        complete = (table.getn(massPoints) == 0)
        while not complete do
            complete = true
            -- Update weights
            for _, v in massPoints do
                v.weight = 1
                v.aggX = v.pos[1]
                v.aggZ = v.pos[3]
            end
            for _, v1 in massPoints do
                if not v1.claimed then
                    for _, v2 in massPoints do
                        if (not v2.claimed) and VDist3(v1.pos,v2.pos) < self.zoneRadius then
                            v1.weight = v1.weight + 1
                            v1.aggX = v1.aggX + v2.pos[1]
                            v1.aggZ = v1.aggZ + v2.pos[3]
                        end
                    end
                end
            end
            -- Find next point to add
            local best = nil
            for _, v in massPoints do
                if (not v.claimed) and ((not best) or best.weight < v.weight) then
                    best = v
                end
            end
            -- Add next point
            best.claimed = true
            local x = best.aggX/best.weight
            local z = best.aggZ/best.weight
            table.insert(self.zones,self:CreateZone({x,GetSurfaceHeight(x,z),z},best.weight,zoneID))
            zoneID = zoneID + 1
            -- Claim nearby points
            for _, v in massPoints do
                if (not v.claimed) and VDist3(v.pos,best.pos) < self.zoneRadius then
                    v.claimed = true
                elseif not v.claimed then
                    complete = false
                end
            end
        end
    end,

    AStarDist = function(self,pos0,pos1,layer,maxDist)
        --LOG("Calling AStarDist")
        local start = PROFILER:Now()
        local indices0  = self:GetIndices(pos0[1],pos0[3])
        local indices1  = self:GetIndices(pos1[1],pos1[3])
        local i0 = indices0[1]
        local j0 = indices0[2]
        local i1 = indices1[1]
        local j1 = indices1[2]
        if self.markers[i0][j0][layer].component ~= self.markers[i1][j1][layer].component then
            PROFILER:Add("AStarDist",PROFILER:Now()-start)
            return -1
        end
        local component = self.markers[i0][j0][layer].component
        if not maxDist then
            maxDist = 10000000000
        end
        local dstPos = self:GetPosition(i1,j1)
        local pq = CreatePriorityQueue()
        self.astar = self.astar + 1
        self.markers[i0][j0][layer].astar = self.astar
        pq:Queue({i=i0,j=j0,d=0,priority=VDist3(self:GetPosition(i0,j0),dstPos)})
        local n = 0
        while pq:Size() > 0 do
            n = n+1
            local node = pq:Dequeue()
            local neighbours = self:GetNeighbours(node.i,node.j,layer)
            for _, v in neighbours do
                if v.i == i1 and v.j == j1 then
                    PROFILER:Add("AStarDist",PROFILER:Now()-start)
                    return node.d+v.d
                end
                -- Only add to queue if:
                --  1. Not yet visited.
                --  2. Same component
                --  3. Below maxDist
                if (self.markers[v.i][v.j][layer].astar ~= self.astar)
                    and (self.markers[v.i][v.j][layer].component == component)
                    and (node.d + v.d < maxDist) then
                    self.markers[v.i][v.j][layer].astar = self.astar
                    pq:Queue({i=v.i,j=v.j,d=v.d+node.d,priority=node.d+v.d+VDist3(self:GetPosition(v.i,v.j),dstPos)})
                end
            end
        end
        PROFILER:Add("AStarDist",PROFILER:Now()-start)
        return -1
    end,

    GetNeighbours = function(self,i,j,layer)
        res = {}
        local R2 = math.sqrt(2)
        if (i < self.xNum) and (j < self.zNum) and self.markers[i][j][layer].connections[1] == 1 then
            table.insert(res,{ i = i+1, j = j+1, d = R2*self.gap })
        end
        if i < self.xNum and self.markers[i][j][layer].connections[2] == 1 then
            table.insert(res,{ i = i+1, j = j, d = self.gap })
        end
        if i < self.xNum and j > 1 and self.markers[i][j][layer].connections[3] == 1 then
            table.insert(res,{ i = i+1, j = j-1, d = R2*self.gap })
        end
        if j > 1 and self.markers[i][j][layer].connections[4] == 1 then
            table.insert(res,{ i = i, j = j-1, d = self.gap })
        end
        if i > 1 and j > 1 and self.markers[i][j][layer].connections[5] == 1 then
            table.insert(res,{ i = i-1, j = j-1, d = R2*self.gap })
        end
        if i > 1 and self.markers[i][j][layer].connections[6] == 1 then
            table.insert(res,{ i = i-1, j = j, d = self.gap })
        end
        if i > 1 and j < self.zNum and self.markers[i][j][layer].connections[7] == 1 then
            table.insert(res,{ i = i-1, j = j+1, d = R2*self.gap })
        end
        if j < self.zNum and self.markers[i][j][layer].connections[8] == 1 then
            table.insert(res,{ i = i, j = j+1, d = self.gap })
        end
        return res
    end,

    GenerateMapEdges = function(self)
        local work = CreatePriorityQueue()
        for _, v in self.zones do
            local indices = self:GetIndices(v.pos[1],v.pos[3])
            work:Queue({priority=(-v.weight/1000), i=indices[1], j=indices[2], zone=v})
        end
        while work:Size() > 0 do
            --LOG("Zones: "..tostring(work:Size()))
            local item = work:Dequeue()
            if not self.markers[item.i][item.j].surf.nearestZone then
                self.markers[item.i][item.j].surf.nearestZone = item.zone
                local neighbours = self:GetNeighbours(item.i,item.j,"surf")
                for _, v in neighbours do
                    if (not self.markers[v.i][v.j].surf.nearestZone) then
                        --LOG("Pri: "..tostring(item.priority+v.d))
                        work:Queue({i=v.i, j=v.j, priority=item.priority+v.d, zone=item.zone})
                    elseif self.markers[v.i][v.j].surf.nearestZone.id ~= item.zone.id then
                        self:AddEdge(self.markers[v.i][v.j].surf.nearestZone,item.zone)
                    end
                end
            elseif self.markers[item.i][item.j].surf.nearestZone.id ~= item.zone.id then
                local neighbours = self:GetNeighbours(item.i,item.j,"surf")
                for _, v in neighbours do
                    if self.markers[v.i][v.j].surf.nearestZone then
                        self:AddEdge(self.markers[v.i][v.j].surf.nearestZone,item.zone)
                    end
                end
                self:AddEdge(self.markers[item.i][item.j].surf.nearestZone,item.zone)
            end
        end
    end,

    AddEdge = function(self,z1,z2)
        if z1.id == z2.id then
            return
        end
        for _, v in z1.edges do
            if v.id == z2.id then
                return
            end
        end
        local dist = self:AStarDist(z1.pos,z2.pos,"surf")
        if dist > 0 then
            table.insert(z1.edges,{zone = z2, dist = dist})
            table.insert(z2.edges,{zone = z1, dist = dist})
        end
    end,

    DrawZones = function(self)
        local start = PROFILER:Now()
        for _, v in self.zones do
            DrawCircle(v.pos,5*v.weight,'aaffffff')
            for _, v2 in v.edges do
                DrawLine(v.pos,v2.zone.pos,'aa000000')
            end
        end
        PROFILER:Add("MapDrawingThread",PROFILER:Now()-start)
    end,

    DrawZoning = function(self)
        local colours = { 'aa1f77b4', 'aaff7f0e', 'aa2ca02c', 'aad62728', 'aa9467bd', 'aa8c564b', 'aae377c2', 'aa7f7f7f', 'aabcbd22', 'aa17becf' }
        for i=1,self.xNum do
            for j=1,self.zNum do
                for k=1,8 do
                    if self.markers[i][j].surf.connections[k] == 1 then
                        local i1 = i
                        local j1 = j
                        if k == 1 then
                            i1 = i+1
                            j1 = j+1
                        elseif k == 2 then
                            i1 = i+1
                        elseif k == 3 then
                            i1 = i+1
                            j1 = j-1
                        elseif k == 4 then
                            j1 = j-1
                        elseif k == 5 then
                            i1 = i-1
                            j1 = j-1
                        elseif k == 6 then
                            i1 = i-1
                        elseif k == 7 then
                            i1 = i-1
                            j1 = j+1
                        else
                            j1 = j+1
                        end
                        if i1 > 0 and j1 > 0 
                                  and i1 <= self.xNum 
                                  and j1 <= self.zNum
                                  and self.markers[i][j].surf.nearestZone
                                  and self.markers[i1][j1].surf.nearestZone
                                  and self.markers[i][j].surf.nearestZone.id == self.markers[i1][j1].surf.nearestZone.id then
                            DrawLine(self.markers[i][j].pos,self.markers[i1][j1].pos,colours[math.mod(self.markers[i][j].surf.nearestZone.id-1,table.getn(colours))+1])
                        end
                    end
                end
            end
        end
    end,

})

local map = GameMap()

function BeginSession()
    map:InitMap()
end

function GetMap()
    return map
end
