local DilliDalliBeginSession = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').BeginSession
local DilliDalliInitLocations = import('/mods/DilliDalli/lua/FlowAI/framework/production/Locations.lua').InitialiseCoords
local DilliDalliLoadProductionGraph = import('/mods/DilliDalli/lua/FlowAI/framework/production/ProductionGraph.lua').LoadProductionGraph

local DilliDalliYeOldeBeginSession = BeginSession
function BeginSession()
    DilliDalliYeOldeBeginSession()
    DilliDalliBeginSession()
    DilliDalliInitLocations()
    DilliDalliLoadProductionGraph()
end

local DilliDalliYeOldeCreateResourceDeposit = CreateResourceDeposit
local DilliDalliCreateMarker = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').CreateMarker
CreateResourceDeposit = function(t,x,y,z,size)
    DilliDalliCreateMarker(t,x,y,z,size)
    DilliDalliYeOldeCreateResourceDeposit(t,x,y,z,size)
end

local DilliDalliYeOldeSetPlayableRect = SetPlayableRect
local DilliDalliSetPlayableArea = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').SetPlayableArea
SetPlayableRect = function(minx,minz,maxx,maxz)
    DilliDalliYeOldeSetPlayableRect(minx,minz,maxx,maxz)
    DilliDalliSetPlayableArea(minx,minz,maxx,maxz)
end