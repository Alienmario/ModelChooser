# ModelChooser
 A better model chooser for Sourcemod.

#### Features
- Third-person model browser
- Custom per-model sounds and animations
- Persistence via cookies
- Extensive configuration
- Admin only and locked models
- Fully automatic downloads
- Scripting API

#### Supported games
- HL2:DM
- Black Mesa

> If you need other games without the custom gamedata requirement, try the **v1 legacy version**.
## Installation
1. Download latest version from the releases page
2. Unpack it in your sourcemod folder
3. Done!

#### Dependencies
- Sourcemod 1.12+
- (Compile+Gamedata) **Natanel-Shitrit/[StudioHdr](https://github.com/Natanel-Shitrit/StudioHdr)**
- (Compile+Gamedata) **Alienmario/[smartdm-redux](https://github.com/Alienmario/smartdm-redux)**
- (Compile) **bcserv/[smlib](https://github.com/bcserv/smlib/tree/transitional_syntax)**

#### Usage
Type !models to enter. Press movement keys to browse. Press use or jump to exit.

#### Config
- **modelchooser_immunity** (0/1) Whether players are immune to damage when selecting models. Default: `0`
- **modelchooser_autoreload** (0/1) Whether to reload model list on mapchanges. Default: `0`
- **modelchooser_lock_model** Model to display for locked playermodels. Default: `models/props_wasteland/prison_padlock001a.mdl`
- **modelchooser_lock_scale** Scale of the lock model. Default: `5.0`

#### Admin commands
- `sm_unlockmodel` Unlock a locked model by name for a player
- `sm_lockmodel` Re-lock a model by name for a player
