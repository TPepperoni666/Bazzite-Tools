⚡ Bazzite Power-Suite

A modular, controller-friendly TUI (Terminal User Interface) suite designed to unlock the full potential of Bazzite OS on handhelds like the Steam Deck and Legion Go.

This tool uses a Hub-and-Spoke architecture: one main launcher that manages independent, powerful scripts for specific tasks.

🚀 Features

Currently Available Modules:

🎥 Boot & Sleep Video Swapper (P10): Easily assign custom .webm videos from your Downloads folder to be your Boot, Suspend, or Throbber animations.

⚔️ Destiny Rising Helper (P24): An automated installer for Destiny: Rising on Waydroid. Handles APK installation, libhoudini checks, and applies the critical Pixel 5 device spoofing required to run the game.

Coming Soon:

☁️ Cloud Save Wrapper: Sync non-Steam PC game saves via Syncthing.

🔁 EmuDeck Auto-Sync: Real-time save syncing for emulators.

🧹 System Janitor: Clean orphaned shader caches and compatdata.

📊 OSD Configurator: Configure MangoHud scaling and layout.

📥 Installation

You do not need to root your device or reboot to use this.

Open a Terminal (Konsole or Ptyxis).

Clone the repository:

git clone https://github.com/TPepperoni666/Bazzite-Tools.git
cd Bazzite-Tools


Make the scripts executable:

chmod +x bazzite_tools.sh scripts/*.sh


Run the suite:

./bazzite_tools.sh


Note: On the first run, the script will automatically download a standalone copy of gum (the interface engine) to a local folder. This keeps your system clean and requires no rpm-ostree layering.

🎮 Controls

The interface is designed for Handheld Controllers:

D-Pad Up/Down: Navigate menus.

A Button (Enter): Select / Confirm.

B Button (Esc): Go Back / Cancel.

🤝 Contributing

This project is built as a collection of independent scripts located in the /scripts folder. If you have a useful Bazzite script, feel free to submit a PR!
