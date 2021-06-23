#!/bin/bash
#
#  This script downloads and builds statically linked libraries for image and data processing
#
#  (C) Copyright 2021 Physikalisch-Technische Bundesanstalt 
#  Christian Gollwitzer
#  
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
# 
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
# 
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <https://www.gnu.org/licenses/>. 
#
#  The resulting builds are subject to the respectve licenses of the libraries
#

# On Linux and macOS, requires a typical build environment + CMake. 
# 
# On Windows, install the git SDK and cmake via:
# wget https://github.com/Kitware/CMake/releases/download/v3.15.0-rc3/cmake-3.15.0-rc3-win64-x64.zip
# unzip cmake-3.15.0-rc3-win64-x64.zip
# PATH=$PWD/cmake-3.15.0-rc3-win64-x64/bin:$PATH

# 
ZLIB=zlib-1.2.8
JPEG=jpeg-8d
JPEGSRC=jpegsrc.v8d
# for jpeg, there is a mismatch between the file name and the TLD name
TIFF=tiff-4.3.0
PNG=libpng-1.6.2
HDF4=hdf-4.2.15
HDF5=hdf5-1.8.21

# use HDF5-1.8 because 1.10 causes problems with simultaneous reading

PKGURLS=(
 $ZLIB $ZLIB.tar.gz https://www.zlib.net/fossils/$ZLIB.tar.gz 44d667c142d7cda120332623eab69f40
 $JPEG $JPEGSRC.tar.gz http://www.ijg.org/files/$JPEGSRC.tar.gz a9b1082e69db9920714b24e89066c7d3
 $TIFF $TIFF.tar.gz http://download.osgeo.org/libtiff/$TIFF.tar.gz 0a2e4744d1426a8fc8211c0cdbc3a1b3
 $PNG $PNG.tar.gz "http://prdownloads.sourceforge.net/libpng/$PNG.tar.gz?download" b9f33116aafde244d04caf1ee19eb573
 $HDF4 $HDF4.tar.bz2 https://support.hdfgroup.org/ftp/HDF/releases/HDF4.2.15/src/$HDF4.tar.bz2 27ab87b22c31906883a0bfaebced97cb
 $HDF5 $HDF5.tar.bz2 https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.8/$HDF5/src/$HDF5.tar.bz2 2d2408f2a9dfb5c7b79998002e9a90e9
)


# enable parallel build, if it is not set
if [ -z "$MAKEFLAGS" ]; then 
	export MAKEFLAGS=-j8
fi

# find the top of the build dir
topdir=$(dirname "$0")
cd "$topdir"
topdir=$(pwd)

# define the output file
machine=$(uname -sm | tr ' ' '-')
pkgname="StaticImglibs_$machine"
pkgdir="$topdir/$pkgname"
pkgfile="$pkgdir.tar.bz2"

srcdir="$topdir/sources"
mkdir -p "$srcdir"

# check for Windows
case `uname` in
	mingw*|MINGW*)
		windows=true
		;;
	*)
		windows=false
		;;
esac

# check for md5sum 
echo "Checking for md5 program..."
if command -v md5sum; then
	MD5=md5short
elif command -v md5; then
	MD5="md5 -q"
else
	echo "MD5 not found"
	exit -1
fi

function md5short() {
	md5sum "$1" | awk '{print $1}'
}

function download() {
	# FILE URL HASH
	file="$1"
	ofile="$srcdir/$file"
	URL="$2"
	HASH="$3"

	if [ -e "$ofile" ]; then 
		# it's already there - check the download
		RETHASH=$( $MD5 "$ofile")
		if [ "$HASH" = "$RETHASH" ]; then 
			# file is complete
			return
		else 
			# file has wrong MD5
			echo "$file is damaged - expecting $HASH, found $RETHASH. Redownloading"
			rm -f "$ofile"
		fi
	fi

	wget -O "$ofile" "$URL"

	RETHASH=$( $MD5 "$ofile")

	if [ "$HASH" != "$RETHASH" ]; then
		echo "Failed to download $file from $URL -> Hashes don't match"
		echo "Expected $HASH, got $RETHASH"
		exit -1
	fi
}

function downloadlist() {
	while ! [ -z "$1" ]; do
		download "$2" "$3" "$4"
		PKGS+=( "$1" )
		PKGTARS+=( "$2" )
		shift 4 
	done
}

downloadlist ${PKGURLS[@]}


# untar and patch
for i in ${!PKGS[@]}; do
	pkg=${PKGS[$i]}
	tar="$srcdir/${PKGTARS[$i]}"
	rm -rf "$srcdir/$pkg"
	tar -xvf "$tar" -C "$srcdir"

	PATCH="$topdir/$pkg.patch"
	if [ -e "$pkg.patch" ]; then
		cd "$srcdir/$pkg"
		patch -p1 < "$PATCH"
	fi
done

