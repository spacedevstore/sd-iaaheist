# SpaceDev IAA Heist

An immersive group heist script for FiveM. Infiltrate the subterranean IAA Facility, neutralize smart guards, hack terminal systems, exfiltrate confidential data, and deliver it to an underground buyer.

---

## ⚡ Features

- **Compatibility**: Supports **QBCore**, **Qbox**, and **ESX Legacy**.
- **Inventories**: Works with `ox_inventory`, `qs-inventory`, and standard framework inventories.
- **Tactical Guard AI**: Natural patrol wandering, stealth vision cones, footstep detection, and floor-isolated alarms.
- **Smart Combat**: Guards open fire immediately upon spotting intruders with a 2-second grace period before sounding the floor alarm.
- **Interior Minimap Zoom**: Dynamic radar zoom for seamless bunker navigation.
- **Co-op Group Voting**: Synchronized elevator entry and exit requiring crew consensus.
- **Hacking Minigames**: Interactive security panels, server computers, and download terminals.

---

## 📦 Dependencies

- [howdy-hackminigame](https://github.com/HiHowdy/howdy-hackminigame)
- Framework: `qb-core`, `qbx_core`, or `es_extended`
- Inventory: `ox_inventory`, `qs-inventory`, or framework inventory

---

## 🚀 Installation

1. Place `sd-iaaheist` into your `resources` folder.
2. Add to your `server.cfg`:
   ```cfg
   ensure howdy-hackminigame
   ensure sd-iaaheist
   ```
3. Ensure these items exist in your inventory:
   - `laptop` (Hacking laptop)
   - `trojan_usb` (Infiltration Trojan USB)
   - `usb_data` (Classified Data USB reward)
4. Customize settings (police required, payout, cooldown, guard difficulty) in `config.lua`.

---

## 📜 License
100% Free and Open Source. Created by **SpaceDev**.


