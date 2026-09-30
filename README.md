# Orbit Drift

Neon space dodge for Android. Drift your craft through asteroid lanes, collect glow orbs for combos, and chase the high score.

**Author:** Vishu  
**Package:** `com.orbitdrift.game`  
**Engine:** Godot 4.3 (GDScript)

## Play

Portrait, one-thumb drag. Tap **PLAY**, steer by dragging, collect cyan orbs for combo multipliers, dodge debris. High score is saved on device.

## Build

Requirements: [Godot 4.3](https://godotengine.org/download/) with Android export templates, JDK 17+, Android SDK.

1. Open this folder in Godot.
2. Project → Export → Android (ARM64-v8a recommended for a smaller APK).
3. Use your own release keystore for Play Store builds (do not commit keystores).

```bash
godot --headless --path . --export-release "Android" OrbitDrift.apk
```

## License

MIT — see [LICENSE](LICENSE).
