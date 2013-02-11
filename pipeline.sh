#!/bin/bash -l
#SBATCH -A a2009002
#SBATCH -p core
#SBATCH -n 1
#SBATCH -t 120:00:00
#SBATCH -J snp_seq_pipeline_controller
#SBATCH -o pipeline-%j.out
#SBATCH -e pipeline-%j.error
#SBATCH --qos=seqver

# Start by exporting the shared drmaa libaries to the LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/bubo/sw/apps/build/slurm-drmaa/lib/:$LD_LIBRARY_PATH

# We also need the correct java engine and R version
module load java/sun_jdk1.6.0_18
module load R/2.15.0
module load bioinfo-tools
module load bwa/0.6.2
module load samtools/0.1.18

# TODO Clean up all paths to that they are relative to run folder

#---------------------------------------------
# Run template - setup which files to run etc
#---------------------------------------------

PIPELINE_SETUP_XML="pipelineSetup.xml"
PROJECT_NAME="TestProject"
PROJECT_ID="a2009002"
# Note that it's important that the last / is included in the root dir path
PROJECT_ROOT_DIR="/local/data/SnpSeqPipelineIntegrationTestData/"
GATK_BUNDLE="/local/data/gatk_bundle/b37"
GENOME_REFERENCE=${GATK_BUNDLE}"/human_g1k_v37.fasta"
DB_SNP=${GATK_BUNDLE}"/dbsnp_137.b37.vcf"
MILLS=${GATK_BUNDLE}"/Mills_and_1000G_gold_standard.indels.b37.vcf"
ONE_K_G=${GATK_BUNDLE}"/1000G_phase1.indels.b37.vcf"
INTERVALS=""

#---------------------------------------------
# Check if we are running on uppmax or locally, and set the jobrunners and path accordingly
#---------------------------------------------
if [ -f "/bubo/sw/apps/build/slurm-drmaa" ];
then
	JOB_RUNNER=" Drmaa -jobNative '-A b2010028 -p node -N 1 --qos=seqver'"
	PATH_TO_BWA="/bubo/sw/apps/bioinfo/bwa/0.6.2/kalkyl/bwa"
	PATH_TO_SAMTOOLS="/bubo/sw/apps/bioinfo/samtools/0.1.12-10/samtools"
else
	JOB_RUNNER=" Shell"
	PATH_TO_BWA="/usr/bin/bwa"
	PATH_TO_SAMTOOLS="/usr/bin/samtools"
fi



#---------------------------------------------
# Unless there exists a pipeline setup file, try to create one
#---------------------------------------------

if [ ! -f ${PIPELINE_SETUP_XML} ];
then
	./fixPipelineSetup.py -p ${PROJECT_NAME} -i ${PROJECT_ID}  -R ${GENOME_REFERENCE} -r ${PROJECT_ROOT_DIR} > ${PIPELINE_SETUP_XML}
fi

#---------------------------------------------
# Global variables
#---------------------------------------------

# Note that the tmp folder needs to be placed in a location that can be reached from all nodes.
# Note that $SNIC_TMP cannot be used since that will lose necessary data as the nodes/core switch.
TMP=tmp/${SLURM_JOB_ID}/

# Comment and uncomment DEBUG to enable/disable the debugging mode of the pipeline.
DEBUG="-l DEBUG" # -startFromScratch"

# Setup temporary directory for the the Qscript tmp files.
# This will be removed as long as the script dies gracefully 
# (if it is killed with a kill -9, manual clean up will have to be run...)
function clean_up {
	# Perform program exit housekeeping
	rm -r ${TMP}
	exit
}

if [ ! -d "${TMP}" ]; then
   mkdir tmp
   mkdir ${TMP}
fi
JAVA_TMP="-Djava.io.tmpdir="${TMP}

#This will execute the removal of the tmp directory
trap clean_up SIGHUP SIGINT SIGTERM

