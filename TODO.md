solve the following issues before 0.2.2 release:

1. evaluate the need of having to index potentially non-existent keys in `update assembler` (clone - assembler before cc -> update assembler -> triggers cc entity check -> `key-not-found` handler) and `housekeeping` (to find orphans). Either to:
	- rewrite logic to avoid indexing non-existent keys OR
	- use rawget but less performant - probably needed in housekeeping

2. infinity loop in:

	`key-not-found` handler -> housekeeping -> line 180 -> loop to index global data for all cc entities (to create cc/rc state if orphan found) -> index action triggers `key-not-found` handler

	- break `housekeeping.clear()` into smaller parts that can be used by `key-not-found` handler

4. test `housekeeping`
	- create entities using script then run housekeeping and stub mt destroy calls?

5. test `cloning-helper`
	- cloning order permutation test	
	- test data handling