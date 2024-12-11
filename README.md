[![CI](https://github.com/Alienmario/ModelChooser/actions/workflows/plugin.yml/badge.svg)](https://github.com/Alienmario/ModelChooser/actions/workflows/plugin.yml)

# Ultimate ModelChooser
 A "**_better_**" player model chooser for Sourcemod.

#### Features
- Third-person model browser
- Custom per-model sounds (all) and animations (hl2dm only)
- Supports skins and bodygroups
- Persistence via cookies
- Extensive configuration
- Admin only, team-based and locked models
- Fully automatic downloads
- Scripting API

#### Supported games
- HL2:DM
- Black Mesa

> If you need other games without the custom gamedata requirement, try the **v1 legacy version**.

## Installation
1. Download latest version from the [releases page](https://github.com/Alienmario/ModelChooser/releases)
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
| Convar | Default | Description |
| --- | --- | --- |
| **modelchooser_immunity** | `0` | (0/1) Whether players are immune to damage when selecting models |
| **modelchooser_autoreload** | `0` | (0/1) Whether to reload the model list on mapchanges |
| **modelchooser_teambased** | `2` | Configures model restrictions in teamplay mode<br> 0 = Do not enforce any team restrictions<br> 1 = Enforce configured team restrictions, allows picking unrestricted models<br> 2 = Strictly enforce teams, only allows models with matching teams |
| **modelchooser_sound** | `ui/buttonclickrelease.wav` | Menu click sound (auto downloads supported), empty to disable |
| **modelchooser_overlay** | `modelchooser/background` | Screen overlay material to show when choosing models (auto downloads supported), empty to disable |
| **modelchooser_lock_model** | `models/props_wasteland/prison_padlock001a.mdl` | Model to display for locked playermodels (auto downloads supported) |
| **modelchooser_lock_scale** | `5.0` | Scale of the lock model |
| **modelchooser_hudtext_x** | `-1` | Hudtext 1 X coordinate, from 0 (left) to 1 (right), -1 is the center |
| **modelchooser_hudtext_y** | `0.01` | Hudtext 1 Y coordinate, from 0 (top) to 1 (bottom), -1 is the center |
| **modelchooser_hudtext2_x** | `-1` | Hudtext 2 X coordinate, from 0 (left) to 1 (right), -1 is the center |
| **modelchooser_hudtext2_y** | `0.95` | Hudtext 2 Y coordinate, from 0 (top) to 1 (bottom), -1 is the center |
| **modelchooser_forcefullupdate** | `1` | (0/1) Fixes weapon prediction glitch caused by going thirperson, recommended to keep on unless you run into issues |

#### Admin commands
- **sm_unlockmodel** Unlock a locked model by name for a player
- **sm_lockmodel** Lock a previously unlocked model by name for a player
