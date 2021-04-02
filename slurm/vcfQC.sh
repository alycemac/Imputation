#!/usr/bin/env bash

#! RUN : sbatch vcfQC.sh <TAG> <CHR>

#! sbatch directives begin here ###############################
#! Name of the job:
##SBATCH -J vcfQC
#! Which project should be charged:
#SBATCH -A GODOGS-SL2-CPU
#! How many whole nodes should be allocated?
#SBATCH --nodes=1
#! How many (MPI) tasks will there be in total? (<= nodes*32)
#! The skylake/skylake-himem nodes have 32 CPUs (cores) each.
#SBATCH --ntasks=1
#! How much wallclock time will be required?
#SBATCH --time 1:00:00
#! What types of email messages do you wish to receive?
#SBATCH --mail-type=ALL
#! Uncomment this to prevent the job from being requeued (e.g. if
#! interrupted by node failure or system downtime):
##SBATCH --no-requeue
#! For 6GB per CPU, set "-p skylake"; for 12GB per CPU, set "-p skylake-himem":
#SBATCH -p skylake

#SBATCH -o logs/job-%j.out

module purge                               # Removes all modules still loaded
module load rhel7/default-peta4            # REQUIRED - loads the basic environment

module load bcftools-1.9-gcc-5.4.0-b2hdt5n        # bcftools
module load tabix-2013-12-16-gcc-5.4.0-xn3xiv7    # bgzip/tabix
module load plink-1.9-gcc-5.4.0-sm3ojoi           # plink/plinkdog

ID=$1
CHR=$2
source ${ID}.config

# rm -rf $ID
# mkdir $ID; cd $ID
mkdir step1; cd step1

# filter SNPS & annotate ID
bcftools view -m2 -M2 -v snps ${VCF} | bcftools filter -e "QUAL < 20" | bcftools annotate --set-id +'%CHROM:%POS' | bgzip -c > chr${CHR}.snps.id.vcf.gz

# vcf2PLINK
plinkdog --const-fid 0 --vcf chr${CHR}.snps.id.vcf.gz --out ${ID}.1

# remove duplicate SNPs
grep -v '#' ${ID}.1.bim | cut -f 2 | sort | uniq -d > snps.dups
plinkdog --bfile ${ID}.1 --exclude snps.dups --make-bed --out ${ID}.2

# rename & filter SNPs 
cut -f 2 ${ID}.2.bim | perl -lane '$col1 = $_; $_ =~ s/chr//g; print $col1."\t".$_;' > snps.map  
plinkdog --bfile ${ID}.2 --make-bed --update-map snps.map --update-name --mind 0.1 --out ${ID}.3

# create file of original reference alleles
bcftools query --format '%ID\t%REF\n' chr${CHR}.snps.id.vcf.gz > ref-alleles
perl -lane '$_ =~ s/chr//; print $_;' ref-alleles > tmp
mv tmp ref-alleles 

# convert back to VCF
plinkdog --bfile ${ID}.3 --recode vcf-iid --a2-allele ref-alleles --real-ref-alleles --out ${ID}
bgzip -f ${ID}.vcf; tabix -p vcf ${ID}.vcf.gz

# export BED file of SNPs
awk -v OFS="\t" '{print $1, $4-1, $4, $2}' ${ID}.3.bim > ${ID}.snps.bed

cp ${ID}.snps.bed ../
cp ${ID}.vcf.gz* ../