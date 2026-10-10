### Disclaimer: This project is mostly AI coded. I made it a while ago, and I am not interested in producing it now, as I don't want to do with this "slop machine" code. At the same time, it definitely has quite a few flaws. I have no real interest in updating it, and you are invited to make a fork/derivative of it and shape it to your own as you may - that's what FOSS is for after all.

<h1 align="center">
  <br>
  <a href="https://github.com/parkuoa/moonleaf"><img src="./artwork/png/moonleaf2.png" alt="moonleaf" width="150"></a>
  <br>
  moonleaf
  <br>
</h1>
<p align="center">
  <i>✨ The Wallpaper Manager for macOS</i>
</p>

<p align="center">
  <a title="platform" target="_blank" href="https://github.com/parkuoa/moonleaf/releases/latest"><img src="https://img.shields.io/github/v/release/parkuoa/moonleaf?style=flat&color=blue&include_prereleases"></a>
  <img src="https://img.shields.io/badge/macOS-12%2B-2396ED?style=flat&logo=apple&logoColor=white" alt="platform" style="margin-right: 10px;" />
  
  <a href="./LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-899ce8?logo=opensourceinitiative" alt="license" />
  </a>
</p>

<p align="center">
moonleaf is a feature-packed Wallpaper Manager for macOS, with support for gifs, videos, online wallpaper browsing, multi-monitor wallpapers, exporting, among other many things!
</p>

<h1 align="center">
✨ Preview
</h1>
<p align="center">
  <img src="https://github.com/user-attachments/assets/15118fad-306d-4804-b108-462e81fef237" alt="Demo GIF" />
</p>

---

## Installation

**System Requirements:**  
- macOS **12** *(Monterey)* or later
- Silicon/Intel Mac

<br>

## 🍺 Homebrew
```
brew install --cask parkuoa/moonleaf/moonleaf
```
then,
```
xattr -dr com.apple.quarantine /Applications/moonleaf.app
```

## Manual
---
> [!IMPORTANT]
> After downloading and trying to launch the app, you will receive a text saying that it is from an unidentified developer.
> This is because I do not own an Apple Developer account. To fix this:
> 1. Open **System Settings** > **Privacy & Security**
> 2. Scroll down and find the warning about the app
> 3. Click **Open Anyway**
>
> You only need to do this once.

<p align="center">
  <a href="https://github.com/parkuoa/moonleaf/releases/latest/download/moonleaf.dmg" target="_self"><img width="200" src="https://github.com/user-attachments/assets/e2b187d1-8010-45cf-a9d4-e7ce5e2e677c" /></a>
</p>

---

### Disclaimer: I consider this project mostly AI coded slop which I am not interested in producing. I have no high interest in updating it, though I will attempt to continue to do so, but mostly expect bug fixes and alike. Feel free to contribute.

## License
moonleaf is licensed under the [MIT License](./LICENSE). \
Versions pre-v3.0 (macpaper) are licensed under the GNU General Public License v3.0 (GPLv3). 

## 🔨 Building from Source
### Note: to build from source, you must have CLT and Xcode installed.
- Clone the repo
- Run ```scripts/build.sh```, optionally with the --all flag to build for all archs (will default to host arch)

## 🉑️ Translating
Contributing to translation is pretty simple and straightforward -partly because there are not many strings to translate-. Fork the repo, grab the template on the [lang](./lang) folder (or an already existing strings file), and replace the value of the keys with the ones respective to your language. Then, upload the translation to lang/{lang}.lproj and submit a pull request.

It is advised that you, alongside the strings file, place a file named `credit` with a link to your GitHub profile, or just your username.

## 🤝 Thanks to
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch), for README inspiration
- [This post](https://stackoverflow.com/questions/34215527/what-does-launchd-status-78-mean-why-my-user-agent-not-running), because it stopped me from going insane

## 🛠️ Troubleshooting
### Quarantine
If you suspect the app is quarantined, run the following on your Terminal after dragging the app to Applications:
```bash
xattr -l /Applications/moonleaf.app
```
Which shall output ```com.apple.quarantine: ...;{BROWSER};``` if the app IS quarantined.
In that case, run:
```bash
xattr -dr com.apple.quarantine /Applications/moonleaf.app
```

### Apple could not verify "moonleaf" is free of malware...
You can fix this by doing the same steps as [here](https://github.com/parkuoa/moonleaf/tree/main/README.md#installation).

## ❤️ Support me
☕ If you like my work and want to support me, you can do so via Ko-fi:\
https://ko-fi.com/parkuoa
