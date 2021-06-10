local DilliDalliYeOldeBeginSession = BeginSession
function BeginSession()
    DilliDalliYeOldeBeginSession()
    -- A wild tongue twister appears
    local doDilliDalliMapAnalysis = true
    local drawStuffz = false
    if doDilliDalliMapAnalysis then
        -- Credit to Uveso for this timing code
        LOG('DilliDalli: Function DilliDalliFuncCreateMapMarkers() started!')
        local START = GetSystemTimeSecondsOnlyForProfileUse()
        DilliDalliFuncCreateMapMarkers()
        local END = GetSystemTimeSecondsOnlyForProfileUse()
        LOG(string.format('DilliDalli: Function DilliDalliFuncCreateMapMarkers() finished, runtime: %.2f seconds.', END - START  ))
        if drawStuffz then
            ForkThread(
                function()
                    coroutine.yield(100)
                    while true do
                        DilliDalliFuncDrawComponentsLand()
                        WaitTicks(2)
                    end
                end
            )
        end
    end
end

function DilliDalliFuncCreateMapMarkers()
    ScenarioInfo.DilliDalliMap = {}
    -- Step 1: Calculate marker positions
    ScenarioInfo.DilliDalliMap.border = 5
    local effectiveXSize = ScenarioInfo.size[1]-2*ScenarioInfo.DilliDalliMap.border
    local effectiveZSize = ScenarioInfo.size[2]-2*ScenarioInfo.DilliDalliMap.border
    -- Max number of markers limited to ~200x200 = 40k (a lot, but oh well)
    ScenarioInfo.DilliDalliMap.gap = math.max(5, math.max(math.round(effectiveXSize/200),math.round(effectiveZSize/200)))
    ScenarioInfo.DilliDalliMap.xNum = math.ceil(effectiveXSize/ScenarioInfo.DilliDalliMap.gap)+1
    ScenarioInfo.DilliDalliMap.zNum = math.ceil(effectiveZSize/ScenarioInfo.DilliDalliMap.gap)+1
    ScenarioInfo.DilliDalliMap.xOffset = (ScenarioInfo.size[1] - (ScenarioInfo.DilliDalliMap.xNum-1)*ScenarioInfo.DilliDalliMap.gap)/2
    ScenarioInfo.DilliDalliMap.zOffset = (ScenarioInfo.size[2] - (ScenarioInfo.DilliDalliMap.zNum-1)*ScenarioInfo.DilliDalliMap.gap)/2
    -- Step 2: Initialize markers
    ScenarioInfo.DilliDalliMap.markers = {}
    for i=1,ScenarioInfo.DilliDalliMap.xNum do
        ScenarioInfo.DilliDalliMap.markers[i] = {}
        for j=1,ScenarioInfo.DilliDalliMap.zNum do
            ScenarioInfo.DilliDalliMap.markers[i][j] = {
                pos = DilliDalliFuncGetPosition(i,j),
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
    for i=1,ScenarioInfo.DilliDalliMap.xNum do
        for j=1,ScenarioInfo.DilliDalliMap.zNum do
            DilliDalliFuncGetConnections(i,j)
        end
    end
    -- Step 4: Generate connected components
    ScenarioInfo.DilliDalliMap.componentNums = { land = 0, bed = 0, water = 0, surf = 0, subs = 0 }
    ScenarioInfo.DilliDalliMap.componentSizes = { land = {}, bed = {}, water = {}, surf = {}, subs = {} }
    for i=1,ScenarioInfo.DilliDalliMap.xNum do
        for j=1,ScenarioInfo.DilliDalliMap.zNum do
            DilliDalliFuncGenerateComponents(i,j)
        end
    end
end

function DilliDalliFuncGetPosition(i,j)
    local x = ScenarioInfo.DilliDalliMap.xOffset + (i-1)*ScenarioInfo.DilliDalliMap.gap
    local z = ScenarioInfo.DilliDalliMap.xOffset + (j-1)*ScenarioInfo.DilliDalliMap.gap
    return {x, GetSurfaceHeight(x,z), z}
end

function DilliDalliFuncGetConnections(i,j)
    local pos = ScenarioInfo.DilliDalliMap.markers[i][j].pos
    if i < ScenarioInfo.DilliDalliMap.xNum and j < ScenarioInfo.DilliDalliMap.zNum then
        local k = 1
        ScenarioInfo.DilliDalliMap.markers[i][j].land.connections[k] = DilliDalliFuncCheckConnectivityLand(pos,1,1,1,0,0,1)
        ScenarioInfo.DilliDalliMap.markers[i][j].bed.connections[k] = DilliDalliFuncCheckConnectivityAmphibian(pos,1,1,1,0,0,1)
        --ScenarioInfo.DilliDalliMap.markers[i][j].water.connections[k] = DilliDalliFuncCheckConnectivityWater(pos,1,1,1,0,0,1)
        ScenarioInfo.DilliDalliMap.markers[i][j].surf.connections[k] = DilliDalliFuncCheckConnectivitySurface(pos,1,1,1,0,0,1)
        --ScenarioInfo.DilliDalliMap.markers[i][j].subs.connections[k] = DilliDalliFuncCheckConnectivitySubmarine(pos,1,1,1,0,0,1)
    end
    if i < ScenarioInfo.DilliDalliMap.xNum then
        local k = 2
        ScenarioInfo.DilliDalliMap.markers[i][j].land.connections[k] = DilliDalliFuncCheckConnectivityLand(pos,1,0,0.5,0.5,0.5,-0.5)
        ScenarioInfo.DilliDalliMap.markers[i][j].bed.connections[k] = DilliDalliFuncCheckConnectivityAmphibian(pos,1,0,0.5,0.5,0.5,-0.5)
        --ScenarioInfo.DilliDalliMap.markers[i][j].water.connections[k] = DilliDalliFuncCheckConnectivityWater(pos,1,0,0.5,0.5,0.5,-0.5)
        ScenarioInfo.DilliDalliMap.markers[i][j].surf.connections[k] = DilliDalliFuncCheckConnectivitySurface(pos,1,0,0.5,0.5,0.5,-0.5)
        --ScenarioInfo.DilliDalliMap.markers[i][j].subs.connections[k] = DilliDalliFuncCheckConnectivitySubmarine(pos,1,0,0.5,0.5,0.5,-0.5)
    end
    if i < ScenarioInfo.DilliDalliMap.xNum and j > 1 then
        local k = 3
        ScenarioInfo.DilliDalliMap.markers[i][j].land.connections[k] = DilliDalliFuncCheckConnectivityLand(pos,1,-1,1,0,0,-1)
        ScenarioInfo.DilliDalliMap.markers[i][j].bed.connections[k] = DilliDalliFuncCheckConnectivityAmphibian(pos,1,-1,1,0,0,-1)
        --ScenarioInfo.DilliDalliMap.markers[i][j].water.connections[k] = DilliDalliFuncCheckConnectivityWater(pos,1,-1,1,0,0,-1)
        ScenarioInfo.DilliDalliMap.markers[i][j].surf.connections[k] = DilliDalliFuncCheckConnectivitySurface(pos,1,-1,1,0,0,-1)
        --ScenarioInfo.DilliDalliMap.markers[i][j].subs.connections[k] = DilliDalliFuncCheckConnectivitySubmarine(pos,1,-1,1,0,0,-1)
    end
    if j > 1 then
        local k = 4
        ScenarioInfo.DilliDalliMap.markers[i][j].land.connections[k] = DilliDalliFuncCheckConnectivityLand(pos,0,-1,0.5,-0.5,-0.5,-0.5)
        ScenarioInfo.DilliDalliMap.markers[i][j].bed.connections[k] = DilliDalliFuncCheckConnectivityAmphibian(pos,0,-1,0.5,-0.5,-0.5,-0.5)
        --ScenarioInfo.DilliDalliMap.markers[i][j].water.connections[k] = DilliDalliFuncCheckConnectivityWater(pos,0,-1,0.5,-0.5,-0.5,-0.5)
        ScenarioInfo.DilliDalliMap.markers[i][j].surf.connections[k] = DilliDalliFuncCheckConnectivitySurface(pos,0,-1,0.5,-0.5,-0.5,-0.5)
        --ScenarioInfo.DilliDalliMap.markers[i][j].subs.connections[k] = DilliDalliFuncCheckConnectivitySubmarine(pos,0,-1,0.5,-0.5,-0.5,-0.5)
    end
    if i > 1 and j > 1 then
        local k = 5
        ScenarioInfo.DilliDalliMap.markers[i][j].land.connections[k] = DilliDalliFuncCheckConnectivityLand(pos,-1,-1,0,-1,-1,0)
        ScenarioInfo.DilliDalliMap.markers[i][j].bed.connections[k] = DilliDalliFuncCheckConnectivityAmphibian(pos,-1,-1,0,-1,-1,0)
        --ScenarioInfo.DilliDalliMap.markers[i][j].water.connections[k] = DilliDalliFuncCheckConnectivityWater(pos,-1,-1,0,-1,-1,0)
        ScenarioInfo.DilliDalliMap.markers[i][j].surf.connections[k] = DilliDalliFuncCheckConnectivitySurface(pos,-1,-1,0,-1,-1,0)
        --ScenarioInfo.DilliDalliMap.markers[i][j].subs.connections[k] = DilliDalliFuncCheckConnectivitySubmarine(pos,-1,-1,0,-1,-1,0)
    end
    if i > 1 then
        local k = 6
        ScenarioInfo.DilliDalliMap.markers[i][j].land.connections[k] = DilliDalliFuncCheckConnectivityLand(pos,-1,0,-0.5,-0.5,-0.5,0.5)
        ScenarioInfo.DilliDalliMap.markers[i][j].bed.connections[k] = DilliDalliFuncCheckConnectivityAmphibian(pos,-1,0,-0.5,-0.5,-0.5,0.5)
        --ScenarioInfo.DilliDalliMap.markers[i][j].water.connections[k] = DilliDalliFuncCheckConnectivityWater(pos,-1,0,-0.5,-0.5,-0.5,0.5)
        ScenarioInfo.DilliDalliMap.markers[i][j].surf.connections[k] = DilliDalliFuncCheckConnectivitySurface(pos,-1,0,-0.5,-0.5,-0.5,0.5)
        --ScenarioInfo.DilliDalliMap.markers[i][j].subs.connections[k] = DilliDalliFuncCheckConnectivitySubmarine(pos,-1,0,-0.5,-0.5,-0.5,0.5)
    end
    if i > 1 and j < ScenarioInfo.DilliDalliMap.zNum then
        local k = 7
        ScenarioInfo.DilliDalliMap.markers[i][j].land.connections[k] = DilliDalliFuncCheckConnectivityLand(pos,-1,1,-1,0,1,0)
        ScenarioInfo.DilliDalliMap.markers[i][j].bed.connections[k] = DilliDalliFuncCheckConnectivityAmphibian(pos,-1,1,-1,0,1,0)
        --ScenarioInfo.DilliDalliMap.markers[i][j].water.connections[k] = DilliDalliFuncCheckConnectivityWater(pos,-1,1,-1,0,1,0)
        ScenarioInfo.DilliDalliMap.markers[i][j].surf.connections[k] = DilliDalliFuncCheckConnectivitySurface(pos,-1,1,-1,0,1,0)
        --ScenarioInfo.DilliDalliMap.markers[i][j].subs.connections[k] = DilliDalliFuncCheckConnectivitySubmarine(pos,-1,1,-1,0,1,0)
    end
    if j < ScenarioInfo.DilliDalliMap.zNum then
        local k = 8
        ScenarioInfo.DilliDalliMap.markers[i][j].land.connections[k] = DilliDalliFuncCheckConnectivityLand(pos,0,1,-0.5,0.5,0.5,0.5)
        ScenarioInfo.DilliDalliMap.markers[i][j].bed.connections[k] = DilliDalliFuncCheckConnectivityAmphibian(pos,0,1,-0.5,0.5,0.5,0.5)
        --ScenarioInfo.DilliDalliMap.markers[i][j].water.connections[k] = DilliDalliFuncCheckConnectivityWater(pos,0,1,-0.5,0.5,0.5,0.5)
        ScenarioInfo.DilliDalliMap.markers[i][j].surf.connections[k] = DilliDalliFuncCheckConnectivitySurface(pos,0,1,-0.5,0.5,0.5,0.5)
        --ScenarioInfo.DilliDalliMap.markers[i][j].subs.connections[k] = DilliDalliFuncCheckConnectivitySubmarine(pos,0,1,-0.5,0.5,0.5,0.5)
    end
end

function DilliDalliFuncGenerateComponents(i,j)
    for _, s in {"surf", "bed", "land"} do --, "water", "subs", "land"} do
        -- TODO: optimisation - don't create a component for disconnected nodes (e.g. land node over water)
        if ScenarioInfo.DilliDalliMap.markers[i][j][s].component < 0 then
            ScenarioInfo.DilliDalliMap.componentNums[s] = ScenarioInfo.DilliDalliMap.componentNums[s] + 1
            local component = ScenarioInfo.DilliDalliMap.componentNums[s]
            ScenarioInfo.DilliDalliMap.componentSizes[s][component] = 0
            work = {{i=i, j=j}}
            while table.getn(work) > 0 do
                local i0 = work[1].i
                local j0 = work[1].j
                table.remove(work,1)
                if i0 <= 0 or j0<= 0 or i0 > ScenarioInfo.DilliDalliMap.xNum or j0 > ScenarioInfo.DilliDalliMap.zNum or ScenarioInfo.DilliDalliMap.markers[i0][j0][s].component > 0 then
                    continue
                end
                ScenarioInfo.DilliDalliMap.markers[i0][j0][s].component = component
                ScenarioInfo.DilliDalliMap.componentSizes[s][component] = ScenarioInfo.DilliDalliMap.componentSizes[s][component]+1
                if ScenarioInfo.DilliDalliMap.markers[i0][j0][s].connections[1] > 0 then
                    table.insert(work,{i=i0+1, j=j0+1})
                end
                if ScenarioInfo.DilliDalliMap.markers[i0][j0][s].connections[2] > 0 then
                    table.insert(work,{i=i0+1, j=j0})
                end
                if ScenarioInfo.DilliDalliMap.markers[i0][j0][s].connections[3] > 0 then
                    table.insert(work,{i=i0+1, j=j0-1})
                end
                if ScenarioInfo.DilliDalliMap.markers[i0][j0][s].connections[4] > 0 then
                    table.insert(work,{i=i0, j=j0-1})
                end
                if ScenarioInfo.DilliDalliMap.markers[i0][j0][s].connections[5] > 0 then
                    table.insert(work,{i=i0-1, j=j0-1})
                end
                if ScenarioInfo.DilliDalliMap.markers[i0][j0][s].connections[6] > 0 then
                    table.insert(work,{i=i0-1, j=j0})
                end
                if ScenarioInfo.DilliDalliMap.markers[i0][j0][s].connections[7] > 0 then
                    table.insert(work,{i=i0-1, j=j0+1})
                end
                if ScenarioInfo.DilliDalliMap.markers[i0][j0][s].connections[8] > 0 then
                    table.insert(work,{i=i0, j=j0+1})
                end
            end
        end
    end
