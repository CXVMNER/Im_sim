class_name LadderDismount
extends Marker3D
## Where the player ends up (their FEET) when leaving a ladder. Add as a direct child of a Ladder.
## Same idea as Valve's info_ladder_dismount. Place it on the floor surface where the player
## should stand: free of walls and with headroom, because the player is moved there without
## collision checks.
##
## - Above the ladder's top (or below its bottom): climbing towards it auto-dismounts when you reach the end.
## - Beside the ladder / mid-way: tick `use_key_only`. You look at it and press interact.
## - A ladder with no LadderDismount children falls back to an automatic ledge probe at the top.

## If true this exit is only taken by looking at it and pressing the interact key.
@export var use_key_only := false
