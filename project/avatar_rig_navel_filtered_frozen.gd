extends "res://avatar_rig_navel.gd"
## Legacy compatibility wrapper.
##
## The old version reconstructed a navel target with obsolete offsets.
## The corrected base rig now reconstructs one ID0 common pose from permanent
## ID1 chest and ID2 navel, then applies SimplePoseStabilizer once.
