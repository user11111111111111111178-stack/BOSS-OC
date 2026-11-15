#!/bin/bash
# Boss OS 0.1 - ISO build script (runs inside a debian:trixie container)
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

W=/work
mkdir -p "$W/out" "$W/logs"
trap 'cp /build/build.log "$W/logs/" 2>/dev/null || true; chown -R "${HOST_UID:-0}" "$W/out" "$W/logs" 2>/dev/null || true' EXIT

apt-get update
apt-get install -y --no-install-recommends \
  live-build debootstrap squashfs-tools xorriso mtools dosfstools cpio \
  syslinux syslinux-common syslinux-utils isolinux \
  grub-pc-bin grub-efi-amd64-bin grub-common \
  imagemagick ca-certificates gnupg xz-utils rsync file

IM=$(command -v magick || command -v convert)

rm -rf /build && mkdir -p /build && cd /build

lb config \
  --distribution trixie \
  --architectures amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --apt-recommends false \
  --debian-installer none \
  --binary-images iso-hybrid \
  --chroot-squashfs-compression-type xz \
  --iso-application "Boss OS" \
  --iso-publisher "Boss OS" \
  --iso-volume "BOSSOS" \
  --image-name "boss-os" \
  --bootappend-live "boot=live components quiet splash username=boss user-fullname=Boss hostname=boss-os"

# ---------- packages ----------
mkdir -p config/package-lists
cat > config/package-lists/bos.list.chroot <<'EOF'
kde-plasma-desktop
sddm
plasma-nm
plasma-pa
pipewire-audio
network-manager
bluez
bluedevil
dolphin
konsole
kwrite
ark
gwenview
okular
kcalc
spectacle
firefox-esr
sudo
xdg-user-dirs
locales
fonts-noto-core
fonts-noto-color-emoji
plymouth
firmware-linux
firmware-iwlwifi
firmware-realtek
firmware-atheros
firmware-misc-nonfree
calamares
calamares-settings-debian
grub-common
grub-pc-bin
grub-efi-amd64-bin
os-prober
efibootmgr
EOF

# ---------- branding files ----------
INC=config/includes.chroot
mkdir -p $INC/usr/share/plymouth/themes/bos $INC/usr/share/backgrounds \
         $INC/usr/local/bin $INC/etc/xdg/autostart $INC/etc/skel/Desktop \
         $INC/usr/share/icons/hicolor/256x256/apps $INC/usr/share/boss-os

T=$INC/usr/share/plymouth/themes/bos
cp "$W/logo.png" "$W/word.png" "$T/"
"$IM" -size 400x4 xc:'rgba(255,255,255,0.18)' "$T/bar-bg.png"
"$IM" -size 4x400 gradient:'#37e6ff-#8b6cff' -rotate -90 "$T/bar-fg.png"

# wallpaper
"$IM" -size 1920x1080 gradient:'#070a1c-#2b1a66' \
  \( "$W/logo.png" -resize 440x \) -gravity center -geometry +0-70 -composite \
  \( "$W/word.png" -resize 340x \) -gravity center -geometry +0+190 -composite \
  $INC/usr/share/backgrounds/boss-os.png

# app icon
"$IM" "$W/logo.png" -background none -resize 256x256 -gravity center -extent 256x256 \
  $INC/usr/share/icons/hicolor/256x256/apps/boss-os.png

# Plymouth boot animation
cat > $T/bos.plymouth <<'EOF'
[Plymouth Theme]
Name=Boss OS
Description=Boss OS boot animation
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/bos
ScriptFile=/usr/share/plymouth/themes/bos/bos.script
EOF

cat > $T/bos.script <<'EOF'
Window.SetBackgroundTopColor(0.027, 0.039, 0.110);
Window.SetBackgroundBottomColor(0.027, 0.039, 0.110);

sw = Window.GetWidth();
sh = Window.GetHeight();
unit = Math.Min(sw, sh);

img = Image("logo.png");
lw = unit * 0.36;
lh = lw * img.GetHeight() / img.GetWidth();
logo = Sprite(img.Scale(lw, lh));
logo.SetX(sw / 2 - lw / 2);
logo.SetY(sh / 2 - lh * 0.85);
logo.SetOpacity(0);

