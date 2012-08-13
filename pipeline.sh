#!/bin/bash -l
#SBATCH -A b2010028
#SBATCH -p core
#SBATCH -n 1
#SBATCH -t 48:00:00
#SBATCH --qos=b2010028_4nodes
#SBATCH -J snp_seq_pipeline_controller

# Start by exporting the shared drmaa libaries to the LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/bubo/sw/apps/build/slurm-drmaa/lib/:$LD_LIBRARY_PATH

# We also need the correct java engine and R version
module load java/sun_jdk1.6.0_18
module load R/2.15.0
module load bioinfo-tools
module load bwa/0.6.2 

# TODO Clean up all paths to that they are relative to run folder

#---------------------------------------------
# Run template - setup which files to run etc
#---------------------------------------------
PROJECT_NAME="test_pipeline"
PATH_TO_FASTQ="/bubo/home/h10/joda8933/glob/private/pipelineTestFolder"
GENOME_REFERENCE="/bubo/home/h10/joda8933/glob/Data/concat.fasta"
DB_SNP="/bubo/home/h10/joda8933/glob/Data/dbSNP_all.vcf"
# Note that the tmp folder needs to be placed in a location that can be reached from all nodes, e.g. glob
# Note that $SNIC_TMP cannot be used since that will lose necessary data as the nodes/core switch.
TMP=/bubo/home/h10/joda8933/glob/tmp/$SLURM_JOB_ID/

#---------------------------------------------
# Global variables
#---------------------------------------------

# Comment and uncomment DEBUG to enable/disable the debugging mode of the pipeline.
DEBUG="-l DEBUG -startFromScratch"

# Setup temporary directory for the the Qscript tmp files.
# This will be removed as long as the script dies gracefully 
# (if it is killed with a kill -9, manual clean up will have to be run...)
function clean_up {
	# Perform program exit housekeeping
	rm -r ${TMP}
	exit
}

if [ ! -d "${TMP}" ]; then
   mkdir ${TMP}
fi
JAVA_TMP="-Djava.io.tmpdir="${TMP}

#This will execute the removal of the tmp directory
trap clean_up SIGHUP SIGINT SIGTERM

QUEUE="${PWD}/gatk/dist/Queue.jar"
SCRIPTS_DIR="${PWD}/gatk/public/scala/qscript/org/broadinstitute/sting/queue/qscripts"
PATH_TO_BWA="/bubo/sw/apps/bioinfo/bwa/0.6.2/kalkyl/bwa"
NBR_OF_BRA_THREADS=8

# Setup directory structure
RAW_BAM_OUTPUT="bam_files_raw"
PROCESSED_BAM_OUTPUT="bam_files_processed"
VCF_OUTPUT="vcf_files"

if [ ! -d "${RAW_BAM_OUTPUT}" ]; then
   mkdir ${RAW_BAM_OUTPUT}
fi

if [ ! -d "${PROCESSED_BAM_OUTPUT}" ]; then
   mkdir ${PROCESSED_BAM_OUTPUT}
fi

if [ ! -d "${VCF_OUTPUT}" ]; then
   mkdir ${VCF_OUTPUT}
fi

#------------------------------------------------------------------------------------------
# fastq2bam - converts fastq files in input directory to unaligned bam files
#------------------------------------------------------------------------------------------
java ${JAVA_TMP} -jar ${QUEUE} -S ${SCRIPTS_DIR}/Fastq2Bam.scala --project ${PROJECT_NAME} -f ${PATH_TO_FASTQ} -outputDir ${RAW_BAM_OUTPUT}/ ${DEBUG} -jobRunner Drmaa -pid b2010028 --job_walltime 86400 -run

#------------------------------------------------------------------------------------------
# Data preprocessing
#------------------------------------------------------------------------------------------
java ${JAVA_TMP} -jar ${QUEUE} -S ${SCRIPTS_DIR}/DataProcessingPipeline.scala \
			  -R ${GENOME_REFERENCE} \
			  --project ${PROJECT_NAME} \
			  -i ${RAW_BAM_OUTPUT}/${PROJECT_NAME}.cohort.list \
			  -outputDir ${PROCESSED_BAM_OUTPUT}/ \
			  --dbsnp ${DB_SNP} \
			  -bwa ${PATH_TO_BWA} \
			  --use_bwa_pair_ended \
			  --bwa_threads ${NBR_OF_BRA_THREADS} \
			  -cm USE_SW \
			  -run \
			  -jobRunner Drmaa -jobNative '-A b2010028 -p node -N 1' \
			  --job_walltime 86400 \
			  -nt 8 \
			  ${DEBUG}
#------------------------------------------------------------------------------------------
# Run variant calling
#------------------------------------------------------------------------------------------
java ${JAVA_TMP} -jar ${QUEUE} -S ${SCRIPTS_DIR}/VariantCalling.scala \
			  -R ${GENOME_REFERENCE} \
			  --project ${PROJECT_NAME} \
			  -i ${PROCESSED_BAM_OUTPUT}/${PROJECT_NAME}.cohort.list \
			  -outputDir ${VCF_OUTPUT}/ \
			  -run \
			  -jobRunner Drmaa -jobNative '-A b2010028 -p node -N 1' \
			  --job_walltime 86400 \
			  -nt 8 \
			  ${DEBUG}


# Move all the report files generated by Queue into a separate directory
if [ ! -d "reports" ]; then
   mkdir "reports"
fi

mv *.jobreport.* reports/

# Remove the file temporary directory - otherwise it will fill up glob. And all the files which are required for
# the pipeline to run are written to the pipeline directory.
clean_up
