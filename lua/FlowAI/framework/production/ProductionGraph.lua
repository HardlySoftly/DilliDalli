local MAP = import("/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua").GetMap()
local GenerateAdjacentLocations = import("/mods/DilliDalli/lua/FlowAI/framework/production/Locations.lua").GenerateAdjacentLocations

local PRODUCTION_GRAPH = nil
local ENGIE_MOD_FLAG = false

local function BPHasCategory(bp,category)
    if bp and bp.Categories then
        for _, cat in bp.Categories do
            if cat == category then
                return true
            end
        end
    end
    return false
end

local function HasAllCategories(unitCategories, checkCategories)
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

local function CanMake(bp0,bp1)
    local i = 0
    while i < table.getn(bp0.Economy.BuildableCategory) do
        i = i+1
        if HasAllCategories(bp1.Categories,STR_GetTokens(bp0.Economy.BuildableCategory[i]," ")) then
            return true
        end
    end
    return false
end

function LoadProductionGraph()
    if PRODUCTION_GRAPH then
        return
    end
    local START = GetSystemTimeSecondsOnlyForProfileUse()
    PRODUCTION_GRAPH = {}
    local adjacencySizes = {}
    local adjacencySizesDict = {}
    local maxAdjSize = 1
    -- Initialise all nodes
    for k, _ in __blueprints do
        local bp = GetUnitBlueprintByName(k)
        if not bp then
            continue
        end
        -- Initialise universal fields.
        PRODUCTION_GRAPH[k] = {
            bp = bp,
            builds = {},
            buildsN = 0,
            builtBy = {},
            builtByN = 0,
            buildRate = bp.Economy.BuildRate,
            structure = false,
            mobile = false,
        }
        -- Is it mobile or is it a structure?
        for _, cat in bp.Categories do
            if cat == "MOBILE" then
                PRODUCTION_GRAPH[k].mobile = true
            elseif cat == "STRUCTURE" then
                PRODUCTION_GRAPH[k].structure = true
            end
            if cat == "SUPPORTFACTORY" then
                ENGIE_MOD_FLAG = true
            end
        end
        if PRODUCTION_GRAPH[k].structure then
            -- If it is a structure, extract size + layer information.
            PRODUCTION_GRAPH[k].layers = {
                land = bp.Physics.BuildOnLayerCaps.LAYER_Land,
                water = ( -- Can I build this in the water?
                    bp.Physics.BuildOnLayerCaps.LAYER_Water
                    or bp.Physics.BuildOnLayerCaps.LAYER_Seabed
                    or bp.Physics.BuildOnLayerCaps.LAYER_Sub
                )
            }
            PRODUCTION_GRAPH[k].adjacency = (bp.Physics.SkirtSizeX == bp.Physics.SkirtSizeZ)
            if (bp.Physics.SkirtSizeX == bp.Physics.SkirtSizeZ) and (not adjacencySizesDict[tostring(bp.Physics.SkirtSizeX)]) then
                adjacencySizesDict[tostring(bp.Physics.SkirtSizeX)] = true
                table.insert(adjacencySizes,bp.Physics.SkirtSizeX)
                maxAdjSize = math.max(maxAdjSize,bp.Physics.SkirtSizeX)
            end
            for _, cat in bp.Categories do
                -- Size index refers to the index used in 'AdjacencyBuffs.lua'
                if cat == "SIZE4" then
                    PRODUCTION_GRAPH[k].sizeCatIndex = 1
                elseif cat == "SIZE8" then
                    PRODUCTION_GRAPH[k].sizeCatIndex = 2
                elseif cat == "SIZE12" then
                    PRODUCTION_GRAPH[k].sizeCatIndex = 3
                elseif cat == "SIZE16" then
                    PRODUCTION_GRAPH[k].sizeCatIndex = 4
                elseif cat == "SIZE20" then
                    PRODUCTION_GRAPH[k].sizeCatIndex = 5
                else
                    -- Keep looking for size category
                    continue
                end
                -- Size category found, break
                break
            end
        elseif PRODUCTION_GRAPH[k].mobile then
            -- If it is mobile, extract movement layer information.
            PRODUCTION_GRAPH[k].layer = MAP:GetMovementLayerBlueprint(bp)
        else
            -- Seems fine, mostly campaign OP structures (e.g. black sun) or stuff like ferry beacons.
            --WARN("Unit found that is neither a structure or mobile: "..tostring(k).." - "..tostring(bp.Description))
        end
    end
    local n = 0
    local ne = 1

    -- Now to determine what builds what
    for k0, _ in PRODUCTION_GRAPH do
        n = n+1
        local bp0 = PRODUCTION_GRAPH[k0].bp
        if bp0.Economy.BuildableCategory == nil then
            continue
        end
        for k1, _ in PRODUCTION_GRAPH do
            local bp1 = PRODUCTION_GRAPH[k1].bp
            if CanMake(bp0,bp1) then
                PRODUCTION_GRAPH[k0].buildsN = PRODUCTION_GRAPH[k0].buildsN + 1
                PRODUCTION_GRAPH[k0].builds[PRODUCTION_GRAPH[k0].buildsN] = k1
                PRODUCTION_GRAPH[k1].builtByN = PRODUCTION_GRAPH[k1].builtByN + 1
                PRODUCTION_GRAPH[k1].builtBy[PRODUCTION_GRAPH[k1].builtByN] = k0
                ne = ne + 1
            end
        end
    end
    local END = GetSystemTimeSecondsOnlyForProfileUse()
    LOG(string.format('FlowAI framework: Production graph loading finished (%d units, %d edges), runtime: %.2f seconds.', n, ne, END - START ))
    GenerateAdjacentLocations(adjacencySizes,maxAdjSize)
end

function GetProductionGraph()
    -- TODO: attempt to load this fewer times
    if not PRODUCTION_GRAPH then
        LoadProductionGraph()
    end
    return PRODUCTION_GRAPH
end

function IsEngieMod()
    return ENGIE_MOD_FLAG
end