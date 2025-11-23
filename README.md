# USB-Soft-KVM

A lightweight software solution that provides KVM-like functionality by automatically switching your monitor's input source based on which computer your USB keyboard is connected to, allowing full KVM switching with a simple USB switch.

## What It Does

USB-Soft-KVM monitors the connection status of a specific USB keyboard and automatically switches your monitor's display input when you use a physical USB switch. When you press the button on your USB switch to move your keyboard (and other peripherals) between computers, your monitor automatically follows, switching to the corresponding video input.

## Use Case

Perfect for users with:
- **Two computers** sharing one monitor (e.g., a laptop and desktop)
- **Multiple video inputs** on the monitor (HDMI, DisplayPort, etc.)
- **A USB switch** to toggle keyboard/mouse between computers
- **No traditional KVM** or desire for a simpler, software-based solution

Instead of manually switching your monitor's input every time you toggle your USB switch, this service handles it automatically.

## How It Works

1. udev rules monitor USB device events on the Desktop PC
2. USB switch connects keyboard to either Laptop or Desktop
3. Keyboard connects to Desktop → udev triggers DDC/CI command → Monitor switches to DisplayPort
4. Keyboard disconnects from Desktop → udev triggers DDC/CI command → Monitor switches to HDMI (Laptop)
5. Monitor switching happens instantly via DDC/CI protocol over I2C

## Requirements

- **Hardware:**
  - Monitor with DDC/CI support (most modern monitors)
  - USB switch (either multi-port or bidirectional)
  - I2C bus access on the desktop PC
  
- **Software:**
  - Linux system (tested on Ubuntu/Debian)
  - `ddccontrol` package
  - `i2c-dev` kernel module
  - `dialog` package (for installer)

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  ┌────────────┐                            ┌──────────────┐    │
│  │ Laptop     │                            │ Desktop      │    │
│  │ (Other PC) │                            │ (This PC)    │    │
│  └─┬───┬──────┘                            │ ┌──────────┐ │    │   1: Monitor USB to
│    │   │                                   │ │ USB    ──┼─┼────┼─►    detect keyboard
│    │   │                                   │ │   Soft   │ │    │   2: Send DCC signal
│    │   │  HDMI   ┌───────────────┐    DP   │ │     KVM  │ │    │      to switch input
│    │   └────────►│               │◄────────┤ └───┬──────┘ │    │
│    │             │    Monitor    │         └─────┼────┬───┘    │
│    │             │               │               │    │        │
│    │             └───────▲───────┘               │    │        │
│    │ USB                 │                       │    │ USB    │
│    │                     │ I2C/DDC Control       │    │        │
│    │                     │ (Switch input source) │    │        │
│    │                     └───────────────────────┘    │        │
│    │                                                  │        │
│    │             ┌─────────────────┐                  │        │
│    └────────────►│ USB Switch      │◄─────────────────┘        │
│                  │ (Toggle button) │                           │
│                  └───────┬─────────┘                           │
│                          │                                     │
│                          │ USB                                 │
│                          │                                     │
│            ┌─────────────┴──────────────┐                      │
│            │   (optionally a USB hub)   │                      │
│        ┌───▼──────┐               ┌─────▼───┐                  │
│        │ Keyboard │               │  Mouse  │                  │
│        └──────────┘               └─────────┘                  │
│                                                                │
└────────────────────────────────────────────────────────────────┘

When keyboard is CONNECTED → Switch to DisplayPort (Desktop)
When keyboard is DISCONNECTED → Switch to HDMI (Laptop)
```

## Quick Installation

Run the interactive script which will guide you through the configuration:

```bash
./usb-soft-kvm.sh
```

Select "Install or Reinstall" from the menu. The installer will:
1. Detect your monitor's I2C bus
2. Show available input sources and let you select which to use
3. Detect your USB keyboard
4. Install udev rules to trigger automatic switching

## Manual Installation (if needed)

If you prefer manual configuration or the installer doesn't work:

### 1. Install Prerequisites

```bash
sudo apt-get install ddccontrol dialog
sudo modprobe i2c-dev
sudo sh -c 'echo "i2c-dev" >> /etc/modules'
```

### 2. Identify Your I2C Bus

```bash
sudo ddccontrol -p
```

Look for your monitor's device path (e.g., `/dev/i2c-12`).

### 3. Identify Input Source Values

The same `ddccontrol -p` output shows available inputs:

```
> Input settings
        > Input sources
                  Possible values:
                        > id=dp1 - name=DP-1, value=15
                        > id=hdmi1 - name=HDMI-1, value=17
```

Note which values correspond to your desktop and laptop connections.

### 4. Identify Your Keyboard

```bash
lsusb
```

Find your keyboard and note its Vendor ID and Product ID. For example:
```
Bus 001 Device 010: ID 04d9:a055 Holtek Semiconductor, Inc.
```
Here: Vendor ID = `04d9`, Product ID = `a055`

### 5. Create udev Rules

Create `/etc/udev/rules.d/90-usb-soft-kvm.rules`:

```
ACTION=="add", ATTRS{idVendor}=="04d9", ATTRS{idProduct}=="a055", RUN+="/bin/sh -c '/usr/bin/ddccontrol -r 0x60 -w 15 dev:/dev/i2c-12; /usr/bin/logger \"USB-Soft-KVM: Keyboard connected - switched to input 15 (Desktop)\"'"
ACTION=="remove", ATTRS{idVendor}=="04d9", ATTRS{idProduct}=="a055", RUN+="/bin/sh -c '/usr/bin/ddccontrol -r 0x60 -w 17 dev:/dev/i2c-12; /usr/bin/logger \"USB-Soft-KVM: Keyboard disconnected - switched to input 17 (Laptop)\"'"
```

Replace `04d9`, `a055`, `15`, `17`, and `/dev/i2c-12` with your values.

### 6. Reload udev

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## Testing

Unplug and replug your USB keyboard. The monitor should switch inputs automatically.

View logs:
```bash
journalctl -f | grep "USB-Soft-KVM"
```

## Uninstallation

To remove USB-Soft-KVM:

```bash
./usb-soft-kvm.sh
```

Select "Uninstall" from the menu. This will remove the udev rules.

## Troubleshooting

**Monitor not switching:**
- Check if udev rules are loaded: `cat /etc/udev/rules.d/90-usb-soft-kvm.rules`
- Test ddccontrol manually: `sudo ddccontrol -r 0x60 -w 17 dev:/dev/i2c-12`
- Check logs: `journalctl -f | grep "USB-Soft-KVM"`
- Verify keyboard IDs: `lsusb`

**Permission issues:**
- Ensure i2c-dev module is loaded: `lsmod | grep i2c_dev`
- Check i2c device permissions: `ls -l /dev/i2c-*`

**Udev rules not triggering:**
- Reload rules: `sudo udevadm control --reload-rules && sudo udevadm trigger`
- Test manually: `sudo udevadm test --action=add /sys/bus/usb/devices/[your-device]`

## Advanced Configuration

The udev-based system creates this file:
- `/etc/udev/rules.d/90-usb-soft-kvm.rules` - udev rules with inline commands

You can manually edit this file to customize behavior, such as:
- Adding notification sounds
- Triggering additional commands
- Adjusting timing with different sleep values