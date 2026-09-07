# HiMusic launcher artwork

`app-icon.png` is the approved transparent cartoon home-NAS mascot (design v6).
All native resources are generated from this single source on a warm cream background.

Regenerate from the repository root with Python and Pillow:

```sh
python3 scripts/generate_app_icons.py
```

The TV banner uses Roboto from the local Flutter SDK cache; run `scripts/flutter.sh precache` first if that SDK cache is missing.

Outputs: iOS and macOS AppIcon catalogs, Android density icons and adaptive foregrounds,
Android TV banner, and a Windows ICO containing 16–256px frames. Existing native resource
names are preserved, so the Xcode catalogs and Windows resource file keep their references.
Android adaptive artwork stays within the central safe region. iOS icons are opaque RGB.
The repository currently has no web or Linux runner.
