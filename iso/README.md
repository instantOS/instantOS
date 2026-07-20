# instantOS iso build

## What this is

A fork of the releng archiso profile. 

## How to update this

Manually copy `/usr/share/archiso/configs/releng/` here. 
Then use a git client to figure out what changed upstream, and manually revert
the stuff which got overwritten even though instantOS should have it changed.
Anything interesting which changed upstream will stand out in the git diff. 


