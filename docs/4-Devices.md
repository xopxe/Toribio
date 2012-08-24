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
The device is name _'accelxo'_, and the module is also _'accelxo'_.

### bobot

Uses the bobot library to access the usb4butia modules. A device will
be instantiated for each module. Hotplug is supported. The device's name
and module is defined by bobot. Sample configuration:

    deviceloaders.bobot.load = true
    deviceloaders.bobot.comms = {'usb', 'serial'} --comms services to use
    deviceloaders.bobot.path = '../bobot' --path to bobot library
    deviceloaders.bobot.timeout_refresh = 10

### dynamixel

Provides support for dynamixel servos. Sample configuration:

    deviceloaders.dynamixel.load = true
    deviceloaders.dynamixel.filename = '/dev/ttyUSB0'

It will create a device for the dynamixel bus (named _'dynamixel:/dev/ttyUSB0'_ 
in the example and module _'dynamixel'_), plus a device for each motor (named like 
_'ax12:5'_ and module _'ax'_)

### mice

This device allows you to read a mouse. As it reads from /dev/input/mice, you probably
need to start toribio with sudo.

### filedev

This is a special loader, that watches for a set of files and starts an associated
loader when a file appears. When a file disappears, it will remove all depending devices.

    deviceloaders.filedev.load = true
    deviceloaders.filedev.module.mice = '/dev/input/mice'
    deviceloaders.filedev.module.dynamixel = '/dev/ttyUSB*'
    deviceloaders.filedev.module.accelxo = '/sys/devices/platform/lis3lv02d'

When a file described by the mask appears, filedev will set the "filename" configuration 
parameters for the corresponding task, and start it. Additional parameters for the 
auto-started task can be provided in it's own section, tough the load attribute for it must
not be set.

When fieldev detects a file removal, it will remove all devices that have it in the "filename"
attribute.

Filedev uses the tasks/inotifier.lua task, and therefore depends on the inotifywait program.

## Accessing devices

Devices are available trough the toribio.devices table, or using the 
`toribio.wait_for_device(name|filter)` method.

To iterate all devices, you can do:

    for name,device in pairs(toribio.devices)do
    	print(name, device.module)
    end

This will print out all the devices, with their name and what 
type (module) are they.

If you know the name of the object, you can retrieve it directly.
Some devices can be detected after your task started,
so instead of going directly to the table you can use the 
`toribio.wait_for_device(name)` method. If the given device exists, 
it will be returned immediately. Otherwise the call will block 
until said device appears.

    local mice = toribio.wait_for_device('mice:/dev/input/mice')

You can also retrieve devices providing a table containing a filter the 
device must match. For example, if you are interested in a dynamixel 
motor connected to a particular serial bus, you can do:

    local motor =  toribio.wait_for_device({
    	module = 'ax',
    	filename = '/dev/ttyUSB1'
    })

Some devices can connect and disconnect at runtime. If you're 
interested in these events, you can listen for the _'new\_device'_ and
_'removed\_device'_ events. For example:

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

Device's type. For example it can be "mice" for a mouse or "bb-dist" 
for a distance sensor.

* device.task

If the device has a long-running task associated, it will be 
available here. This is also the task that emits device's events.

* device.signals

A table containing the signals that the device can emit. The key is the
name of the signal.

* device.filename

If the device depends on a device file, it will be here.

* device:register_callback(...)

OO-styled synonym for `toribio.register_callback(device, ...)`

### device-dependant fields

Each device will have a set of methods that allow to manipulate 
the device. Usually all devices with equal module will have the 
same methods. For example a device with module "bb-dist" could
have a `device.get_distance()` method.

## Creating your own devices.

Besides representing pieces of hardware, a Device can represent an 
abstract service. The use can define it own device modules. For that
it must instantiate a table with the appropriate structure, and feed it to 
Toribio using `toribio.add_device(device)`. This will allow other tasks
to easily request it (using `toribio.wait_for_device`), and register callbacks
(using `toribio.wait_for_device`).