end

function DilliDalliFuncDrawComponentsLand()
    local colours = { 'aa1f77b4', 'aaff7f0e', 'aa2ca02c', 'aad62728', 'aa9467bd', 'aa8c564b', 'aae377c2', 'aa7f7f7f', 'aabcbd22', 'aa17becf' }
    for i=1,ScenarioInfo.DilliDalliMap.xNum do
        for j=1,ScenarioInfo.DilliDalliMap.zNum do
            local connections = 0
            for _, v in ScenarioInfo.DilliDalliMap.markers[i][j].land.connections do
                connections = connections + v
            end
            if connections == 8 then
                continue
            end
            for k=1,8 do
                if ScenarioInfo.DilliDalliMap.markers[i][j].land.connections[k] == 1 then
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
                    if i1 > 0 and j1 > 0 and i1 <= ScenarioInfo.DilliDalliMap.xNum and j1 <= ScenarioInfo.DilliDalliMap.zNum and (ScenarioInfo.DilliDalliMap.componentSizes.land[ScenarioInfo.DilliDalliMap.markers[i][j].land.component] > 10) then
                        DrawLine(ScenarioInfo.DilliDalliMap.markers[i][j].pos,ScenarioInfo.DilliDalliMap.markers[i1][j1].pos,colours[math.mod(ScenarioInfo.DilliDalliMap.markers[i][j].land.component-1,table.getn(colours))+1])
                    end
                end
            end
        end
    end
