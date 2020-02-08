#!/bin/bash
#GCC Builder and Installer
#Pi 4:Quad-core Cortex-A72 (ARM v8) 64-bit SoC @ 1.5 GHz.
#VideoCore VI 3D:
#ARMv8 Instruction Set
# https://solarianprogrammer.com/2018/05/06/building-gcc-cross-compiler-raspberry-pi/

#Make system current to latest versions
sudo apt update
sudo apt upgrade
sudo apt install build-essential gawk git texinfo bison file wget

# create a working Directory
cd ~
mkdir gcc_all
cd gcc_all

#include dependences for GCC
sudo apt install -y libgmp-dev libmpfr-dev libmpc-dev

# get the current version for building gcc
wget https://ftpmirror.gnu.org/binutils/binutils-2.31.tar.bz2
wget https://ftpmirror.gnu.org/glibc/glibc-2.28.tar.bz2
wget https://ftpmirror.gnu.org/gcc/gcc-8.3.0/gcc-8.3.0.tar.gz
wget https://ftpmirror.gnu.org/gcc/gcc-9.2.0/gcc-9.2.0.tar.gz
git clone --depth=1 https://github.com/raspberrypi/linux

#Untar and remove old files
tar xf binutils-2.31.tar.bz2
tar xf glibc-2.28.tar.bz2
tar xf gcc-8.3.0.tar.gz
tar xf gcc-9.2.0.tar.gz
rm *.tar.*

#GCC also needs some prerequisites
cd gcc-8.3.0
contrib/download_prerequisites
rm *.tar.*
cd ..
cd gcc-9.2.0
contrib/download_prerequisites
rm *.tar.*

#Next, create a folder in which we’ll put the cross compiler and add it to the path:
cd ~/gcc_all
if [ -d /opt/cross-pi-gcc ]
then
#clean up for previous build
rm -R /opt/cross-pi-gcc
fi
sudo mkdir -p /opt/cross-pi-gcc
sudo chown $USER /opt/cross-pi-gcc
export PATH=/opt/cross-pi-gcc/bin:$PATH

#Copy the kernel headers in the above folder
cd ~/gcc_all
cd linux
KERNEL=kernel7l
make ARCH=arm INSTALL_HDR_PATH=/opt/cross-pi-gcc/arm-linux-gnueabihf headers_install

#Next, let’s build Binutils:
cd ~/gcc_all
if [ -d build-binutils ]
then
#clean up for previous build
rm -R build-binutils
fi
mkdir build-binutils
cd build-binutils
../binutils-2.31/configure --prefix=/opt/cross-pi-gcc --target=arm-linux-gnueabihf --with-arch=armv6 --with-fpu=vfp --with-float=hard --disable-multilib
make -j 8
make install

#GCC and Glibc are interdependent, you can’t fully build one without the other,
#so we are going to do a partial build of GCC,
#a partial build of Glibc and finally build GCC and Glibc.
cd ~/gcc_all
if [ -d build-gcc ]
then
#clean up for previous build
rm -R build-gcc
fi
mkdir build-gcc
cd build-gcc
../gcc-8.3.0/configure --prefix=/opt/cross-pi-gcc --target=arm-linux-gnueabihf --enable-languages=c,c++,fortran --with-arch=armv6 --with-fpu=vfp --with-float=hard --disable-multilib
make -j8 all-gcc
make install-gcc

#Now, let’s partially build Glibc
cd ~/gcc_all
if [ -d build-glibc ]
then
#clean up for previous build
rm -R build-glibc
fi
mkdir build-glibc
cd build-glibc
../glibc-2.28/configure --prefix=/opt/cross-pi-gcc/arm-linux-gnueabihf --build=$MACHTYPE --host=arm-linux-gnueabihf --target=arm-linux-gnueabihf --with-arch=armv6 --with-fpu=vfp --with-float=hard --with-headers=/opt/cross-pi-gcc/arm-linux-gnueabihf/include --disable-multilib libc_cv_forced_unwind=yes
make install-bootstrap-headers=yes install-headers
make -j8 csu/subdir_lib
install csu/crt1.o csu/crti.o csu/crtn.o /opt/cross-pi-gcc/arm-linux-gnueabihf/lib
arm-linux-gnueabihf-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o /opt/cross-pi-gcc/arm-linux-gnueabihf/lib/libc.so
touch /opt/cross-pi-gcc/arm-linux-gnueabihf/include/gnu/stubs.h