# create build directory
rm -rf build hdf4_build hdf5_build "$pkgdir"
mkdir -p build


# make zlib
cd "$srcdir/$ZLIB"
CFLAGS="-fPIC" ./configure --static --64 --prefix="$topdir/build"
make && make install
cd $topdir

cd "$srcdir/$JPEG"
./configure --enable-static --disable-shared --with-pic \
	--prefix="$topdir/build" \
	--includedir="$topdir/build/include" \
	--libdir="$topdir/build/lib"
make && make install
cd $topdir

cd "$srcdir/$PNG"
./configure --enable-static --disable-shared --with-pic \
	--prefix="$topdir/build" \
	--includedir="$topdir/build/include" \
	--libdir="$topdir/build/lib"
make && make install
cd $topdir

cd "$srcdir/$TIFF"
./configure --enable-static --disable-shared --prefix=$topdir/build --with-pic --without-x \
	--includedir="$topdir/build/include" \
	--libdir="$topdir/build/lib" \
	--with-zlib-include-dir="$topdir/build/include" \
	--with-zlib-lib-dir="$topdir/build/lib" \
	--with-jpeg-include-dir="$topdir/build/include" \
	--with-jpeg-lib-dir="$topdir/build/lib" \
	--disable-cxx 
	
make && make install
cd "$topdir"

## HDF4
if [ "X$autoconf_hdf4" = "Xyes" ]; then 
cd "$srcdir/$HDF4"
./configure LIBS=$HDF4_EXTRA_LIBS --enable-static --disable-shared --prefix=$topdir/build --with-pic \
	--disable-fortran \
	--disable-netcdf \
	--disable-hdf4-xdr \
	--includedir="$topdir/build/include" \
	--libdir="$topdir/build/lib" \
	--with-zlib="$topdir/build/" \
	--with-jpeg="$topdir/build/" && \
make && make install
cd "$topdir"
else

	if $windows; then 
		generator="MSYS Makefiles"
	else
		generator="Unix Makefiles"
	fi

	# Try using cmake
	mkdir -p hdf4_build
	cd hdf4_build
	cmake \
	    -Wno-dev \
	    -DPOSITION_INDEPENDENT_CODE:BOOL=ON \
	    -DBUILD_SHARED_LIBS:BOOL=OFF \
	    -DCMAKE_BUILD_TYPE:STRING=Release \
	    -DHDF4_BUILD_FORTRAN:BOOL=OFF \
	    -DHDF4_ENABLE_SZIP_SUPPORT:BOOL=OFF \
	    -DHDF4_ENABLE_Z_LIB_SUPPORT:BOOL=ON \
	    -DZLIB_ROOT:PATH="$topdir/build/" \
	    -DJPEG_ROOT:PATH="$topdir/build/" \
	    "-G$generator" \
	    -DCMAKE_INSTALL_PREFIX:PATH="$topdir/build/" \
	    "$srcdir/$HDF4"
	make install
	cd "$topdir"

fi

## HDF5
if $windows; then
	# on Windows MINGW, cmake must be used to compile HDF5
	# autoconf does not work there

	# Further, a patch is necessary for gcc to support
	# a VC++ variadic macro extension
	#cd sources/$HDF5/
	#patch -p1 < ../../$HDF5.patch
	#cd ../..

	mkdir hdf5_build
	cd hdf5_build
	cmake \
	    -Wno-dev \
	    -DBUILD_SHARED_LIBS:BOOL=OFF \
	    -DCMAKE_BUILD_TYPE:STRING=Release \
	    -DHDF5_BUILD_HL_LIB:BOOL=ON \
	    -DHDF5_BUILD_FORTRAN:BOOL=OFF \
	    -DHDF5_ENABLE_F2003:BOOL=OFF \
	    -DHDF5_BUILD_CPP_LIB:BOOL=ON \
	    -DHDF5_BUILD_TOOLS:BOOL=ON \
	    -DHDF5_ENABLE_SZIP_SUPPORT:BOOL=OFF \
	    -DHDF5_ENABLE_Z_LIB_SUPPORT:BOOL=ON \
	    -DZLIB_ROOT:PATH=$topdir/build/ \
	    -G"MSYS Makefiles" \
	    -DCMAKE_INSTALL_PREFIX:PATH="$topdir/build/" \
	    ../sources/$HDF5
	make install


else
	cd "$srcdir/$HDF5"
	./configure --enable-static --disable-shared --prefix=$topdir/build --with-pic \
		--disable-fortran \
		--includedir="$topdir/build/include" \
		--libdir="$topdir/build/lib" \
		--with-zlib="$topdir/build/" \
		--enable-cxx
		
	make && make install
	cd "$topdir"

fi

# now package the compiled libraries into a tarball
mkdir "$pkgdir"
cp -r "$topdir/build/include"  "$topdir/build/lib" "$topdir/build/share" "$pkgdir"
tar cvjf "$pkgfile" -C "$topdir" "$pkgname"
