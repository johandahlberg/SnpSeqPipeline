SnpSeqPipeline
==============

This is a prototype for a variant calling pipeline for the SNP&SEQ Technology Platform at Uppsala University. Please note that nothing here is finished at this point, and that a lot of things might change before this is actually used.

The pipeline is built on GATK Queue, and is basically just a bash script which chains together a number of QScripts.

Basic usage
-----------

To setup and use this pipeline on UPPMAX you need to follow these step.

1. Clone this repository: `git clone git@github.com:johandahlberg/SnpSeqPipeline.git`
2. Move into the repository and setup you sbatch parameters in the setup.sh script. Then run it using `sbatch setup.sh`. This will download a custom version of GATK and compile it on a node.
3. Go on and have coffee, your code is compiling. ;)
4. When this is finished you should have a directory called gatk in you pipeline directory. Look in the slurm log file, and make sure that it says "BUILD SUCCESSFUL".
5. Open the pipeline.sh script and edit it so that you have the correct sbatch parameters at the top, and that variables in the "Run template" section are pointing to the files and directories which you want to use in your analysis.
6. Run the pipeline using `sbatch pipeline.sh`
