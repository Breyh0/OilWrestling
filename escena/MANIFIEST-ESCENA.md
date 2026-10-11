# Manifiesto de escena

Generado con `escena/inventario.luau`. **La escena no esta en git**: esto la vigila,
no la respalda. Para restaurar de verdad hay que publicar el place.

Huella: `3218896102`

La huella es el FNV-1a de 32 de este mismo documento con la linea de la huella
sustituida por `(se calcula al final)`. Se puede comprobar en cualquier momento:

```
python -c "d=open('escena/MANIFIEST-ESCENA.md','rb').read(); h=2166136261; [None for b in d if not (h:=((h^b)*16777619)%4294967296)]; print(h)"
```

## Workspace (raiz)

| Objeto | Clase | Objetos | Notas |
|---|---|---|---|
| AmbientacionRomana | Folder | 413 |  |
| ArenaCrowd | Folder | 1561 |  |
| Baseplate | Part | 2 |  |
| BroadcastBooth | Model | 18 | 17 partes, 0 Humanoid, 0 Animation |
| Camera | Camera | 1 |  |
| Colosseum | Model | 8 | 1 partes, 0 Humanoid, 0 Animation |
| ColosseumStructure | Folder | 2311 |  |
| MuroPodio | Part | 1 |  |
| OilWrestlingRing | Model | 774 | 737 partes, 0 Humanoid, 0 Animation |
| StadiumEnclosure | Model | 13 | 11 partes, 0 Humanoid, 0 Animation |
| Terrain | Terrain | 1 |  |

**Total en Workspace: 5103 objetos**

## OilWrestlingRing

| Parte | Clase | Tamano | Posicion | Material / Color | Texturas |
|---|---|---|---|---|---|
| AnclaFoco | Part Block | 0.2 x 0.2 x 0.2 | 0, 44.0, 0 | Plastic / 0.639216, 0.635294, 0.647059 | ninguna |
| GoldFrame | Part Block | 74.0 x 1.0 x 74.0 | -0, 6.0, 0 | Metal / 0.909804, 0.713726, 0.282353 | ninguna |
| MarbleTier | Part Block | 84.0 x 2.0 x 84.0 | -0, 4.5, 0 | Marble / 0.933333, 0.909804, 0.839216 | ninguna |
| OilAmbientEmitter | Part Block | 66.0 x 20.0 x 66.0 | 0, 17.7, 0 | Plastic / 0.639216, 0.635294, 0.647059 | ninguna |
| OilArena | Part Block | 70.0 x 1.2 x 70.0 | 0, 6.1, 0 | SmoothPlastic / 0.0784314, 0.054902, 0.0352941 | 1 textura(s) |
| OilFilm | Part Block | 69.6 x 0.1 x 69.6 | 0, 6.7, 0 | SmoothPlastic / 0.109804, 0.0784314, 0.0470588 | ninguna |
| PedestalBase | Part Block | 100.0 x 3.0 x 100.0 | -0, 2.0, 0 | Sandstone / 0.784314, 0.690196, 0.533333 | ninguna |

## StarterGui

| ScreenGui | Elementos | Habilitado |
|---|---|---|
| FighterGui | 6 | true |
| GameHUD | 16 | false |
| LoadingScreen | 136 | true |
| MainMenu | 257 | true |
| ProgressionUI | 2 | true |

**Total en StarterGui: 417 objetos**

### MainMenu > Background (hijos directos)

| Nombre | Clase | Tamano | Visible |
|---|---|---|---|
| Banners | Frame | 0 x 0 | true |
| Beams | Frame | 0 x 0 | true |
| CodesPanel | Frame | 480 x 380 | false |
| Corners | Frame | 0 x 0 | true |
| EdgeShade | Frame | 0 x 0 | true |
| Glow | Frame | 0 x 0 | true |
| ModePanel | Frame | 640 x 500 | false |
| Panel | Frame | 440 x 524 | true |
| Particles | Frame | 0 x 0 | true |
| ShopPanel | Frame | 660 x 540 | false |
| UIGradient | UIGradient | - | - |
| Vignette | Frame | 0 x 0 | true |
| Watermark | Frame | 620 x 620 | true |

## Sonidos (SoundService)

| Ruta | SoundId | Volumen | Looped |
|---|---|---|---|
| MusicGroup (grupo) | - | 0.35 | - |
| MusicGroup/BattleMusic | rbxassetid://138780044639987 | 0.50 | true |
| MusicGroup/LobbyMusic | rbxassetid://1836420216 | 0.50 | true |
| SFXGroup (grupo) | - | 0.85 | - |
| SFXGroup/Ambiente (carpeta) |
| SFXGroup/Ambiente/CrowdAmbience | rbxassetid://9119562843 | 0.30 | true |
| SFXGroup/Combate (carpeta) |
| SFXGroup/Combate/ChargeSound | rbxassetid://112670894256968 | 0.70 | false |
| SFXGroup/Combate/CrowdCheer | rbxassetid://102038131931901 | 0.70 | false |
| SFXGroup/Combate/DodgeSound | rbxassetid://136302305612182 | 0.70 | false |
| SFXGroup/Combate/PushSound | rbxassetid://124217526033242 | 0.85 | false |
| SFXGroup/Combate/SplashSlip | rbxassetid://70557734865364 | 0.70 | false |
| SFXGroup/Resultado (carpeta) |
| SFXGroup/Resultado/VictorySound | rbxassetid://122087211247387 | 0.85 | false |
| SFXGroup/Ronda (carpeta) |
| SFXGroup/Ronda/CountdownBeep | rbxassetid://117751546358455 | 0.60 | false |
| SFXGroup/Ronda/WhistleGong | rbxassetid://17798541626 | 0.70 | false |

## FighterTemplate (hitbox)

| Parte | Tamano | Colision | Contacto |
|---|---|---|---|
| Head | 2.0 x 1.0 x 1.0 | true | true |
| HumanoidRootPart | 2.0 x 2.0 x 1.0 | false | true |
| Left Arm | 1.0 x 2.0 x 1.0 | true | true |
| Left Leg | 1.0 x 2.0 x 1.0 | true | true |
| Right Arm | 1.0 x 2.0 x 1.0 | true | true |
| Right Leg | 1.0 x 2.0 x 1.0 | true | true |
| Torso | 2.0 x 2.0 x 1.0 | true | true |
