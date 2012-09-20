#!/bin/bash -l
#SBATCH -A b2010028
#SBATCH -p node
#SBATCH -N 1
#SBATCH -n 8
#SBATCH --qos=b2010028_4nodes
#SBATCH -C mem24GB
#SBATCH -t 00:30:00
#SBATCH -J setup_SNPSEQ_pipeline
#SBATCH -o setup-%j.out
#SBATCH -e setup-%j.error

# Very simple setup script to download the latest version of the custom gatk version and build it.

# This will give an error if run locally - but never mind. It works any way...
module load java/sun_jdk1.6.0_18
module load ant/1.8.1

# Clone my gatk repository - getting the stable branch.
# TODO When there is a stable version. Make sure to change to that...
git clone https://github.com/johandahlberg/gatk.git -b devel gatk 
git checkout sp_0.0.1
#Setup the ant maximum java heap size
ANT_OPTS=-Xmx24G

# Compile gatk
cd gatk
ant



