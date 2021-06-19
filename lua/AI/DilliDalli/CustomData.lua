--[[
    Documentation on what unit CustomData fields are used by DilliDalli, and what they mean.
    
    CustomData.excludeAssignment
        If true, exclude this engineer/factory from being assigned to make things
    
    CustomData.isAssigned
        True while this engineer/factory is assigned to a job
        
    CustomData.assistComplete
        False or nil when this engie isn't assisting, used as a flag to tell the assisting troop function to exit.
        
    CustomData.assigned
        True when assigned to a unit controller
        
]]