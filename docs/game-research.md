# Research brief: cooperative RV physics games

Research date: 4 October 2026

This document records the design analysis used for the 3D rebuild. It is a feature study, not an asset-extraction or cloning plan. Dustbound Expeditions uses original names, map geometry, characters, props, shaders, UI, code, and generated artwork.

## Verified reference-game pillars

The official Steam listing describes a shared RV driven by up to four players, online co-op, proximity chat, and physics-based front and rear winches. It also highlights light survival activities and character customization:

- <https://store.steampowered.com/app/3949040/RV_There_Yet/>

Developer FAQ and review coverage establish that the reference is a first-person, Unreal Engine 5, hand-authored-map game rather than a procedural driving game:

- <https://steamcommunity.com/app/3949040/discussions/0/811335793676322569/>
- <https://game8.co/articles/reviews/rv-there-yet-review>

Detailed reviews consistently identify the systems that create the co-op stories:

- manual clutch/gears and a heavy, fragile vehicle;
- one driver while other players navigate, recover supplies, repair, and scout;
- loose physical cargo and vehicle parts;
- front/rear winches attached to environmental anchors;
- planks and improvised bridge solutions;
- player health plus layered RV damage;
- garages/checkpoints that support recovery instead of restarting the whole run;
- physical tools for wheels, welding, oil, recovery, and cooking;
- environmental threats and wildlife;
- in-world navigation and proximity voice rather than constant HUD guidance.

Sources:

- <https://savegame.co.uk/rv-there-yet-review-the-chaotic-co-op-road-trip-your-friend-group-needs/>
- <https://gertlushgaming.co.uk/rv-there-yet-co-op-road-trip-review/>
- <https://comicbuzz.com/rv-there-yet-review/>
- <https://gamecritix.co.uk/rv-there-yet-review/>

Route guides show why the map works as a sequence of escalating physics problems: water/ferry traversal, damaged bridge, long ravine, restock garage, narrow canyon, repeated river crossings, and a final exit. Dustbound does **not** reproduce those layouts; it uses the progression principle to build an original route:

- <https://deltiasgaming.com/rv-there-yet-all-checkpoints-guide/>
- <https://powerupgaming.co.uk/2025/10/29/all-checkpoint-locations-in-rv-there-yet/>

## Design translation for mobile

| Reference pillar | Dustbound Expeditions implementation |
|---|---|
| Shared vehicle | One server-authoritative four-wheel RV for the whole crew |
| 1–4 co-op | ENet host/join over LAN or direct IP |
| Proximity chat | Quantized mono microphone packets played through positional 3D audio |
| Manual driving | Reverse, neutral, five forward ratios, steering, braking, fuel and damage |
| Twin winches | Independent front/rear cables, anchor search, tension and pulling force |
| Team roles | Driver, Mechanic, Scout and Navigator labels/loadout identity |
| Physical recovery | Carryable planks, bridge sockets, garages, fuel and checkpoints |
| First-person play | CharacterBody explorer, interaction ray, vehicle entry/exit |
| Hand-authored journey | Original Redmesa Valley route with camp, creek, broken span, garage, mud bog, switchbacks and Route 17 exit |
| Hazards | Ridge boars, impact damage, canyon falls and a triggered rockfall |
| Mobile readability | Large touch targets, twin virtual sticks, compact mission/status HUD |
| Stylized graphics | Original procedural low-poly assets, terrain shader, dynamic sky/fog and generated original key art |

## Quality constraints

Mobile hardware cannot run a desktop UE5 scene unchanged. The Godot renderer therefore uses:

- OpenGL compatibility rendering for broad Android/iOS support;
- an indexed terrain mesh with lower mobile tessellation;
- procedural low-poly props instead of high-overdraw foliage;
- a 2K directional shadow budget;
- no remote textures or runtime downloads;
- 12 kHz mono voice packets to keep four-player bandwidth controlled;
- host-authoritative RV, mission, wildlife, and checkpoint state.

## Intellectual-property boundary

The implementation deliberately excludes the reference game's title, character designs, map geometry, textures, models, audio, dialogue, story, UI, logos, and extracted data. Comparable mechanics and genre conventions are rebuilt with original expression.
