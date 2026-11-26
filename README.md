# WARNING! macOS Sequoia 15.4 is confirmed to entirely break the game!
Do NOT update to 15.4 if you care about Rocksmith 2014 working.
The issue is independent from the patch and also happens on a vanilla unmodified install of the game.

# macOS Tahoe 26 and macOS 27
Players reported the game itself running again on Tahoe 26. Rocksmith 2014 stays an x86_64 app: on Apple Silicon it runs under Rosetta 2, so `uname -m` printing `arm64` is expected.

This tree updates the patch for that setup. The dylib is built as thin x86_64 with a macOS 10.13 deployment target. The installer clears quarantine, ad-hoc signs the tool and the game, and inserts an `@executable_path` load command. It does not turn the hardened runtime on, because library validation would refuse the ad-hoc dylib.

It has not been loaded into Rocksmith on a Mac. Confirm "RSBypass: patched" in Console after you install it.

# RSBypass
Rocksmith 2014 uses a DSA signature to verify the authenticity of songs.
This app is a runtime patch for Rocksmith 2014 OSX which allows playing
custom CDLC content.

See [CustomsForge, How to Add Custom Songs on Mac](https://customsforge.com/index.php/topic/33889-how-to-add-custom-songs-on-mac/?p=81067) for more info.

If you have problems please join the CustomsForge discord server so we can help you make it work!
https://discord.com/invite/cf

Donations: https://paypal.me/starbfly4

Original Injector: https://github.com/rscustom/RSInjector-Mac

## Install

Quit Rocksmith first. Do not use `sudo`.

1. Download the `RSBypass-macos-x86_64` artifact from the GitHub Actions run (or copy a locally built `libRSBypass.dylib` next to `insert_dylib` and `RUN_PATCH_RS.command`).
2. Unzip it. On macOS 26 and later, Gatekeeper can refuse a double-clicked download, so run the script from Terminal:

```bash
cd ~/Downloads/RSBypass-macos-x86_64
xattr -dr com.apple.quarantine .
bash RUN_PATCH_RS.command
```

From a git checkout the script lives in `RSBypass/` and `insert_dylib` is at the repo root. Put `libRSBypass.dylib` in `RSBypass/` and run:

```bash
bash RSBypass/RUN_PATCH_RS.command
```

The script looks up Steam library folders (`libraryfolders.vdf`, app id 221680), including a library on another disk. To force a location:

```bash
RS_PATH="$HOME/Library/Application Support/Steam/steamapps/common/Rocksmith2014/Rocksmith2014.app" bash RSBypass/RUN_PATCH_RS.command
```

`RS_PATH` may be the `.app`, the `Contents/MacOS` directory, or the `Rocksmith2014` executable.

Launch the game from Steam and open a CDLC song. In Console.app, filter for `RSBypass`. A successful load logs `RSBypass: patched`.

## Uninstall

```bash
bash RUN_PATCH_RS.command uninstall
```

That restores the executable and code signature saved under `~/Library/Application Support/RSBypass/`. If there is no backup, use Steam's **Properties → Installed Files → Verify integrity of game files**. Verifying also removes the patch.

## Troubleshooting

- **`uname -m` is `arm64`.** Expected on Apple Silicon. The game and this dylib are x86_64. Do not replace the dylib with an arm64 build.
- **Double-click does nothing, or macOS says the developer cannot be verified.** Run `bash RUN_PATCH_RS.command` from Terminal, as above. macOS 26 keeps a SIP-protected provenance mark on downloaded files; clearing `com.apple.quarantine` does not remove that mark, and right-click Open is no longer a bypass for an unsigned app.
- **`insert_dylib` was built for Mac OS X 12 / `____chkstk_darwin`.** The bundled `insert_dylib` needs macOS 12 or newer. Older systems should use [LEGACY.md](LEGACY.md) and `Legacy_Patch.zip`.
- **Game crashes at launch.** Quit the game and run the installer again. If it still crashes, uninstall or verify files in Steam, then check Console for `RSBypass`. `pattern not found` means this build's signature check did not match. `cannot make ... writable` means the page could not be patched.
- **CDLC still fails the signature check, and Console never shows `RSBypass`.** The dylib did not load. `otool -L` on the game executable should list `@executable_path/libRSBypass.dylib`, and that file must sit in `Contents/MacOS`.
- **`code signature invalid` / the app is damaged.** Re-run the installer so it can ad-hoc sign the executable. Launch from Steam rather than a copied `.app`.
- **Steam replaced the executable.** A verify or update removes the load command. Run the installer again. It keeps a fresh backup of the unpatched file.
- **Sequoia 15.4.** The game itself does not start, patched or not. That is not fixed here.

`DYLD_INSERT_LIBRARIES` is not used. Current macOS ignores that variable for hardened processes. The patch is an `LC_LOAD_DYLIB` command, then an ad-hoc signature without the hardened runtime.

## Building

The dylib has to be x86_64. `ARCHS_STANDARD` on an Apple Silicon Mac is arm64, which will not load into the game.

```bash
xcodebuild -project RSBypass.xcodeproj -scheme RSBypass -configuration Release \
  -derivedDataPath build ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=10.13 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM="" ENABLE_HARDENED_RUNTIME=NO
cp build/Build/Products/Release/RSBypass.dylib RSBypass/libRSBypass.dylib
codesign --force --sign - RSBypass/libRSBypass.dylib
```

GitHub Actions (`.github/workflows/build.yml`) builds that dylib on `macos-latest` and uploads `RSBypass-macos-x86_64`.