QUEUE="${PWD}/gatk/dist/Queue.jar"
SCRIPTS_DIR="${PWD}/gatk/public/scala/qscript/org/broadinstitute/sting/queue/qscripts"
NBR_OF_THREADS=16

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

#TODO Fix mechanism for setting walltimes.

#------------------------------------------------------------------------------------------
# Align fastq files using bwa - outputs bam files.
#------------------------------------------------------------------------------------------
java ${JAVA_TMP} -jar ${QUEUE} -S ${SCRIPTS_DIR}/AlignWithBWA.scala \
			-i ${PIPELINE_SETUP_XML} \
			-outputDir ${RAW_BAM_OUTPUT}/ \
			-bwa ${PATH_TO_BWA} \
			-samtools ${PATH_TO_SAMTOOLS} \
			-bwape \
			--bwa_threads ${NBR_OF_THREADS} \
			-jobRunner ${JOB_RUNNER} \
			--job_walltime 345600 \
			-run \
			${DEBUG}


# Check the script exit status, and if it did not finish, clean up and exit
if [ $? -ne 0 ]; then 
	echo "Caught non-zero exit status from AlignWithBwa. Cleaning up and exiting..."
	clean_up
	exit 1
fi

#------------------------------------------------------------------------------------------
# NOTE: These parts of the analysis does not yet suport the xml based setup.
#       Running them will require manually setting up path etc.
#------------------------------------------------------------------------------------------

#------------------------------------------------------------------------------------------
# Data preprocessing
#------------------------------------------------------------------------------------------
java ${JAVA_TMP} -jar ${QUEUE} -S ${SCRIPTS_DIR}/DataProcessingPipeline.scala \
			  -R ${GENOME_REFERENCE} \
			  --project ${PROJECT_NAME} \
			  -i ${RAW_BAM_OUTPUT}/${PROJECT_NAME}.cohort.list \
			  -outputDir ${PROCESSED_BAM_OUTPUT}/ \
			  --dbsnp ${DB_SNP} \
                          --extra_indels ${MILLS} \
                          --extra_indels ${ONE_K_G} \
			  -intervals ${INTERVALS} \
			  -cm USE_SW \
			  -run \
			  -jobRunner ${JOB_RUNNER} \
			  --job_walltime 86400 \
			  -nt ${NBR_OF_THREADS} \
			  ${DEBUG}

# Check the script exit status, and if it did not finish, clean up and exit
if [ $? -ne 0 ]; then 
        echo "Caught non-zero exit status from DataProcessingPipeline. Cleaning up and exiting..."
        clean_up
        exit 1
fi

#------------------------------------------------------------------------------------------
# Run variant calling
#------------------------------------------------------------------------------------------
java ${JAVA_TMP} -jar ${QUEUE} -S ${SCRIPTS_DIR}/VariantCalling.scala \
			  -R ${GENOME_REFERENCE} \
			  -res ${GATK_BUNDLE} \
			  --project ${PROJECT_NAME} \
			  -i ${PROCESSED_BAM_OUTPUT}/${PROJECT_NAME}.cohort.list \
			  -intervals ${INTERVALS} \
			  -outputDir ${VCF_OUTPUT}/ \
			  -run \
			  -jobRunner ${JOB_RUNNER} \
			  --job_walltime 3600 \
			  -nt  ${NBR_OF_THREADS} \
			  -retry 2 \
			  ${DEBUG}

# Check the script exit status, and if it did not finish, clean up and exit
if [ $? -ne 0 ]; then 
        echo "Caught non-zero exit status from VariantCalling. Cleaning up and exiting..."
        clean_up
        exit 1
fi



# Move all the report files generated by Queue into a separate directory
if [ ! -d "reports" ]; then
   mkdir "reports"
fi

mv *.jobreport.* reports/

# Remove the file temporary directory - otherwise it will fill up glob. And all the files which are required for
# the pipeline to run are written to the pipeline directory.
clean_up
