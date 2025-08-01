#!/bin/bash
#
#  This script downloads and builds statically linked libraries for image and data processing
#
#  (C) Copyright 2021 Physikalisch-Technische Bundesanstalt (PTB)
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
ZLIB=zlib-1.3.1
JPEG=jpeg-9f
JPEGSRC=jpegsrc.v9f
# for jpeg, there is a mismatch between the file name and the TLD name
TIFF=tiff-4.7.0
PNG=libpng-1.6.50
HDF4VERSION=hdf4.3.0
HDF4=hdf4-$HDF4VERSION  # toplevel dir for 4.3 series is different
HDF5=hdf5-1.8.23

# use HDF5-1.8 because 1.10 causes problems with simultaneous reading


# List of packages to build. Package name, URL, MD5 of source, path to license
PKGURLS=(
 $ZLIB $ZLIB.tar.gz https://www.zlib.net/fossils/$ZLIB.tar.gz 9855b6d802d7fe5b7bd5b196a2271655 README
 $JPEG $JPEGSRC.tar.gz http://www.ijg.org/files/$JPEGSRC.tar.gz 9ca58d68febb0fa9c1c087045b9a5483 README
 $TIFF $TIFF.tar.gz http://download.osgeo.org/libtiff/$TIFF.tar.gz 3a0fa4a270a4a192b08913f88d0cfbdd LICENSE.md
 $PNG $PNG.tar.gz "http://prdownloads.sourceforge.net/libpng/$PNG.tar.gz?download" eef2d3da281ae83ac8a8f5fd9fa9d325 LICENSE
 $HDF4 $HDF4.tar.bz2 https://github.com/HDFGroup/hdf4/archive/refs/tags/$HDF4VERSION.tar.gz 9789b5ad3341ce5f25fac1de231e2608 COPYING
 $HDF5 $HDF5.tar.bz2 https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.8/$HDF5/src/$HDF5.tar.bz2 66bc4a02321fd41281a78e2bb25ef039 COPYING
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
distdir="$topdir/dist"
mkdir -p "$distdir"
pkgfile="$distdir/$pkgname.tar.bz2"

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

	curl "$URL" -LJo "$ofile" 

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
		LICENSES+=( "$5" )
		shift 5
	done
}

downloadlist ${PKGURLS[@]}

# untar and patch
for i in ${!PKGS[@]}; do
	pkg=${PKGS[$i]}
	tar="$srcdir/${PKGTARS[$i]}"
	rm -rf "$srcdir/$pkg"
        echo "Untarring $pkg"

	tar -xf "$tar" -C "$srcdir"

	PATCH="$topdir/$pkg.patch"
	if [ -e "$PATCH" ]; then
                echo "Patching $pkg"
		cd "$srcdir/$pkg"
		patch -p1 < "$PATCH"
	fi
done

# create build directory
rm -rf build hdf4_build hdf5_build "$pkgdir"
mkdir -p build

function runmake() {
    # exit with error in case make fails
    if ! make "$@"; then
        echo "***Error: Make $@ failed"
        exit -1
    fi
}

function runcp() {
    # exit with error in case make fails
    if ! cp "$@"; then
        echo "***Error: Copy $@ failed"
        exit -1
    fi
}

# make zlib
cd "$srcdir/$ZLIB"
CFLAGS="-fPIC" ./configure --static --64 --prefix="$topdir/build"
runmake
runmake install
cd $topdir

cd "$srcdir/$JPEG"
./configure --enable-static --disable-shared --with-pic \
	--prefix="$topdir/build" \
	--includedir="$topdir/build/include" \
	--libdir="$topdir/build/lib"
runmake
runmake install
cd $topdir

cd "$srcdir/$PNG"
./configure --enable-static --disable-shared --with-pic \
	--prefix="$topdir/build" \
	--includedir="$topdir/build/include" \
	--libdir="$topdir/build/lib"
runmake
runmake install
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
	
runmake
runmake install
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
runmake
runmake install
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
	CFLAGS=-Wno-implicit-function-declaration cmake \
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
        runmake install
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
	CFLAGS="-Wno-implicit-function-declaration -D_GNU_SOURCE=1" cmake \
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
        runmake install


else
	cd "$srcdir/$HDF5"
	./configure --enable-static --disable-shared --prefix=$topdir/build --with-pic \
		--disable-fortran \
		--includedir="$topdir/build/include" \
		--libdir="$topdir/build/lib" \
		--with-zlib="$topdir/build/" \
		--enable-cxx
		
        runmake
        runmake install
	cd "$topdir"

fi

# now package the compiled libraries into a tarball
mkdir -p "$pkgdir"
licdir="$pkgdir/licenses"
mkdir -p "$licdir"

# copy the license files of the libraries

for i in ${!PKGS[@]}; do
	pkg=${PKGS[$i]}
	lic="$srcdir/$pkg/${LICENSES[$i]}"
	runcp "$lic" "$licdir/license.terms.$pkg"
done

cp -r "$topdir/build/include"  "$topdir/build/lib" "$topdir/build/share" "$pkgdir"
tar cvjf "$pkgfile" -C "$topdir" "$pkgname"
