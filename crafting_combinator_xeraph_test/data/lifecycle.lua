local deepcopy = require("__crafting_combinator_xeraph_test__.util").deepcopy

--- stores global references for before_all and after_all
local original = {
    global = nil,
    late_migrations = nil
}

local late_migrations_template = {__migrations = {}, __ordered = {}, __versioned = {}}

--- specs: dummy ConfigurationChangedData
local conf_changed_data = {
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

-- upvalues

local control
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
    -- restore global table reference (required by Testorio after each test)
    global = original.global
end)

after_all(function()
    -- restore references
    global = original.global
    late_migrations = original.late_migrations

    -- on_load to redirect references to original global tables skipping setmetatable()
    control.on_load(true, true)
end)

--- reference to late_migrations.__migrations
local migrations
local migration_count = 5

local function load_migrations()
    late_migrations["0.0.1"] = function() return true end
    late_migrations["0.0.2"] = function() return true end
    late_migrations["0.0.3"] = function() return true end
    late_migrations["random_name"] = function() return true end
    late_migrations["random_name2"] = function() return true end

    assert.are_equal(migration_count, table_size(late_migrations.__migrations))
    migrations = mock(late_migrations.__migrations)
end

---asserts for all tests in this module
local asserts_all = function()
    -- test mt of global cc rc data
    assert.is_truthy(getmetatable(global.cc.data))
    assert.is_truthy(getmetatable(global.rc.data))
end

describe("on_init", function()
    local asserts_on_init = function()
        assert.are_equal(migration_count, table_size(migrations))
        -- assert that no late migration was applied
        for _, migration in pairs(migrations) do
            assert.spy(migration.apply).called(0)
        end 
        asserts_all()
    end

    describe("with migration", function ()
        test("no conf changed", function()
            control.on_init()
            load_migrations() -- migration files are loaded after on_init
            asserts_on_init()
        end)
        
        -- specs for on_init > conf changed
        local conf_changed_tests = {
            {"init only", conf_changed_data.init_only},
            {"remove original", conf_changed_data.init_remove_original},
        }

        describe("conf changed", function ()
            test.each(conf_changed_tests, "%s", function(_, change)
                control.on_init()
                load_migrations()
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

    -- specs for on_load > conf changed
    local conf_changed_tests = {
        {"mod updated", conf_changed_data.load_update},
        {"mod not updated", conf_changed_data.load_other_mod_changes},
        {"no mod changes", conf_changed_data.load_no_mod_changes}
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

    local asserts_migration_applied = function()
        assert.are_equal(migration_count, table_size(migrations))
        -- assert that each migration was applied once
        for _, migration in pairs(migrations) do
            assert.spy(migration.apply).called(1)
        end
        asserts_on_load()
    end

    describe("with migration", function()
        before_each(function ()
            load_migrations() -- migration files are loaded before on_load
        end)

        describe("conf changed", function()
            test.each(conf_changed_tests, "%s", function(_, changes)
                control.on_load()
                control.on_configuration_changed(changes)
                asserts_migration_applied()
            end)
        end)
    end)

    -- scenarios below should not happen
    -- except during dev
    describe("hypothetical", function()
        test.skip("migration only", function() -- conf changed bypassed by not updating version number
            load_migrations()
            control.on_load()
            asserts_migration_applied()
        end)
    end)
end)