end

function DilliDalliFuncCheckConnectivitySurface(pos,xdelta,zdelta,orthX0,orthZ0,orthX1,orthZ1)
    local maxSlope = 0.5 -- Slope = ydiff/distance
    local num = 10
    local length = ScenarioInfo.DilliDalliMap.gap*math.sqrt(xdelta*xdelta + zdelta*zdelta)
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
end

function DilliDalliFuncCheckConnectivityLand(pos,xdelta,zdelta,orthX0,orthZ0,orthX1,orthZ1)
    local maxSlope = 0.5 -- Slope = ydiff/distance
    local num = 10
    local length = ScenarioInfo.DilliDalliMap.gap*math.sqrt(xdelta*xdelta + zdelta*zdelta)
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
end

function DilliDalliFuncCheckConnectivityAmphibian(pos,xdelta,zdelta,orthX0,orthZ0,orthX1,orthZ1)
    local maxSlope = 0.5 -- Slope = ydiff/distance
    local num = 10
    local length = ScenarioInfo.DilliDalliMap.gap*math.sqrt(xdelta*xdelta + zdelta*zdelta)
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
end

function DilliDalliFuncCheckConnectivityWater(pos,xdelta,zdelta,orthX0,orthZ0,orthX1,orthZ1)
    --[[local maxSlope = 0.5 -- Slope = ydiff/distance
    local num = 10
    local length = ScenarioInfo.DilliDalliMap.gap*math.sqrt(xdelta*xdelta + zdelta*zdelta)
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
    return 1]]
    -- TODO
    return 0
end

function DilliDalliFuncCheckConnectivitySubmarine(pos,xdelta,zdelta,orthX0,orthZ0,orthX1,orthZ1)
    --[[local maxSlope = 0.5 -- Slope = ydiff/distance
    local num = 10
    local length = ScenarioInfo.DilliDalliMap.gap*math.sqrt(xdelta*xdelta + zdelta*zdelta)
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
    return 1]]
    -- TODO
    return 0
end

