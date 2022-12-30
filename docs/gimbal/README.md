# Camera Gimbal

In the lack of affordable camera solutions, we have decided to build our own. The hardware design is made by an amateur, so contributions to the design will be much welcomed. The gimbal uses a controller called BaseCam SBGC32Tiny, and gimbal motors from T-Motor. BOM can be found at the [bottom of this page](../bom.md#camera-gimbal).

The rest of the mechanical parts are 3D printed, and can be found in the downloaded and printed from these files:

- [Camera mount (.stl)](gimbal-camera-mount.stl)
- [Roll holder (.stl)](gimbal-roll-holder.stl)
- [Forward arm (.stl)](gimba-forward-arm.stl)
- [Main holder (.stl)](gimbal-main-holder.stl)
- [Mount lower plate (.stl)](gimbal-mount-lower-plate.stl)
- [Mount upper plate (.stl)](gimbal-mount-upper-plate.stl)
- [Damper mount (.stl)](gimbal-damper-mount.stl) (x2)
- [Cable distancer (.stl)](gimbal-cable-distancer.stl)

## Software

Download the newest version from: [https://www.basecamelectronics.com/downloads/32bit/](https://www.basecamelectronics.com/downloads/32bit/). This will allow you to load the configuration file, and update the firmware of the controller.

### Configuration

A working configuration file can be found [here](x500-cm4.profile). This file can be loaded into the controller using the BaseCam software.

## Standard

Pixhawk has defined a [standard for payloads](https://pixhawk.org/standards/#payload), which includes camera gimbals. This is very promissing, and something that will be closely monitored into the future, and will replace this description as soon as there are affordable options available on the marked.

## Example

Fully assemmbeled gimbal:

TODO: Add image
