[![CI](https://github.com/Alienmario/ModelChooser/actions/workflows/plugin.yml/badge.svg)](https://github.com/Alienmario/ModelChooser/actions/workflows/plugin.yml)

# ModelChooser
 A better model chooser for Sourcemod.

#### Features
- Third-person model browser
- Custom per-model sounds (all) and animations (hl2dm only)
- Supports skins and bodygroups
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
2. Unpack it in your gameroot folder (hl2mp, bms, ...)
3. Done!

#### Dependencies
- Sourcemod 1.12+
- (Compile+Gamedata) **Alienmario/[StudioHdr](https://github.com/Alienmario/StudioHdr)**
- (Compile+Gamedata) **Alienmario/[smartdm-redux](https://github.com/Alienmario/smartdm-redux)**
- (Compile) **bcserv/[smlib](https://github.com/bcserv/smlib/tree/transitional_syntax)**

#### Usage
Type !models to enter. Press movement keys to browse. Press use or jump to exit.

#### Config
- **modelchooser_immunity** (0/1) Whether players are immune to damage when selecting models. Default: `0`
- **modelchooser_autoreload** (0/1) Whether to reload the model list on mapchanges. Default: `0`
- **modelchooser_sound** Menu click sound (auto downloads supported), empty to disable. Default: `ui/buttonclickrelease.wav`
- **modelchooser_overlay** Screen overlay material to show when choosing models (auto downloads supported), empty to disable. Default: `modelchooser/background`
- **modelchooser_lock_model** Model to display for locked playermodels (auto downloads supported). Default: `models/props_wasteland/prison_padlock001a.mdl`
- **modelchooser_lock_scale** Scale of the lock model. Default: `5.0`

#### Admin commands
- **sm_unlockmodel** Unlock a locked model by name for a player
- **sm_lockmodel** Lock a previously unlocked model by name for a player
