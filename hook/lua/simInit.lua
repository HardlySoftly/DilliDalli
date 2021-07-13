local DilliDalliBeginSession = import('/mods/DilliDalli/lua/AI/DilliDalli/Mapping.lua').BeginSession

local DilliDalliYeOldeBeginSession = BeginSession
function BeginSession()
    DilliDalliYeOldeBeginSession()
    DilliDalliBeginSession()
end

DilliDalliYeOldeCreateResourceDeposit = CreateResourceDeposit
local DilliDalliCreateMarker = import('/mods/DilliDalli/lua/AI/DilliDalli/Mapping.lua').CreateMarker
CreateResourceDeposit = function(t,x,y,z,size)
    DilliDalliCreateMarker(t,x,y,z,size)
    DilliDalliYeOldeCreateResourceDeposit(t,x,y,z,size)
end