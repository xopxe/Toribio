# Install Toribio.

Toribio runs on Lua 5.1, so make sure you have it installed.

Then, install [nixio](https://github.com/Neopallium/nixio). 
If you are on OpenWRT, nixio is already installed. Otherwise, you probably
have to build it from sources. Under Ubuntu, you will need `build-essential`, `liblua5.1-dev` and `libssl-dev` packages. 

    $ git clone https://github.com/Neopallium/nixio.git
    $ cd nixio
    $ make
    $ sudo make install

You can also crosscompile nixio for other platforms. For example `make HOST_CC="gcc -m32" CROSS=arm-linux-gnueabi-` to crosscompile for ARM (you will have to check your toolchain docs).

Then, download the latest version of [Toribio](https://github.com/xopxe/Toribio). You can either get the [tarball](https://github.com/xopxe/Toribio/tarball/master) , or use git:

    $ git clone git://github.com/xopxe/Toribio.git
    $ cd Toribio
    $ git submodule init
    $ git submodule update

Finally, to use the filedev device loader you will need the inotifywait program (on Ubuntu, do a `sudo apt-get install inotify-tools`).

