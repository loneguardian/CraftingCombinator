local control

local original = {
    global = nil,
    late_migrations = nil
}

local late_migrations_template = {__migrations = {}, __ordered = {}, __versioned = {}}

--- dummy ConfigurationChangedData
local change_data = {
    init_only = {
        mod_changes = {
            crafting_combinator_xeraph = {
                new_version = true
            }
        }
    },
    init_remove_original = {
        mod_changes = {
            crafting_combinator = {
                old_version = true
            },
            crafting_combinator_xeraph = {
                new_version = true
            }
        }
    },
    load_update = {
        mod_changes = {
            crafting_combinator_xeraph = {
                old_version = true,
                new_version = true
            }
        }
    },
    load_other_mod_changes = {
        mod_changes = {
            crafting_combinator_xeraph = false
        }
    },
    load_no_mod_changes = {
        mod_changes = {}
    }
}

-- deepcopy function adapted from factorio lualib
local function deepcopy(object, skip_metatable)
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
            -- don't copy factorio rich objects
        elseif object.__self then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        if skip_metatable then
            return new_table
        else
            return setmetatable(new_table, getmetatable(object))
        end
    end

    return _copy(object)
end

local late_migrations_mt

before_all(function()
    control = _G.crafting_combinator_xeraph_lifecycle_test

    -- store original references
    original.global = global
    original.late_migrations = late_migrations
    late_migrations_mt = getmetatable(late_migrations)
end)

before_each(function()
    -- replace late_migrations table
    late_migrations = setmetatable(deepcopy(late_migrations_template), late_migrations_mt)

    -- replace global table
    global = {}
end)

after_each(function()
    -- restore global table reference for Testorio
    global = original.global
end)

after_all(function()
    -- restore references
    global = original.global
    late_migrations = original.late_migrations

    -- on_load to redirect references to original global tables
    control.on_load(true, true)
end)

local function populate_migrations()
    late_migrations["0.0.1"] = function() return true end
    late_migrations["0.0.2"] = function() return true end
    late_migrations["random_name"] = function() return true end
end

---List of asserts for all tests in this module
local asserts_all = function()
    -- test mt of global cc rc data
    assert.is_truthy(getmetatable(global.cc.data))
    assert.is_truthy(getmetatable(global.rc.data))
end

describe("on_init", function()
    local migrations
    local mock_migrations = function()
        migrations = mock(late_migrations.__migrations)
    end
    local asserts_on_init = function()
        -- assert that no late migration was applied
        for _, migration in pairs(migrations) do
            assert.spy(migration.apply).called(0)
        end 
        asserts_all()
    end

    describe("with migration", function ()
        test("no conf changed", function()
            control.on_init()
            populate_migrations() -- migration files are loaded after on_init
            mock_migrations()
            asserts_on_init()
        end)
        
        local conf_changed_tests = {
            {"init only", change_data.init_only},
            {"remove original", change_data.init_remove_original},
        }

        describe("conf changed", function ()
            test.each(conf_changed_tests, "%s", function(_, change)
                control.on_init()
                populate_migrations()
                mock_migrations()
                control.on_configuration_changed(change)
                asserts_on_init()
            end)
        end)
    end)
end)

describe("on_load", function()
    before_each(function()
        control.on_init()
        global = deepcopy(global, true) -- deepcopy without metatables, simulate pre-on_load behaviour

        global.cc.data[1] = {}
        global.rc.data[1] = {} -- simulate existing cc/rc state
    end)

    local conf_changed_tests = {
        {"mod updated", change_data.load_update},
        {"mod not updated", change_data.load_other_mod_changes},
        {"no mod changes", change_data.load_no_mod_changes}
    }

    local asserts_on_load = function()
        -- test mt of cc rc state
        assert.is_truthy(getmetatable(global.cc.data[1]))
        assert.is_truthy(getmetatable(global.rc.data[1]))
        asserts_all()
    end

    describe("without migration", function()
        test("no conf changed", function()
            control.on_load()
            asserts_on_load()
        end)

        describe("conf changed", function()
            test.each(conf_changed_tests, "%s", function(_, changes)
                control.on_load()
                control.on_configuration_changed(changes)
                asserts_on_load()
            end)
        end)
    end)
    
    local migrations
    local mock_migrations = function()
        migrations = mock(late_migrations.__migrations)
    end

    local asserts_migration_applied = function()
        -- assert that each migration was applied once
        for _, migration in pairs(migrations) do
            assert.spy(migration.apply).called(1)
        end
    end

    describe("with migration", function()
        before_each(function ()
            populate_migrations() -- migration files are loaded before on_load
            mock_migrations()
        end)

        describe("conf changed", function()
            test.each(conf_changed_tests, "%s", function(_, changes)
                control.on_load()
                control.on_configuration_changed(changes)
                asserts_migration_applied()
                asserts_on_load()
            end)
        end)
    end)

    -- scenarios below should not happen
    -- except during dev
    describe("hypothetical", function()
        test("migration only", function() -- conf changed bypassed by not updating version number
            populate_migrations()
            mock_migrations()
            control.on_load()
            asserts_migration_applied()
            asserts_on_load()
        end)
    end)
end)