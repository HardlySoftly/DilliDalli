Job = Class({
    Init = function(self, brain, specification)
        -- 'Specification' for the job, describing exactly what kind of thing should be executed
        self.specification = {
            -- Key against which we charge resource usage
            key = nil,
            -- Target number of things to build - only relevant if location / unit are not specified.
            count = 0,
            -- Production ID of the thing to build.
            productionID = nil,
            -- Assist flag.
            assist = true,
            -- Location to build at (nil if no specific location requirements).
            location = nil,
            -- Whether or not to assign this job.
            active = false,
            -- The utility of doing this job (a scalar value, higher is better).
            utility = 0,
            -- Unit - used by upgrades.
            unit = nil,
            unitFlag = false
        }
        -- Now that we've initialised with some default values, replace with provided values if they exist.
        if specification then
            for k, v in specification do
                self.specification[k] = v
            end
        end
        if self.specification.unit then
            self.specification.unitFlag = true
        else
            self.specification.unitFlag = false
        end

        local bp = GetUnitBlueprintByName(self.specification.unitBlueprintID)

        -- Job state, meddle with this at your peril.
        self.data = {
            -- List of job executors
            executors = {},
            numExecutors = 0,
            -- List of assigned engineers
            assignees = {},
            numAssignees = 0,
            -- Build time
            buildTime = bp.Economy.BuildTime,
            -- Spend rate, useful for guessing at buildpower requirements.
            massSpendRate = bp.Economy.BuildCostMass/bp.Economy.BuildTime,
            -- Stats for measuring the assist ratio effectively.
            totalBuildpower = 0,
            assistBuildpower = 0,
            -- Job category
            category = nil
        }
    end,
})