--[[
    Distribution of jobs to engies based on priorities and location of units
]]

local PROFILER = import('/mods/DilliDalli/lua/FlowAI/framework/utils/Profiler.lua').GetProfiler()

Job = Class({
    Init = function(self, specification)
        self.specification = {
            -- Target amount of mass to spend (rate)
            targetSpend = 0,
            -- Target number of things to build
            count = 0,
            -- Max job duplication
            duplicates = 0,
            -- Requirements for the component to build in
            componentRequirement = nil,
            -- Marker type, nil if no marker required
            markerType = nil,
            -- Blueprint ID of the thing to build
            unitBlueprintID = nil,
            -- Blueprint ID of the builder (nil if no restrictions required)
            builderBlueprintID = nil,
            -- Assist flag
            assist = true,
            -- Max ratio of assisters to builders, -1 => no cap.
            assistRatio = -1,
            -- Location to build at (nil if no location requirements)
            location = nil,
        }
        if specification then
            for k, v in specification do
                self.specification[k] = v
            end
        end

        -- Internally maintained state, but can be accessed by others for feedback
        self.data = {
            -- List of job executors
            executors = {},
            numJobExecutors = 0,
            -- Theoretical spend (assigned builpower * mass rate)
            theoreticalSpend = 0,
            -- Actual spend as measured
            actualSpend = 0,
        }
    end,
})

JobDistributor = Class({
    Init = function(self)
    end,

    AddMobileJob = function(self,markerType)
    end,
})