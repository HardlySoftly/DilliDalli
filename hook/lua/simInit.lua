local DilliDalliBeginSession = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').BeginSession
local DilliDalliLoadProductionGraph = import('/mods/DilliDalli/lua/FlowAI/framework/production/ProductionGraph.lua').LoadProductionGraph

local DilliDalliYeOldeBeginSession = BeginSession
function BeginSession()
    DilliDalliYeOldeBeginSession()
    DilliDalliBeginSession()
    DilliDalliLoadProductionGraph()
end

local DilliDalliYeOldeCreateResourceDeposit = _G.CreateResourceDeposit
local DilliDalliCreateMarker = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').CreateMarker
_G.CreateResourceDeposit = function(t,x,y,z,size)
    DilliDalliCreateMarker(t,x,y,z,size)
    DilliDalliYeOldeCreateResourceDeposit(t,x,y,z,size)
end

local DilliDalliYeOldeSetPlayableRect = _G.SetPlayableRect
local DilliDalliSetPlayableArea = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').SetPlayableArea
_G.SetPlayableRect = function(minx,minz,maxx,maxz)
    DilliDalliYeOldeSetPlayableRect(minx,minz,maxx,maxz)
    DilliDalliSetPlayableArea(minx,minz,maxx,maxz)
end