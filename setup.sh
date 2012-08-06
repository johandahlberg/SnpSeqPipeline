#!/bin/bash

# Very simple setup script to download the latest version of the custom gatk version and build it.

# Clone my gatk repository - getting the stable branch.
# TODO When there is a stable version. Make sure to change to that...
git clone git@github.com:johandahlberg/gatk.git -b devel gatk

cd gatk
ant && ant queue


