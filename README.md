# ModelChooser
 A better model chooser for Sourcemod
 
 Tested on HL2DM and Black Mesa, potentially works on other games as well.

## Installation
- Move the config file from corresponding configs folder to your Sourcemod's configs folder
- Move `model_chooser_2020.smx` to your Sourcemod's plugins folder

Older build for SM versions lower than 11 is provided but not maintained - `model_chooser_2020_preSM11.smx`

#### Requirements
- DHooks (Included in Sourcemod 11+)

#### Compile requirements
- SMLib
## Usage
Type !models to enter. Press moveleft or moveright to browse. Press use or jump to exit.

#### Config
- `modelchooser_immunity` (0/1) Whether players have damage immunity / are unable to fire when selecting models

#### Admin commands
- `sm_unlockmodel` Unlock a locked model by name for a player
- `sm_lockmodel` Re-lock a model by name for a player
