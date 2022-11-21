# Known Issues #
The following is a list of known issues that **cannot** be fixed in a simple manner:

### Blueprint ###
- Issues with undo - cc construction/deconstruction cannot be undone at the moment, and rc settings do not transfer through undo. This is a limitation of the undo API ([basically no API](https://forums.factorio.com/viewtopic.php?f=28&t=100960))
- Unable to transfer settings when updating entity for library blueprints - this is a blueprint API limitation. Workaround is to copy/move the blueprint into the inventory, then update the entities

### Editor ###
- Using "Remove all entities" will cause error - due to the silent-destroy nature of this button (no event is raised), it is not possible to perform the required state changes after the usage of the button. The only way to avoid the error is to:
  1. Not use the button
  2. (Mod author) perform entity validity check before every update cycle - this will incur UPS cost, which is almost equivalent to the current idle UPS cost

-------------

# What am I working on currently? #
1. Optimising entity validity check before every update cycle. Entity validity check, even though costs UPS, will provide a safety net for the mod when cc entities are handled incorrectly by other mods