wimg = Image("word.png");
ww = unit * 0.38;
wh = ww * wimg.GetHeight() / wimg.GetWidth();
word = Sprite(wimg.Scale(ww, wh));
word.SetX(sw / 2 - ww / 2);
word.SetY(sh / 2 + lh * 0.2);
word.SetOpacity(0);

bw = unit * 0.40;
bh = Math.Max(3, unit * 0.005);
bx = sw / 2 - bw / 2;
by = sh / 2 + lh * 0.2 + wh + unit * 0.06;
bgimg = Image("bar-bg.png");
bar_bg = Sprite(bgimg.Scale(bw, bh));
bar_bg.SetPosition(bx, by, 1);
bar_bg.SetOpacity(0);
fgimg = Image("bar-fg.png");
bar_fg = Sprite();
bar_fg.SetPosition(bx, by, 2);
bar_fg.SetOpacity(0);

progress = 0;
frame = 0;

fun refresh() {
  global.frame = global.frame + 1;
  t = global.frame / 50;
  fade = Math.Min(1, t / 1.8);
  pulse = 0.9 + 0.1 * Math.Sin(t * 2.4);
  global.logo.SetOpacity(fade * pulse);
  global.word.SetOpacity(Math.Max(0, Math.Min(1, (t - 1.0) / 1.2)));
  barop = Math.Max(0, Math.Min(1, (t - 1.8) / 0.8));
  global.bar_bg.SetOpacity(barop);
  global.bar_fg.SetOpacity(barop);
  w = Math.Max(1, Math.Int(global.bw * global.progress));
  global.bar_fg.SetImage(global.fgimg.Scale(w, global.bh));
}
Plymouth.SetRefreshFunction(refresh);

fun on_progress(duration, p) {
  global.progress = p;
}
Plymouth.SetBootProgressFunction(on_progress);
EOF

# first-login setup: macOS-style look, glass blur, menu bar + dock (runs once per user)
cat > $INC/usr/local/bin/boss-first-run <<'EOF'
#!/bin/sh
M="$HOME/.config/boss-os-firstrun"
[ -e "$M" ] && exit 0
sleep 6
D=/usr/share/plasma/look-and-feel
pick() { ls "$D" 2>/dev/null | grep -i -m1 -E "$1"; }
LNF=$(pick 'tahoe.*dark'); [ -z "$LNF" ] && LNF=$(pick 'tahoe')
[ -z "$LNF" ] && LNF=$(pick 'whitesur.*dark'); [ -z "$LNF" ] && LNF=$(pick 'whitesur')
[ -z "$LNF" ] && LNF=org.kde.breezedark.desktop
plasma-apply-lookandfeel -a "$LNF" >/dev/null 2>&1 || true
sleep 2
plasma-apply-wallpaperimage /usr/share/backgrounds/boss-os.png >/dev/null 2>&1 || true

ICON=$(ls /usr/share/icons 2>/dev/null | grep -i -m1 -E 'tahoe.*dark|whitesur.*dark|tahoe|whitesur')
if [ -n "$ICON" ]; then
  kwriteconfig6 --file kdeglobals --group Icons --key Theme "$ICON" || true
  CI=$(find /usr/lib /usr/libexec -name plasma-changeicons 2>/dev/null | head -n1)
  [ -n "$CI" ] && "$CI" "$ICON" >/dev/null 2>&1 || true
fi
if fc-list 2>/dev/null | grep -qi 'Inter'; then
  kwriteconfig6 --file kdeglobals --group General --key font "Inter,10,-1,5,50,0,0,0,0,0" || true
fi

# glass effect: window blur
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true || true
kwriteconfig6 --file kwinrc --group Effect-blur --key BlurStrength 9 || true
kwriteconfig6 --file kwinrc --group Effect-blur --key NoiseStrength 3 || true
gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure >/dev/null 2>&1 || true

# macOS-style layout: menu bar on top, floating dock at the bottom
JS="$(cat /usr/share/boss-os/mac-layout.js)"
Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus)
if [ -n "$Q" ]; then
  "$Q" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$JS" >/dev/null 2>&1 || true
else
  gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
    --method org.kde.PlasmaShell.evaluateScript "$JS" >/dev/null 2>&1 || true
fi
mkdir -p "$HOME/.config" && touch "$M"
EOF

cat > $INC/usr/share/boss-os/mac-layout.js <<'EOF'
var old = panels();
for (var i = 0; i < old.length; i++) { old[i].remove(); }

