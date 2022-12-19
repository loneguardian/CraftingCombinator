local deepcopy = require("__crafting_combinator_xeraph_test__.util").deepcopy

--- specs: grouped dummy ConfigurationChangedData
---
--- {category : {spec name, ConfigurationChangedData}}
local conf_changed_specs = {
    init = {
        { "init only", { mod_changes = {
            crafting_combinator_xeraph = {
                new_version = true
            }
        } } },
        { "original mod removed", { mod_changes = {
            crafting_combinator = {
                old_version = true
            },
            crafting_combinator_xeraph = {
                new_version = true
            }
        } } },
    },
    load = {
        { "mod update", { mod_changes = {
            crafting_combinator_xeraph = {
                old_version = true,
                new_version = true
            }
        } } },
        { "other mod update", { mod_changes = {
            some_random_mod = true
        } } },
        { "no mod changes", {
            mod_changes = {}
        } }
    },
}
-- upvalues

local control
local late_migrations_mt

--- stores global references for setup and teardown
local original = {
    global = nil,
    late_migrations = nil
}
before_all(function()
    control = _ENV.crafting_combinator_xeraph_lifecycle_test

    -- store original references
    original.global = global
    original.late_migrations = late_migrations
    late_migrations_mt = getmetatable(late_migrations)
end)

local late_migrations_template = {__migrations = {}, __ordered = {}, __versioned = {}}
before_each(function()
    -- replace late_migrations table
    late_migrations = setmetatable(deepcopy(late_migrations_template), late_migrations_mt)

    -- replace global table
    global = {}
end)

local mock_tables = {}
after_each(function()
    -- revert mock, release reference
    for k, v in pairs(mock_tables) do
        if v then
            mock.revert(v)
            mock_tables[k] = nil
        end
    end

    -- restore global table reference (required by Testorio after each test)
    global = original.global
    late_migrations = original.late_migrations

    -- reestablish local references to global tables for all modules, skipping setmetatable()
    control.on_load(true, true)
end)

--- functions scoped for all tests

local migration_count = 5
local function load_migrations()
    late_migrations["0.0.1"] = function() return true end
    late_migrations["0.0.2"] = function() return true end
    late_migrations["0.0.3"] = function() return true end
    late_migrations["random_name"] = function() return true end
    late_migrations["random_name2"] = function() return true end

    assert.are_equal(migration_count, table_size(late_migrations.__migrations))
    mock_tables.migrations = mock(late_migrations.__migrations)
end

local on_load = false
local on_tick_event = {name = defines.events.on_tick}
local function on_tick_test()
    if on_load then -- for on_load specs
        -- mock rc cc state metatable
        mock_tables.cc_mt = mock(getmetatable(global.cc.data[1]).__index, true)
        mock_tables.rc_mt = mock(getmetatable(global.rc.data[1]).__index, true)

        local timeout = math.max(control.settings.cc_rate + 1, control.settings.rc_rate + 1)
        local cc_updated = false
        local rc_updated = false
        async(timeout)
        on_tick(function(tick)
            if not cc_updated then
                if #mock_tables.cc_mt.update.calls > 0 then
                    cc_updated = true
                end
            end
            if not rc_updated then
                if #mock_tables.rc_mt.update.calls > 0 then
                    rc_updated = true
                end
            end
            if (cc_updated and cc_updated) then done() end
            if (tick >= timeout) then
                assert.is_true(cc_updated)
                assert.is_true(rc_updated)
                done()
            end
        end)
    else
        on_tick_event.tick = game.tick
        control.on_tick(on_tick_event)
    end
end

---asserts scoped for all tests
local asserts_all = function()
    -- test mt of global cc rc data
    assert.is_truthy(getmetatable(global.cc.data))
    assert.is_truthy(getmetatable(global.rc.data))
    on_tick_test()
end

describe("on_init", function()
    test("without migration", function()
        control.on_init()
        asserts_all()
    end)

    describe("with migration", function ()
        local asserts_on_init_with_migration = function()
            assert.are_equal(migration_count, table_size(mock_tables.migrations))
            -- assert that no late migration was applied
            for _, migration in pairs(mock_tables.migrations) do
                assert.spy(migration.apply).called(0)
            end 
            asserts_all()
        end
        
        test("no conf changed", function()
            control.on_init()
            load_migrations() -- migration files are loaded after on_init
            asserts_on_init_with_migration()
        end)

        describe("conf changed", function ()
            test.each(conf_changed_specs.init, "%s", function(_, change)
                control.on_init()
                load_migrations()
                control.on_configuration_changed(change)
                asserts_on_init_with_migration()
            end)
        end)
    end)
end)

describe("on_load", function()
    before_each(function()
        on_load = true

        control.on_init()
        global = deepcopy(global, true) -- deepcopy without metatables, simulate pre-on_load behaviour

        -- simulate existing cc/rc states
        local cc_state = {}
        global.cc.data[1] = cc_state
        global.cc.ordered[1] = cc_state

        local rc_state = {}
        global.rc.data[1] = rc_state
        global.rc.ordered[1] = rc_state
    end)

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
            test.each(conf_changed_specs.load, "%s", function(_, changes)
                control.on_load()
                control.on_configuration_changed(changes)
                asserts_on_load()
            end)
        end)
    end)

    local asserts_migration_applied = function()
        assert.are_equal(migration_count, table_size(mock_tables.migrations))
        -- assert that each migration was applied once
        for _, migration in pairs(mock_tables.migrations) do
            assert.spy(migration.apply).called(1)
        end
        asserts_on_load()
    end

    describe("with migration", function()
        before_each(function ()
            load_migrations() -- migration files are loaded before on_load
        end)

        describe("conf changed", function()
            test.each(conf_changed_specs.load, "%s", function(_, changes)
                control.on_load()
                control.on_configuration_changed(changes)
                asserts_migration_applied()
            end)
        end)
    end)

    -- scenarios below should not happen
    -- except during dev
    describe("hypothetical", function()
        test.skip("migration only", function() -- no conf changed, bypassed by not updating version number
            load_migrations()
            control.on_load()
            asserts_migration_applied()
        end)
    end)
end)