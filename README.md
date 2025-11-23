# USB Soft KVM

A lightweight software solution that provides KVM-like functionality by automatically switching your monitor's input based on which computer your USB keyboard is connected to, allowing full KVM switching with a simple USB switch.

## What It Does

USB Soft KVM monitors the connection status of a specific USB keyboard and automatically switches your monitor's display input when you use a physical USB switch. When you press the button on your USB switch to move your keyboard (and other peripherals) between computers, your monitor automatically follows, switching to the corresponding video input.

## Use Case

Perfect for users with:
- **Two computers** sharing one monitor (e.g., a laptop and desktop)
- **Multiple video inputs** on their monitor (HDMI, DisplayPort, etc.)
- **A USB switch** to toggle keyboard/mouse between computers
- **No traditional KVM** or desire for a simpler, software-based solution

Instead of manually switching your monitor's input every time you toggle your USB switch, this service handles it automatically.

## How It Works

1. Desktop PC runs the monitoring service (this software)
2. USB switch connects keyboard to either Laptop or Desktop
3. Keyboard connects to Desktop → Monitor switches to DisplayPort
4. Keyboard disconnects from Desktop → Monitor switches to HDMI (Laptop)
5. Monitor switching happens via DDC/CI protocol over I2C

## Requirements

- **Hardware:**
  - Monitor with DDC/CI support (most modern monitors)
  - USB switch (either multi-port or bidirectional)
  - I2C bus access on the desktop PC
  
- **Software:**
  - Linux system (tested on Ubuntu/Debian)
  - `ddccontrol` package
  - `i2c-dev` kernel module
  - systemd (for service management)

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

## Prerequisites

1. Install ddccontrol:
   ```bash
   sudo apt-get install ddccontrol
   ```

2. Ensure the i2c device is accessible:
   ```bash
   sudo ddccontrol -p
   ```

3. Load i2c-dev kernel module if needed:
   ```bash
   sudo modprobe i2c-dev
   sudo sh -c 'echo "i2c-dev" >> /etc/modules'
   ```

## Configuration Guide

Before using this service, you need to identify the correct values for your setup.

### 1. Identify Your I2C Bus

First, probe for available monitors:
```bash
sudo ddccontrol -p
```

This will list all detected monitors and their I2C bus addresses. Look for output like:
```
Detected monitors :
 - Device: dev:/dev/i2c-12
   DDC/CI supported: Yes
   Monitor Name: Iiyama GB3461WQSU (DP)
```

Note the device path (e.g., `/dev/i2c-12`). Update the `DEVICE` variable in `monitor-keyboard.sh` with this value.

### 2. Identify Display Input Source Values

To find the correct input source values for HDMI and DisplayPort, run:
```bash
sudo ddccontrol -p
```

This will probe your monitor and list all available input sources with their corresponding values. Look for the input source section in the output and note the values for your HDMI and DisplayPort inputs.

Example output:
```
Detected monitors :
 - Device: dev:/dev/i2c-12
   DDC/CI supported: Yes
   Monitor Name: Iiyama GB3461WQSU (DP)
   Input type: Digital

...

> Input settings
        > Input sources
                > id=inputsource, name=Input Source Select (Main), address=0x60, delay=-1ms, type=2
                  Possible values:
                        > id=dp1 - name=DP-1, value=15
                        > id=dp2 - name=DP-2, value=16
                        > id=hdmi1 - name=HDMI-1, value=17
                        > id=hdmi2 - name=HDMI-2, value=18
                  supported, value=16, maximum=8206
```

In this example, the values are:
- DisplayPort 1: `15`
- DisplayPort 2: `16`
- HDMI 1: `17`
- HDMI 2: `18`

Update the values in `monitor-keyboard.sh`:
- `INPUT_DISCONNECTED`: Set to your HDMI value (for laptop)
- `INPUT_CONNECTED`: Set to your DisplayPort value (for this machine)

### 3. Identify Your Keyboard Name

To find the exact name of your USB keyboard:

1. Unplug your keyboard, then run:
   ```bash
   lsusb > /tmp/before.txt
   ```

2. Plug in your keyboard, then run:
   ```bash
   lsusb > /tmp/after.txt
   diff /tmp/before.txt /tmp/after.txt
   ```

3. The difference will show your keyboard. For example:
   ```
   > Bus 001 Device 010: ID 04d9:a055 Holtek Semiconductor, Inc. HOLTEK USB-HID Keyboard
   ```

4. The keyboard name to use is the text after the ID (e.g., "HOLTEK USB-HID Keyboard").

Alternatively, view all USB devices:
```bash
lsusb
```

And look for your keyboard in the list. Update the `KEYBOARD_NAME` variable in `monitor-keyboard.sh` with the exact name.

## Installation Steps

1. Make the script executable:
   ```bash
   chmod +x monitor-keyboard.sh
   ```

2. Copy the service file to systemd directory:
   ```bash
   sudo cp keyboard-monitor.service /etc/systemd/system/
   ```

3. Update the ExecStart path in the service file if you move the script:
   ```bash
   sudo nano /etc/systemd/system/keyboard-monitor.service
   ```

4. Reload systemd daemon:
   ```bash
   sudo systemctl daemon-reload
   ```

5. Enable the service to start on boot:
   ```bash
   sudo systemctl enable keyboard-monitor.service
   ```

6. Start the service:
   ```bash
   sudo systemctl start keyboard-monitor.service
   ```

## Managing the Service

Check service status:
```bash
sudo systemctl status keyboard-monitor.service
```

View logs:
```bash
sudo journalctl -u keyboard-monitor.service -f
```

Stop the service:
```bash
sudo systemctl stop keyboard-monitor.service
```

Restart the service:
```bash
sudo systemctl restart keyboard-monitor.service
```

Disable the service:
```bash
sudo systemctl disable keyboard-monitor.service
```

## Troubleshooting

- Verify the keyboard name matches exactly:
  ```bash
  lsusb | grep -i holtek
  ```

- Test ddccontrol commands manually:
  ```bash
  sudo ddccontrol -r 0x60 -w 17 dev:/dev/i2c-12
  sudo ddccontrol -r 0x60 -w 16 dev:/dev/i2c-12
  ```

- Check i2c device permissions and availability

## Configuration

You can adjust these variables in `monitor-keyboard.sh`:
- `KEYBOARD_NAME`: The USB device name to monitor
- `DEVICE`: The i2c device path
- `CHECK_INTERVAL`: How often to check connection status (in seconds)
- `INPUT_DISCONNECTED`: Display input value when keyboard is disconnected (HDMI/laptop)
- `INPUT_CONNECTED`: Display input value when keyboard is connected (DisplayPort/this machine)
