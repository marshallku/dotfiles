#!/bin/bash
sudo cp -r ~/dotfiles/sddm/usr/share/sddm/themes/custom-theme /usr/share/sddm/themes/
sudo cp -r ~/dotfiles/sddm/etc/sddm.conf.d /etc/sddm.conf.d
sudo chown -R root:root /usr/share/sddm/themes/custom-theme
sudo mkdir -p /etc/sddm.conf.d
sudo chown -R root:root /etc/sddm.conf.d
sudo find /usr/share/sddm/themes/custom-theme -type f -exec chmod 644 {} \;
sudo find /usr/share/sddm/themes/custom-theme -type d -exec chmod 755 {} \;
sudo find /etc/sddm.conf.d -type f -exec chmod 644 {} \;
echo "✓ SDDM theme deployed"

