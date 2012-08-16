# Devices.

A device object represent some piece of hardware or service. 
Devices have a unique "name" field, and a "module" field, which
is Device's type.

## Device Loaders

Usually, devices are detected and instantiated by tasks in
the deviceloaders/ directory. To use them, you should enable them
in the toribio-go.conf configuration file.

Some of the deviceloaders are:

### accelxo

Supports the accelerometer installed in the OLPC XO-1.75 laptops. 
The device is name "accelxo", and the module is also "accelxo".

### bobot

Uses the bobot library to access the usb4butia modules. A device will
be instantiated for each module. Hotplug is supported. The device's name
and module is defined by bobot. Sample configuration:

    deviceloaders.bobot.load = true
    deviceloaders.bobot.comms = {"usb", "serial"} --comms services to use

### dynamixel

Provides support for dynamixel servos. Sample configuration:

    deviceloaders.dynamixel.load = true
    deviceloaders.dynamixel.filename = '/dev/ttyUSB0'

It will create a device for the dynamixel bus (named 'dynamixel:/dev/ttyUSB0' 
in the example and module "dynamixel"), plus a device for each motor (named, for example, 
'ax12:5' and module 'ax')

### mice

This device allows you to read a mouse.

### filedev

This is a special loader, that watches for a serie of files and starts an associated
loader when a file appears. When a file dissapears, it will remove all depending devices.

    deviceloaders.filedev.load = true
    deviceloaders.filedev.module.mice = '/dev/input/mice'
    deviceloaders.filedev.module.dynamixel = '/dev/ttyUSB*'
    deviceloaders.filedev.module.accelxo = '/sys/devices/platform/lis3lv02d'

When a file described by the mask appears, filedev will set the "filename" configuration 
parameters for the corresponing task, and start it. Aditional parameters for the 
autostarted task can be provided in it's own section, tough the load atribute for it must
not be set.

When fieldev detects a file removal, it will remove all devices that have it in the filename
attribute.

Filedev uses the tasks/inotifier.lua task, and therefore depends on the inotifywait program.

## Accessing devices

Devices are available trough de toribio.devices table, or using the 
toribio.wait\_for\_device(name) method.

To iterate all devices, you can do:

    for name,device in pairs(toribio.devices)do
    	print(name, device.module)
    end

This will print out all the devices, with their name and what 
type (module) are they.

If you know the name of the object, you can retrieve it directly.
Some devices can be detected after your task started,
so instead of going directly to the table you can use the 
toribio.wait\_for\_device(name) method. If the given device exists, 
it will be returned inmediatelly. Otherwise the call will block 
until said device appears.

    local mice = toribio.wait_for_device('mice:/dev/input/mice')

Some devices can connect and disconnect at runtime. If you're 
interested in these events, you can listen for the 'new\_device' and
'removed\_device' events. For example:

    sched.sigrun(
    	{
    		emitter=toribio.task, 
    		signals={toribio.signals.new_device}
    	}, 
    	function(device) 
    		print('new device!', device.name)
    	end
    )

## Using devices

Devices have a set of common methods and fields, plus methods specific 
to the instance.

### Common fields

* device.name

Device's unique name.

* device.module

Device's type. For example it can be "mice" for a mouse or "dist" 
for a distence sensor.

* device.task

If the device has a long-running task associated, it will be 
available here. This is also the task that emits device's events.

* device.signals

A table containing the signals that the device can emit.

* device.filename

If the device depends on a device file, it will be here.

* device:register_callback()

OO-styled synonim for toribio.register_callback()

### device-dependant fields

Each device will have a set of methods that allow to manipulate 
the device. Usually all evices with equal module will have the 
same methods. For example a device with moule "dist" could
have a device.get_distance() method.

## Creating your own devices.

TODO