#Back to GCC
cd ..
cd build-gcc
make -j8 all-target-libgcc
make install-target-libgcc

#Finish building Glibc
cd ..
cd build-glibc
make -j8
make install

#Finish building GCC 8.3.0
cd ..
cd build-gcc
make -j8
make install
cd ..

#Build a test file and test it

echo '// Simple C++ program to display "Hello World"' >test.cpp
echo >> test.cpp
echo '// Header file for input output functions' >> test.cpp
echo '#include<iostream>' >> test.cpp
echo >> test.cpp
echo 'using namespace std;' >> test.cpp
echo >> test.cpp
echo '// main function -' >> test.cpp
echo '// where the execution of program begins' >> test.cpp
echo 'int main()' >> test.cpp
echo '{' >> test.cpp
echo '// prints hello world' >> test.cpp
echo 'cout<<"Hello World";' >> test.cpp
echo >> test.cpp
echo ' return 0;' >> test.cpp
echo '}' >> test.cpp 

arm-linux-gnueabihf-g++ test.cpp -o test

file test
# OUTPUT => test: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter 
#  /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0, not stripped
echo when ready press any key
read var1
#At this point, you have a full cross compiler toolchain with GCC 8.3.0.
sudo cp -r /opt/cross-pi-gcc /opt/cross-pi-gcc-8.3.0
cd ~/gcc_all

#Edit gcc-9.2.0/libsanitizer/asan/asan_linux.cc and add

echo '#ifndef PATH_MAX' > temp.txt
echo '#define PATH_MAX 4096' >> temp.txt
echo '#endif' >> temp.txt
cat gcc-9.2.0/libsanitizer/asan/asan_linux.cc >> temp.txt
cp temp.txt gcc-9.2.0/libsanitizer/asan/asan_linux.cc

#save and close the file

#Next, we are going to use the above built Glibc to build
#a more modern cross compiler that will overwrite GCC 8.3
cd ~/gcc_all
if [ -d build-gcc9 ]
then
#clean up for previous build
rm -R build-gcc9
fi
mkdir build-gcc9
cd build-gcc9
../gcc-9.2.0/configure --prefix=/opt/cross-pi-gcc --target=arm-linux-gnueabihf --enable-languages=c,c++,fortran --with-arch=armv6 --with-fpu=vfp --with-float=hard --disable-multilib
make -j8
make install

#At this point, you can use GCC 9.2 to cross compile any C,
#C++ or Fortran code for your Raspberry Pi.
#You can invoke any of the cross compilers by using the prefix:
## arm-linux-gnueabihf-
# examples: arm-linux-gnueabihf-gcc, arm-linux-gnueabihf-g++, arm-linux-gnueabihf-gfortran.

#In order to stress test our cross compiler, let’s use it to cross compile itself for the Pi:
sudo mkdir -p /opt/gcc-9.2.0
sudo chown $USER /opt/gcc-9.2.0

cd ~/gcc_all
if [ -d build-native-gcc9 ]
then
#clean up for previous build
rm -R build-native-gcc9
fi
mkdir build-native-gcc9
cd build-native-gcc9
../gcc-9.2.0/configure --prefix=/opt/gcc-9.2.0 --build=$MACHTYPE --host=arm-linux-gnueabihf --target=arm-linux-gnueabihf --enable-languages=c,c++,fortran --with-arch=armv6 --with-fpu=vfp --with-float=hard --disable-multilib --program-suffix=-9.2
make -j 8
make install-strip

#If you want to permanently add the cross compiler to your path, use something like:
echo 'export PATH=/opt/cross-pi-gcc/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

#You can now, optionally, safely erase the build folder
cd ~
rm -rf gcc_all

#Let’s archive the native GCC ARM compiler and save it to our home folder:
cd /opt
tar -cjvf ~/gcc-9.2.0-armhf-raspbian.tar.bz2 gcc-9.2.0

# clean up the build system
sudo rm -R gcc-9.2.0
cd ~