var bar = new Panel();
bar.location = "top";
bar.height = 30;
try { bar.floating = false; } catch (e) {}
var menu = bar.addWidget("org.kde.plasma.kickoff");
menu.currentConfigGroup = ["General"];
menu.writeConfig("icon", "boss-os");
bar.addWidget("org.kde.plasma.appmenu");
bar.addWidget("org.kde.plasma.panelspacer");
bar.addWidget("org.kde.plasma.systemtray");
bar.addWidget("org.kde.plasma.digitalclock");

var dock = new Panel();
dock.location = "bottom";
dock.height = 64;
try { dock.alignment = "center"; } catch (e) {}
try { dock.lengthMode = "fit"; } catch (e) {}
try { dock.floating = true; } catch (e) {}
try { dock.hiding = "dodgewindows"; } catch (e) {}
var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
  "applications:firefox-esr.desktop",
  "applications:org.kde.dolphin.desktop",
  "applications:org.kde.konsole.desktop",
  "applications:systemsettings.desktop",
  "applications:org.kde.systemsettings.desktop"
]);
EOF

cat > $INC/etc/xdg/autostart/boss-first-run.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Boss OS first run
Exec=/usr/local/bin/boss-first-run
OnlyShowIn=KDE;
NoDisplay=true
EOF

cat > $INC/etc/skel/Desktop/install-boss-os.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Install Boss OS
Comment=Install Boss OS on this computer
Exec=sudo -E env QT_QPA_PLATFORM=xcb calamares
Icon=boss-os
Terminal=false
Categories=System;
EOF

# ---------- macOS-style themes (downloaded from GitHub at build time) ----------
mkdir -p config/hooks/live config/hooks/normal
cat > config/hooks/live/9980-bos-themes.hook.chroot <<'EOF'
#!/bin/bash
[ -e /var/lib/bos-themes-done ] && exit 0
export DEBIAN_FRONTEND=noninteractive HOME=/root
apt-get update || true
for p in git ca-certificates fonts-inter qt6-style-kvantum qt5-style-kvantum librsvg2-bin; do
  apt-get install -y --no-install-recommends "$p" || true
done
rm -rf /tmp/th && mkdir -p /tmp/th && cd /tmp/th
for r in MacTahoe-kde MacTahoe-icon-theme WhiteSur-kde WhiteSur-icon-theme WhiteSur-cursors; do
  if git clone --depth 1 "https://github.com/vinceliuice/$r.git" "$r" </dev/null; then
    (cd "$r" && bash ./install.sh </dev/null) || echo "theme $r failed, skipping"
  fi
done
cd / && rm -rf /tmp/th
touch /var/lib/bos-themes-done
exit 0
EOF
cp config/hooks/live/9980-bos-themes.hook.chroot config/hooks/normal/9980-bos-themes.hook.chroot

# ---------- chroot hook (runs inside the new system) ----------
HOOK=bos-branding.hook.chroot
mkdir -p config/hooks/live config/hooks/normal
cat > config/hooks/live/9990-$HOOK <<'EOF'
#!/bin/sh
set -e
chmod +x /usr/local/bin/boss-first-run /etc/skel/Desktop/install-boss-os.desktop || true

sed -i 's/^NAME=.*/NAME="Boss OS"/; s/^PRETTY_NAME=.*/PRETTY_NAME="Boss OS 0.1"/' /usr/lib/os-release || true
printf 'Boss OS 0.1 \\n \\l\n\n' > /etc/issue || true

# Installer branding
for f in $(find /etc /usr/share -name branding.desc -path '*calamares*' 2>/dev/null); do
  sed -i -E 's/^(\s*(productName|shortProductName|versionedName|shortVersionedName):\s*).*/\1Boss OS/; s/^(\s*bootloaderEntryName:\s*).*/\1BossOS/' "$f" || true
done

# Boot animation
plymouth-set-default-theme bos || true
update-initramfs -u -k all || true
EOF
cp config/hooks/live/9990-$HOOK config/hooks/normal/9990-$HOOK
chmod +x config/hooks/live/* config/hooks/normal/*

# ---------- build ----------
lb build 2>&1 | tee build.log

ISO=$(ls -1 *.iso | head -n1)
cp "$ISO" "$W/out/Boss-OS-0.1-amd64.iso"
ls -lh "$W/out"
