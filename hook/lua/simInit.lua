local DilliDalliBeginSession = import('/mods/DilliDalli/lua/FlowAI/framework/Mapping.lua').BeginSession
local DilliDalliLoadBPData = import('/mods/DilliDalli/lua/FlowAI/framework/ProductionGraph.lua').LoadBPData
local DilliDalliInitLocations = import('/mods/DilliDalli/lua/FlowAI/framework/production/Locations.lua').InitialiseCoords

local DilliDalliYeOldeBeginSession = BeginSession
function BeginSession()
    DilliDalliYeOldeBeginSession()
    DilliDalliBeginSession()
    DilliDalliLoadBPData()
    DilliDalliInitLocations()
end

DilliDalliYeOldeCreateResourceDeposit = CreateResourceDeposit
local DilliDalliCreateMarker = import('/mods/DilliDalli/lua/FlowAI/framework/Mapping.lua').CreateMarker
CreateResourceDeposit = function(t,x,y,z,size)
    DilliDalliCreateMarker(t,x,y,z,size)
    DilliDalliYeOldeCreateResourceDeposit(t,x,y,z,size)
end

DilliDalliYeOldeSetPlayableRect = SetPlayableRect
local DilliDalliSetPlayableArea = import('/mods/DilliDalli/lua/FlowAI/framework/Mapping.lua').SetPlayableArea
SetPlayableRect = function(minx,maxz,maxx,maxz)
    DilliDalliYeOldeSetPlayableRect(minx,maxz,maxx,maxz)
    DilliDalliSetPlayableArea(minx,maxz,maxx,maxz)
end