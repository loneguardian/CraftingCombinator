solve the following issues before 0.2.2 release:

1. evaluate the need of having to index potentially non-existent keys in `update assembler` (clone - assembler before cc -> update assembler -> triggers cc entity check -> `key-not-found` handler) and `housekeeping` (to find orphans). Either to:
	- rewrite logic to avoid indexing non-existent keys OR
	- use rawget but less performant - probably needed in housekeeping

2. infinity loop in:

	`key-not-found` handler -> housekeeping -> line 180 -> loop to index global data for all cc entities (to create cc/rc state if orphan found) -> index action triggers `key-not-found` handler

	- break `housekeeping.clear()` into smaller parts that can be used by `key-not-found` handler

```
The mod Space Exploration (0.6.89) caused a non-recoverable error.
Please report this error to the mod author.

Error while running event space-exploration::on_tick (ID 0)
The mod Crafting Combinator Xeraph's Fork (0.2.2) caused a non-recoverable error.
Please report this error to the mod author.

Error while running event crafting_combinator_xeraph::on_entity_cloned (ID 123)
__crafting_combinator_xeraph__/control.lua:34: C stack overflow
stack traceback:
	__crafting_combinator_xeraph__/control.lua:34: in function 'on_key_not_found'
	__crafting_combinator_xeraph__/control.lua:41: in function '__index'
	__crafting_combinator_xeraph__/script/housekeeping.lua:180: in function 'cleanup'
	__crafting_combinator_xeraph__/control.lua:36: in function 'on_key_not_found'
	__crafting_combinator_xeraph__/control.lua:41: in function '__index'
	__crafting_combinator_xeraph__/script/housekeeping.lua:180: in function 'cleanup'
	__crafting_combinator_xeraph__/control.lua:36: in function 'on_key_not_found'
	__crafting_combinator_xeraph__/control.lua:41: in function '__index'
	__crafting_combinator_xeraph__/script/housekeeping.lua:180: in function 'cleanup'
	__crafting_combinator_xeraph__/control.lua:36: in function 'on_key_not_found'
	...
	__crafting_combinator_xeraph__/script/housekeeping.lua:180: in function 'cleanup'
	__crafting_combinator_xeraph__/control.lua:36: in function 'on_key_not_found'
	__crafting_combinator_xeraph__/control.lua:41: in function '__index'
	__crafting_combinator_xeraph__/script/housekeeping.lua:180: in function 'cleanup'
	__crafting_combinator_xeraph__/control.lua:36: in function 'on_key_not_found'
	__crafting_combinator_xeraph__/control.lua:41: in function '__index'
	__crafting_combinator_xeraph__/script/housekeeping.lua:180: in function 'cleanup'
	__crafting_combinator_xeraph__/control.lua:36: in function 'on_key_not_found'
	__crafting_combinator_xeraph__/control.lua:41: in function '__index'
	__crafting_combinator_xeraph__/script/cc.lua:195: in function 'update_assemblers'
	__crafting_combinator_xeraph__/control.lua:140: in function <__crafting_combinator_xeraph__/control.lua:125>
stack traceback:
	[C]: in function 'clone_brush'
	__space-exploration__/scripts/spaceship-clone.lua:276: in function 'clone'
	__space-exploration__/scripts/spaceship.lua:622: in function 'launch'
	__space-exploration__/scripts/spaceship.lua:2601: in function 'stop_integrity_check'
	__space-exploration__/scripts/spaceship.lua:2914: in function 'integrity_check_tick'
	__space-exploration__/scripts/spaceship.lua:1719: in function 'spaceship_tick'
	__space-exploration__/scripts/spaceship.lua:2021: in function 'callback'
	__space-exploration__/scripts/event.lua:15: in function <__space-exploration__/scripts/event.lua:13>
```

3. delay `find_chest`, `find_assembler` for all entities cloned to the next tick (or after other mods finished their cloning process - if they decide to implement cloning over multiple ticks) - should help with ups spike during cloning. This way `update_assemblers` should have no reason to pick up cc's with non-existent keys

4. test `housekeeping`
	- create entities using script then run housekeeping and stub mt destroy calls?

5. test `cloning-helper`
	- cloning order permutation test 
	- example permutation generator:

```
function permgen (a, n)
  if n == 0 then
	printResult(a)
  else
	for i=1,n do

	  -- put i-th element as the last one
	  a[n], a[i] = a[i], a[n]

	  -- generate all permutations of the other elements
	  permgen(a, n - 1)

	  -- restore i-th element
	  a[n], a[i] = a[i], a[n]

	end
  end
end