#Copy gcc-9.2.0-armhf-raspbian.tar.bz2 to your RPi.
#====================================================
# For the remaining of this article I’ll assume you are on your RPi
# and that the above archive is in your home folder:
cd ~
tar xvf gcc-9.2.0-armhf-raspbian.tar.bz2
#====== uncomment the next line if you do not want to save your zip'd file
#rm gcc-9.2.0-armhf-raspbian.tar.bz2
sudo mv gcc-9.2.0 /opt

#Next, we are going to add the new compilers to the path and create a few symbolic links
echo 'export PATH=/opt/gcc-9.2.0/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/opt/gcc-9.2.0/lib:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
sudo ln -s /usr/include/arm-linux-gnueabihf/sys /usr/include/sys
sudo ln -s /usr/include/arm-linux-gnueabihf/bits /usr/include/bits
sudo ln -s /usr/include/arm-linux-gnueabihf/gnu /usr/include/gnu
sudo ln -s /usr/include/arm-linux-gnueabihf/asm /usr/include/asm
sudo ln -s /usr/lib/arm-linux-gnueabihf/crti.o /usr/lib/crti.o
sudo ln -s /usr/lib/arm-linux-gnueabihf/crt1.o /usr/lib/crt1.o
sudo ln -s /usr/lib/arm-linux-gnueabihf/crtn.o /usr/lib/crtn.o
cd ~

#At this point, you should be able to invoke the compilers with
# gcc-9.2, g++-9.2 or gfortran-9.2

#Let’s try to compile and run a C++17 code that uses
# an if block with init-statement (the example is a bit silly,
# but it will show you how to compile C++17 programs):
#=========================
echo '#include <iostream>' >if_test.cpp
echo  >>if_test.cpp
echo 'int main() {' >>if_test.cpp
echo '    // if block with init-statement:' >>if_test.cpp
echo '    if(int a = 5; a < 8) {' >>if_test.cpp
echo '        std::cout << "Local variable a is < 8\n";' >>if_test.cpp
echo '    } else {' >>if_test.cpp
echo '        std::cout << "Local variable a is >= 8\n";' >>if_test.cpp
echo '    }' >>if_test.cpp
echo '    return 0;' >>if_test.cpp
echo '}' >>if_test.cpp
#============================

#Save the above code in a file named if_test.cpp and compile it with:
g++-9.2 -std=c++17 -Wall -pedantic ./if_test.cpp -o if_test
./if_test

#OUTPUT =======================
# pi@raspberrypi:~ $ g++-9.2 -std=c++17 -Wall -pedantic if_test.cpp -o if_test
# pi@raspberrypi:~ $ ./if_test
# Local variable a is < 8
echo 'Local variable a is < 8'
# pi@raspberrypi:~ $
#OUTPUT ========================
echo Press any key to continue
read var1

#Let’s also try to use the C++17 filesystem:
#============================
echo '#include <iostream>' >fs_test.cpp
echo '#include <filesystem>' >>fs_test.cpp
echo >>fs_test.cpp
echo 'int main() {' >>fs_test.cpp
echo '   for(auto &file : std::filesystem::recursive_directory_iterator("./")) {' >>fs_test.cpp
echo '       std::cout << file.path() << "\n";' >>fs_test.cpp
echo '   }' >>fs_test.cpp
echo '}' >>fs_test.cpp
#===================================

#Save the above code in a file named fs_test.cpp and compile it with:
g++-9.2 -std=c++17 -Wall -pedantic ./fs_test.cpp -o fs_test
cd Documents
../fs_test
cd ~

#This is what I see on my RPi (don’t run the next code in your home 
# folder if you have a lot of files because it will recursively print
# all of them, for example you can move it in a folder with a smaller numbers of files):
#OUTPUT ========================================================================
# pi@raspberrypi:~ $ g++-9.2 -std=c++17 -Wall -pedantic fs_test.cpp -o fs_test
# pi@raspberrypi:~ $ ./fs_test
# "./.nano"
# "./.profile"
# "./.bash_logout"
# "./fs_test.cpp"
# "./.bashrc"
# "./if_test.cpp"
# "./if_test"
# "./fs_test"
# "./.bash_history"
# pi@raspberrypi:~ $
#OUTPUT =================================


